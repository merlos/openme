/**
 * @file openmelib.c
 * @brief openme SPA knock protocol — C implementation.
 *
 * Crypto back-end: Monocypher 4 (X25519, ChaCha20-Poly1305, Ed25519) +
 * bundled SHA-256/HMAC/HKDF for HKDF-SHA-256 key derivation.
 *
 * Platform support matrix (see openmelib.h for details):
 *   RNG   : Linux (getrandom), macOS (arc4random_buf), Windows (BCrypt),
 *            ESP32 Arduino / ESP-IDF (esp_fill_random), bare-metal (user hook)
 *   Time  : Linux/macOS (clock_gettime), Windows (GetSystemTimeAsFileTime),
 *            ESP32/lwIP (gettimeofday), bare-metal (user hook)
 *   Send  : POSIX sockets, Windows Winsock2, lwIP
 */

#include "../include/openmelib.h"
#include "openme_sha256.h"
#include "monocypher.h"

#include <stdio.h>
#include <string.h>
#include <stddef.h>

/* ═══════════════════════════════════════════════════════════════════════════
 * Compile-time target detection
 * ═══════════════════════════════════════════════════════════════════════════ */

#if defined(_WIN32) || defined(_WIN64)
#  define OPENME_PLATFORM_WINDOWS 1
#elif defined(ESP_PLATFORM) || defined(ARDUINO_ARCH_ESP32)
#  define OPENME_PLATFORM_ESP32   1
#elif defined(ARDUINO)
#  define OPENME_PLATFORM_ARDUINO 1
#elif defined(__unix__) || defined(__APPLE__)
#  define OPENME_PLATFORM_POSIX   1
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * Protocol constants
 * ═══════════════════════════════════════════════════════════════════════════ */

static const uint8_t HKDF_INFO[] = "openme-v1-chacha20poly1305";
/* length excludes NUL terminator — matches other SDK implementations */
#define HKDF_INFO_LEN  (sizeof(HKDF_INFO) - 1)

/* ═══════════════════════════════════════════════════════════════════════════
 * openme_build_packet — fully deterministic, no OS calls
 * ═══════════════════════════════════════════════════════════════════════════ */

