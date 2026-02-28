/**
 * @file openmelib.h
 * @brief openme SPA (Single Packet Authentication) client library — C API.
 *
 * openmelib implements the client side of the openme knock protocol in pure C
 * with no dynamic memory allocation.  It is designed to compile on any
 * C99-compliant toolchain including:
 *
 *   - Desktop  : Linux / macOS / Windows (GCC, Clang, MSVC)
 *   - ESP32    : Arduino framework and ESP-IDF
 *   - Arduino  : AVR / ARM (Uno, Mega, Due, MKR, RP2040, …)
 *   - Bare metal: any ARM/RISC-V MCU with a C99 compiler
 *
 * ## Crypto dependencies
 * The packet construction functions depend on **Monocypher 4** for:
 *   - X25519 ECDH  (`crypto_x25519`, `crypto_x25519_public_key`)
 *   - ChaCha20-Poly1305 (`crypto_aead_lock`)
 *   - Ed25519 (`crypto_eddsa_key_pair`, `crypto_eddsa_sign`)
 *
 * A small SHA-256 / HMAC-SHA-256 implementation is bundled internally for
 * HKDF-SHA-256 key derivation (RFC 5869).
 *
 * ## Wire format (165 bytes)
 * @code
 *  0       1      33      45                   101                   165
 *  ┌───────┬──────┬───────┬─────────────────────┬─────────────────────┐
 *  │version│ephem │ nonce │     ciphertext      │    ed25519_sig      │
 *  │ 1 B   │32 B  │12 B   │      56 B           │      64 B           │
 *  └───────┴──────┴───────┴─────────────────────┴─────────────────────┘
 *  ◄─────────────── signed portion (101 B) ──────────────────────────►
 * @endcode
 *
 * Decrypted plaintext (40 bytes):
 * @code
 *  [ timestamp: int64 be nanoseconds (8) ][ random nonce (16) ][ target IP (16) ]
 * @endcode
 */

#ifndef OPENMELIB_H
#define OPENMELIB_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>

/* ─── Constants ─────────────────────────────────────────────────────────────── */

/** Protocol version byte embedded in every knock packet. */
#define OPENME_VERSION         ((uint8_t)1)

/** Total wire size, in bytes, of a SPA knock packet. */
#define OPENME_PACKET_SIZE     165

/** Number of bytes covered by the Ed25519 signature (all fields except sig). */
#define OPENME_SIGNED_SIZE     101   /* OPENME_PACKET_SIZE - 64 */

/** Size of the plaintext payload before AEAD encryption. */
#define OPENME_PLAINTEXT_SIZE  40

/** AEAD ciphertext size (plaintext + 16-byte Poly1305 tag). */
#define OPENME_CIPHERTEXT_SIZE 56   /* OPENME_PLAINTEXT_SIZE + 16 */

/* ─── Error codes ───────────────────────────────────────────────────────────── */

/** Success. */
#define OPENME_OK              0

/** One or more pointer arguments were NULL. */
#define OPENME_ERR_NULL        (-1)

/** Key or nonce buffer has wrong length (logic error in caller). */
#define OPENME_ERR_PARAM       (-2)

/** Platform-level send / networking error.
 *  Only returned by openme_send_knock(); not returned by openme_build_packet(). */
#define OPENME_ERR_SEND        (-3)

/* ─── Low-level API (portable — no OS calls) ────────────────────────────────── */

/**
 * Build a 165-byte SPA knock packet.
 *
 * All random/time values must be supplied by the caller, making this function
 * completely portable to bare-metal platforms.  On Arduino/ESP32 use
 * `openme_knock_packet()` which fills these values from platform APIs.
 *
 * Construction steps (mirrors canonical protocol):
 *  1. Derive ephemeral X25519 public key from @p ephem_secret.
 *  2. X25519 ECDH(ephem_secret, server_pubkey) → shared secret.
 *  3. HKDF-SHA256(ikm=shared_secret, info="openme-v1-chacha20poly1305") → 32-byte key.
 *  4. Build 40-byte plaintext: timestamp_ns (big-endian) ‖ random_nonce ‖ target_ip.
 *  5. ChaCha20-Poly1305 encrypt plaintext → 56-byte ciphertext+tag.
 *  6. Assemble 101-byte signed portion: version ‖ ephem_pub ‖ aead_nonce ‖ ciphertext.
 *  7. Ed25519-sign signed portion with client key → 64-byte signature.
 *  8. Append signature → 165-byte packet in @p out.
 *
 * @param out               Output buffer, exactly OPENME_PACKET_SIZE (165) bytes.
 * @param server_pubkey     32-byte Curve25519 (X25519) public key of the server.
 * @param client_seed       32-byte Ed25519 seed (private key material) of this client.
 *                          If the client stores a 64-byte key (seed + pubkey), pass
 *                          only the first 32 bytes.
 * @param timestamp_ns      Current time as Unix nanoseconds (int64, big-endian in packet).
 *                          The server rejects packets outside its replay window (default ±60 s).
 * @param ephem_secret      32 bytes of random data used as the ephemeral X25519 secret key.
 *                          Must be unique per knock — never reuse.
 * @param aead_nonce        12 bytes of random data used as the ChaCha20-Poly1305 nonce.
 *                          Must be unique per knock — never reuse.
 * @param random_nonce      16 bytes of random data embedded in the plaintext for
 *                          uniqueness / replay protection.
 * @param target_ip         16-byte IPv6 (or IPv4-mapped) address the server should
 *                          open the firewall for.  Pass NULL (or 16 zero bytes) to
 *                          tell the server to use the source IP of the knock packet.
 * @return OPENME_OK on success, negative error code on failure.
 */