int openme_build_packet(
    uint8_t       out[OPENME_PACKET_SIZE],
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    int64_t       timestamp_ns,
    const uint8_t ephem_secret[32],
    const uint8_t aead_nonce[12],
    const uint8_t random_nonce[16],
    const uint8_t target_ip[16])
{
    if (!out || !server_pubkey || !client_seed ||
        !ephem_secret || !aead_nonce || !random_nonce)
        return OPENME_ERR_NULL;

    /* ── 1. Derive ephemeral X25519 public key ────────────────────────── */
    uint8_t ephem_pub[32];
    crypto_x25519_public_key(ephem_pub, ephem_secret);

    /* ── 2. X25519 ECDH → 32-byte shared secret ──────────────────────── */
    uint8_t shared_secret[32];
    crypto_x25519(shared_secret, ephem_secret, server_pubkey);

    /* ── 3. HKDF-SHA-256 → 32-byte symmetric key ─────────────────────── */
    uint8_t sym_key[32];
    openme_hkdf_sha256(
        sym_key, 32,
        shared_secret, 32,
        NULL, 0,                   /* no salt (empty) */
        HKDF_INFO, HKDF_INFO_LEN
    );
    /* wipe shared secret immediately */
    crypto_wipe(shared_secret, sizeof(shared_secret));

    /* ── 4. Build 40-byte plaintext ───────────────────────────────────── */
    uint8_t plaintext[OPENME_PLAINTEXT_SIZE];
    /* timestamp: int64 big-endian nanoseconds */
    plaintext[0] = (uint8_t)((uint64_t)timestamp_ns >> 56);
    plaintext[1] = (uint8_t)((uint64_t)timestamp_ns >> 48);
    plaintext[2] = (uint8_t)((uint64_t)timestamp_ns >> 40);
    plaintext[3] = (uint8_t)((uint64_t)timestamp_ns >> 32);
    plaintext[4] = (uint8_t)((uint64_t)timestamp_ns >> 24);
    plaintext[5] = (uint8_t)((uint64_t)timestamp_ns >> 16);
    plaintext[6] = (uint8_t)((uint64_t)timestamp_ns >>  8);
    plaintext[7] = (uint8_t)((uint64_t)timestamp_ns);
    /* random nonce: 16 bytes */
    memcpy(plaintext + 8, random_nonce, 16);
    /* target IP: 16 bytes (all-zero = use source IP) */
    if (target_ip)
        memcpy(plaintext + 24, target_ip, 16);
    else
        memset(plaintext + 24, 0, 16);

    /* ── 5. ChaCha20-Poly1305 encrypt ────────────────────────────────── */
    /*
     * Monocypher 4 layout:
     *   crypto_aead_lock(cipher_text, mac, key, nonce, ad, ad_size, pt, pt_size)
     * The packet needs ciphertext || mac contiguously at offset 45.
     */
    uint8_t mac[16];
    /* ciphertext goes directly to out + 45; mac goes to out + 45 + 40 = 85 */
    uint8_t ciphertext[OPENME_PLAINTEXT_SIZE]; /* 40 bytes */
    crypto_aead_lock(ciphertext, mac, sym_key, aead_nonce,
                     NULL, 0, plaintext, OPENME_PLAINTEXT_SIZE);

    /* wipe symmetric key */
    crypto_wipe(sym_key, sizeof(sym_key));
    /* wipe plaintext */
    crypto_wipe(plaintext, sizeof(plaintext));

    /* ── 6. Assemble signed portion (101 bytes) ──────────────────────── */
    uint8_t *p = out;
    *p++ = OPENME_VERSION;                   /* offset  0 :  1 B — version  */
    memcpy(p, ephem_pub, 32);   p += 32;     /* offset  1 : 32 B — ephem pub*/
    memcpy(p, aead_nonce, 12);  p += 12;     /* offset 33 : 12 B — nonce    */
    memcpy(p, ciphertext, 40);  p += 40;     /* offset 45 : 40 B — ciphertext*/
    memcpy(p, mac,        16);  p += 16;     /* offset 85 : 16 B — AEAD tag */
    /* p is now at offset 101 = OPENME_SIGNED_SIZE */

    /* ── 7. Ed25519 sign the first 101 bytes ─────────────────────────── */
    /*
     * Monocypher 4: crypto_eddsa_key_pair(secret64, pubkey32, seed32)
     *   seed is consumed/wiped — pass a local copy.
     * The 64-byte secret_key is [seed_clamped(32) || pubkey(32)].
     */
    uint8_t seed_copy[32];
    memcpy(seed_copy, client_seed, 32);
    uint8_t ed_secret64[64];
    uint8_t ed_public[32];
    crypto_eddsa_key_pair(ed_secret64, ed_public, seed_copy);

    uint8_t signature[64];
    crypto_eddsa_sign(signature, ed_secret64, out, OPENME_SIGNED_SIZE);

    /* wipe signing material */
    crypto_wipe(ed_secret64, sizeof(ed_secret64));

    /* ── 8. Append signature → 165-byte packet ───────────────────────── */
    memcpy(p, signature, 64);    /* offset 101 : 64 B — Ed25519 sig         */
    /* p is now at offset 165 = OPENME_PACKET_SIZE */

    (void)p; /* suppress unused warning if compiler doesn't like the math */
    return OPENME_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Platform: RNG
 * ═══════════════════════════════════════════════════════════════════════════ */

#if !defined(OPENME_CUSTOM_RNG)

#if defined(OPENME_PLATFORM_WINDOWS)

#include <windows.h>
#include <bcrypt.h>
#pragma comment(lib, "bcrypt.lib")

void openme_random_bytes(uint8_t *buf, size_t len) {
    BCryptGenRandom(NULL, buf, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
}

#elif defined(OPENME_PLATFORM_ESP32)

#include "esp_random.h"

void openme_random_bytes(uint8_t *buf, size_t len) {
    esp_fill_random(buf, len);
}

#elif defined(OPENME_PLATFORM_ARDUINO)
/* No default — user must define openme_random_bytes().
 * Example using a hardware TRNG peripheral or an entropy source:
 *   void openme_random_bytes(uint8_t *buf, size_t len) { ... }
 * Compile with -DOPENME_CUSTOM_RNG and provide the implementation.
 */
#  warning "openmelib: no default RNG for this Arduino board. " \
           "Define openme_random_bytes() and compile with -DOPENME_CUSTOM_RNG."

void openme_random_bytes(uint8_t *buf, size_t len) {
    /* Fallback: NOT cryptographically secure — replace this! */
    for (size_t i = 0; i < len; i++)
        buf[i] = (uint8_t)(rand() & 0xff);
}

#elif defined(OPENME_PLATFORM_POSIX)

#if defined(__linux__)
#  include <sys/random.h>
#  include <errno.h>
static void posix_getrandom(uint8_t *buf, size_t len) {
    size_t done = 0;
    while (done < len) {
        ssize_t n = getrandom(buf + done, len - done, 0);
        if (n > 0) done += (size_t)n;
    }
}
void openme_random_bytes(uint8_t *buf, size_t len) { posix_getrandom(buf, len); }

#elif defined(__APPLE__)
#  include <stdlib.h>
void openme_random_bytes(uint8_t *buf, size_t len) { arc4random_buf(buf, len); }

#else
/* Generic fallback: /dev/urandom */
#  include <stdio.h>
void openme_random_bytes(uint8_t *buf, size_t len) {
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) { fread(buf, 1, len, f); fclose(f); }
}
#endif

#endif /* OPENME_PLATFORM_* */
#endif /* !OPENME_CUSTOM_RNG */

/* ═══════════════════════════════════════════════════════════════════════════
 * Platform: Time
 * ═══════════════════════════════════════════════════════════════════════════ */

#if !defined(OPENME_CUSTOM_TIME)

#if defined(OPENME_PLATFORM_WINDOWS)

#include <windows.h>
/* Windows FILETIME epoch: Jan 1 1601 → Unix epoch difference = 116444736000000000 100ns intervals */
#define OPENME_FILETIME_EPOCH_DIFF 116444736000000000ULL
int64_t openme_now_ns(void) {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    /* Convert 100-ns intervals since 1601 to nanoseconds since 1970 */
    return (int64_t)((t - OPENME_FILETIME_EPOCH_DIFF) * 100ULL);
}

#elif defined(OPENME_PLATFORM_ESP32) || defined(OPENME_PLATFORM_POSIX)

#include <time.h>
int64_t openme_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

#elif defined(OPENME_PLATFORM_ARDUINO)

/* Arduino has no real-time clock by default.
 * We use millis() plus a compile-time base timestamp so that the knock
 * timestamp is at least monotonically increasing.  For the server to accept
 * the packet the base time must be close to actual UTC.
 *
 * Two options:
 *  A) Set OPENME_UNIX_BASE_NS at compile time (e.g. via cmake or build flag)
 *     to a recent Unix timestamp in nanoseconds, e.g.:
 *       -DOPENME_UNIX_BASE_NS=1709164800000000000LL  (2024-02-29 00:00:00 UTC)
 *  B) Store an NTP-synced time in EEPROM and call openme_set_base_time_ns()
 *     before the first knock.
 */

/* Default base: 2026-01-01 00:00:00 UTC in nanoseconds.
 * Override at compile time: -DOPENME_UNIX_BASE_NS=<value>LL              */
#ifndef OPENME_UNIX_BASE_NS
#  define OPENME_UNIX_BASE_NS ((int64_t)1767225600LL * 1000000000LL)
#endif

static volatile int64_t _openme_base_ns = OPENME_UNIX_BASE_NS;

void openme_set_base_time_ns(int64_t unix_ns) { _openme_base_ns = unix_ns; }

int64_t openme_now_ns(void) {
    return _openme_base_ns + (int64_t)(unsigned long)millis() * 1000000LL;
}

#endif /* OPENME_PLATFORM_* */
#endif /* !OPENME_CUSTOM_TIME */

/* ═══════════════════════════════════════════════════════════════════════════
 * openme_knock_packet — convenience wrapper
 * ═══════════════════════════════════════════════════════════════════════════ */

int openme_knock_packet(
    uint8_t       out[OPENME_PACKET_SIZE],
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16])
{
    uint8_t entropy[32 + 12 + 16]; /* ephem(32) + aead_nonce(12) + random_nonce(16) */
    openme_random_bytes(entropy, sizeof(entropy));

    int64_t ts = openme_now_ns();

    return openme_build_packet(
        out,
        server_pubkey,
        client_seed,
        ts,
        entropy,           /* ephem_secret  : bytes [0..31]  */
        entropy + 32,      /* aead_nonce    : bytes [32..43] */
        entropy + 44,      /* random_nonce  : bytes [44..59] */
        target_ip
    );
}