int openme_build_packet(
    uint8_t       out[OPENME_PACKET_SIZE],
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    int64_t       timestamp_ns,
    const uint8_t ephem_secret[32],
    const uint8_t aead_nonce[12],
    const uint8_t random_nonce[16],
    const uint8_t target_ip[16]   /* NULL → all-zeros (use source IP) */
);

/* ─── Platform hooks (implement for your target) ────────────────────────────── */

/**
 * Fill @p buf with @p len cryptographically secure random bytes.
 *
 * A default implementation is provided for:
 *   - Linux / macOS  : getrandom() / /dev/urandom
 *   - Windows        : BCryptGenRandom
 *   - ESP32 (Arduino): esp_fill_random()
 *   - AVR/Other      : *no default* — you MUST provide this function.
 *
 * To override, define OPENME_CUSTOM_RNG before including this header and
 * provide your own implementation of openme_random_bytes().
 */
void openme_random_bytes(uint8_t *buf, size_t len);

/**
 * Return current time as Unix nanoseconds (int64).
 *
 * A default implementation is provided for:
 *   - Linux / macOS  : clock_gettime(CLOCK_REALTIME)
 *   - Windows        : GetSystemTimeAsFileTime
 *   - ESP32 (Arduino): millis() + compile-time base (see README)
 *   - AVR/Other      : *no default* — you MUST provide this function.
 *
 * To override, define OPENME_CUSTOM_TIME before including this header and
 * provide your own implementation of openme_now_ns().
 *
 * @warning On platforms without a real-time clock (e.g., bare Arduino Uno),
 *   the timestamp will be wrong; the server will reject the knock unless its
 *   replay_window is set very large or timestamp checking is disabled.
 */
int64_t openme_now_ns(void);

/**
 * Arduino only: set the epoch base used by the built-in openme_now_ns().
 *
 * Call this after obtaining a valid UTC time from NTPClient or an RTC.
 * The library will add millis() to this base for each subsequent call
 * to openme_now_ns().
 *
 * @param unix_ns  Current Unix time in nanoseconds.
 *
 * Example:
 * @code
 *   // After NTPClient.update():
 *   openme_set_base_time_ns((int64_t)timeClient.getEpochTime() * 1000000000LL
 *                           - (int64_t)millis() * 1000000LL);
 * @endcode
 */
#if defined(ARDUINO)
void openme_set_base_time_ns(int64_t unix_ns);
#endif

/* ─── Convenience API (uses openme_random_bytes / openme_now_ns) ─────────────── */

/**
 * Build a 165-byte SPA knock packet using platform-provided RNG and time.
 *
 * This is the main entry point for ESP32/Arduino and other platforms where
 * the OS or framework provides randomness and time.  It calls
 * openme_random_bytes() and openme_now_ns() internally.
 *
 * @param out           Output buffer, exactly OPENME_PACKET_SIZE (165) bytes.
 * @param server_pubkey 32-byte X25519 public key of the server.
 * @param client_seed   32-byte Ed25519 seed of this client.
 * @param target_ip     16-byte IPv6 target, or NULL to use source IP.
 * @return OPENME_OK on success, negative error code on failure.
 */
int openme_knock_packet(
    uint8_t       out[OPENME_PACKET_SIZE],
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16]  /* NULL → use source IP */
);

/* ─── Socket helper (POSIX / Windows / lwIP) ────────────────────────────────── */

/**
 * Build and send a SPA knock packet over UDP.
 *
 * This function is available on targets that have POSIX `<sys/socket.h>` or
 * Windows `<winsock2.h>` (enabled automatically) or lwIP (define
 * OPENME_USE_LWIP=1 as a compile flag).
 *
 * On bare Arduino (no socket API), use openme_knock_packet() to get the
 * 165-byte buffer and send it with WiFiUDP / EthernetUDP yourself — see the
 * Arduino example sketch.
 *
 * @param server_host   Null-terminated hostname or dotted-decimal/colon IPv6 string.
 * @param server_port   UDP port the server listens on (typically 54154).
 * @param server_pubkey 32-byte X25519 public key of the server.
 * @param client_seed   32-byte Ed25519 seed of this client.
 * @param target_ip     16-byte IPv6 target, or NULL to use source IP.
 * @return OPENME_OK on success, OPENME_ERR_SEND on network failure,
 *         other negative code for crypto errors.
 */
int openme_send_knock(
    const char   *server_host,
    uint16_t      server_port,
    const uint8_t server_pubkey[32],
    const uint8_t client_seed[32],
    const uint8_t target_ip[16]  /* NULL → use source IP */
);

/* ─── Utility ─────────────────────────────────────────────────────────────── */

/**
 * Decode a null-terminated Base64 string into @p out.
 *
 * Ignores whitespace.  Returns the number of decoded bytes, or -1 on error
 * (invalid character or @p out_len too small).
 *
 * @param out       Destination buffer.
 * @param out_len   Capacity of @p out in bytes.
 * @param b64       Null-terminated Base64-encoded string.
 * @return Number of bytes written, or -1 on error.
 */
int openme_b64_decode(uint8_t *out, size_t out_len, const char *b64);

#ifdef __cplusplus
}
#endif

#endif /* OPENMELIB_H */