/* ═══════════════════════════════════════════════════════════════════════════
 * openme_send_knock — UDP socket send
 * Only compiled when a socket API is available.
 * ═══════════════════════════════════════════════════════════════════════════ */

#if defined(OPENME_PLATFORM_WINDOWS)
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  pragma comment(lib, "ws2_32.lib")
#  define OPENME_HAVE_SOCKET 1
#elif defined(OPENME_PLATFORM_POSIX) || defined(OPENME_PLATFORM_ESP32) || defined(OPENME_USE_LWIP)
#  include <sys/socket.h>
#  include <netdb.h>
#  include <unistd.h>
#  define OPENME_HAVE_SOCKET 1
#  if defined(OPENME_PLATFORM_WINDOWS)
#    define closesocket close
#  endif
#endif

#ifdef OPENME_HAVE_SOCKET

int openme_send_knock(
    const char   *server_host,
    uint16_t      server_port,
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16])
{
    if (!server_host || !server_pubkey || !client_seed)
        return OPENME_ERR_NULL;

    /* Build packet */
    uint8_t pkt[OPENME_PACKET_SIZE];
    int rc = openme_knock_packet(pkt, server_pubkey, client_seed, target_ip);
    if (rc != OPENME_OK) return rc;

#if defined(OPENME_PLATFORM_WINDOWS)
    /* Init Winsock (idempotent; can be called multiple times) */
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif

    /* Resolve host */
    char port_str[8];
    /* snprintf is available on all targets we care about */
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)server_port);

    struct addrinfo hints, *res, *rp;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;
    hints.ai_flags    = AI_ADDRCONFIG;

    if (getaddrinfo(server_host, port_str, &hints, &res) != 0)
        return OPENME_ERR_SEND;

    int sock = -1;
    int sent = OPENME_ERR_SEND;

    for (rp = res; rp != NULL; rp = rp->ai_next) {
#if defined(OPENME_PLATFORM_WINDOWS)
        SOCKET s = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (s == INVALID_SOCKET) continue;
#else
        int s = (int)socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (s < 0) continue;
#endif
        if (sendto(s, (const char *)pkt, OPENME_PACKET_SIZE, 0,
                   rp->ai_addr, (int)rp->ai_addrlen) == OPENME_PACKET_SIZE) {
            sent = OPENME_OK;
#if defined(OPENME_PLATFORM_WINDOWS)
            closesocket(s);
#else
            close(s);
#endif
            break;
        }
#if defined(OPENME_PLATFORM_WINDOWS)
        closesocket(s);
#else
        close(s);
#endif
    }

    freeaddrinfo(res);
    return sent;
}

#else /* !OPENME_HAVE_SOCKET */

int openme_send_knock(
    const char   *server_host,
    uint16_t      server_port,
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16])
{
    (void)server_host; (void)server_port;
    (void)server_pubkey; (void)client_seed; (void)target_ip;
    /* No socket API on this platform.
     * Use openme_knock_packet() to obtain the 165-byte buffer and send it
     * with your platform's UDP API (e.g. WiFiUDP on Arduino). */
    return OPENME_ERR_SEND;
}

#endif /* OPENME_HAVE_SOCKET */

/* ═══════════════════════════════════════════════════════════════════════════
 * openme_b64_decode — minimal Base64 decoder (no newline or padding required)
 * ═══════════════════════════════════════════════════════════════════════════ */

static const int8_t B64_TABLE[256] = {
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0x00-0x0F */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0x10-0x1F */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,  /* 0x20-0x2F  +  / */
    52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,  /* 0x30-0x3F  0-9  */
    -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14, /* 0x40-0x4F  A-O  */
    15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,  /* 0x50-0x5F  P-Z  */
    -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40, /* 0x60-0x6F  a-o  */
    41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,  /* 0x70-0x7F  p-z  */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0x80-0x8F */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0x90-0x9F */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0xA0-0xAF */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0xB0-0xBF */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0xC0-0xCF */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0xD0-0xDF */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,  /* 0xE0-0xEF */
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1   /* 0xF0-0xFF */
};

int openme_b64_decode(uint8_t *out, size_t out_len, const char *b64) {
    if (!out || !b64) return -1;
    size_t written = 0;
    uint32_t accum = 0;
    int      bits  = 0;

    for (; *b64; b64++) {
        unsigned char c = (unsigned char)*b64;
        /* skip whitespace and padding */
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '=')
            continue;
        int v = B64_TABLE[c];
        if (v < 0) return -1; /* invalid character */
        accum = (accum << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (written >= out_len) return -1;
            out[written++] = (uint8_t)((accum >> bits) & 0xff);
        }
    }
    return (int)written;
}
