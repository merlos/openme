/**
 * @file openme_sha256.c
 * @brief Minimal SHA-256, HMAC-SHA-256, and HKDF-SHA-256 (RFC 5869).
 *
 * Public domain.  Based on FIPS 180-4.
 * No dynamic allocation.  C99 compliant.  Endian-safe.
 */

#include "openme_sha256.h"
#include <string.h>

/* ─── SHA-256 round constants ──────────────────────────────────────────────── */
static const uint32_t K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

/* ─── Internal helpers ─────────────────────────────────────────────────────── */
#define ROTR32(x, n)  (((x) >> (n)) | ((x) << (32 - (n))))

#define CH(x,y,z)   (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z)  (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define SIG0(x)     (ROTR32(x,2)  ^ ROTR32(x,13) ^ ROTR32(x,22))
#define SIG1(x)     (ROTR32(x,6)  ^ ROTR32(x,11) ^ ROTR32(x,25))
#define sig0(x)     (ROTR32(x,7)  ^ ROTR32(x,18) ^ ((x) >> 3))
#define sig1(x)     (ROTR32(x,17) ^ ROTR32(x,19) ^ ((x) >> 10))

static uint32_t load_be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
         | ((uint32_t)p[2] <<  8) |  (uint32_t)p[3];
}

static void store_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >>  8);
    p[3] = (uint8_t)(v);
}

static void sha256_compress(uint32_t state[8], const uint8_t block[64]) {
    uint32_t W[64];
    int i;
    for (i = 0; i < 16; i++)
        W[i] = load_be32(block + 4 * i);
    for (i = 16; i < 64; i++)
        W[i] = sig1(W[i-2]) + W[i-7] + sig0(W[i-15]) + W[i-16];

    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (i = 0; i < 64; i++) {
        uint32_t T1 = h + SIG1(e) + CH(e,f,g) + K[i] + W[i];
        uint32_t T2 = SIG0(a) + MAJ(a,b,c);
        h = g; g = f; f = e; e = d + T1;
        d = c; c = b; b = a; a = T1 + T2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

/* ─── SHA-256 public functions ─────────────────────────────────────────────── */

void openme_sha256_init(openme_sha256_ctx *ctx) {
    ctx->state[0] = 0x6a09e667u;
    ctx->state[1] = 0xbb67ae85u;
    ctx->state[2] = 0x3c6ef372u;
    ctx->state[3] = 0xa54ff53au;
    ctx->state[4] = 0x510e527fu;
    ctx->state[5] = 0x9b05688cu;
    ctx->state[6] = 0x1f83d9abu;
    ctx->state[7] = 0x5be0cd19u;
    ctx->count = 0;
}

void openme_sha256_update(openme_sha256_ctx *ctx, const uint8_t *data, size_t len) {
    size_t off = (size_t)(ctx->count & 63);
    ctx->count += (uint64_t)len;
    while (len > 0) {
        size_t n = 64 - off;
        if (n > len) n = len;
        memcpy(ctx->buf + off, data, n);
        data += n; len -= n; off += n;
        if (off == 64) {
            sha256_compress(ctx->state, ctx->buf);
            off = 0;
        }
    }
}

void openme_sha256_final(openme_sha256_ctx *ctx, uint8_t digest[OPENME_SHA256_DIGEST_SIZE]) {
    uint64_t bits = ctx->count << 3;
    uint8_t  pad  = 0x80;
    size_t   off  = (size_t)(ctx->count & 63);
    openme_sha256_update(ctx, &pad, 1);
    pad = 0;
    while ((ctx->count & 63) != 56)
        openme_sha256_update(ctx, &pad, 1);
    /* append bit length big-endian 64-bit */
    uint8_t len_be[8];
    len_be[0] = (uint8_t)(bits >> 56);
    len_be[1] = (uint8_t)(bits >> 48);
    len_be[2] = (uint8_t)(bits >> 40);
    len_be[3] = (uint8_t)(bits >> 32);
    len_be[4] = (uint8_t)(bits >> 24);
    len_be[5] = (uint8_t)(bits >> 16);
    len_be[6] = (uint8_t)(bits >>  8);
    len_be[7] = (uint8_t)(bits);
    openme_sha256_update(ctx, len_be, 8);
    (void)off; /* suppress unused warning */
    for (int i = 0; i < 8; i++)
        store_be32(digest + 4 * i, ctx->state[i]);
    /* wipe */
    memset(ctx, 0, sizeof(*ctx));
}

void openme_sha256(const uint8_t *data, size_t len, uint8_t digest[OPENME_SHA256_DIGEST_SIZE]) {
    openme_sha256_ctx ctx;
    openme_sha256_init(&ctx);
    openme_sha256_update(&ctx, data, len);
    openme_sha256_final(&ctx, digest);
}

/* ─── HMAC-SHA-256 ─────────────────────────────────────────────────────────── */

void openme_hmac_sha256(
    const uint8_t *key,  size_t key_len,
    const uint8_t *data, size_t data_len,
    uint8_t        mac[OPENME_SHA256_DIGEST_SIZE])
{
    uint8_t k[OPENME_SHA256_BLOCK_SIZE];
    uint8_t ipad[OPENME_SHA256_BLOCK_SIZE];
    uint8_t opad[OPENME_SHA256_BLOCK_SIZE];
    uint8_t inner[OPENME_SHA256_DIGEST_SIZE];
    int i;

    /* if key > block size, hash it first */
    memset(k, 0, sizeof(k));
    if (key_len > OPENME_SHA256_BLOCK_SIZE) {
        openme_sha256(key, key_len, k);
    } else {
        memcpy(k, key, key_len);
    }

    for (i = 0; i < OPENME_SHA256_BLOCK_SIZE; i++) {
        ipad[i] = k[i] ^ 0x36u;
        opad[i] = k[i] ^ 0x5cu;
    }

    /* inner hash: SHA256(ipad || data) */
    openme_sha256_ctx ctx;
    openme_sha256_init(&ctx);
    openme_sha256_update(&ctx, ipad, OPENME_SHA256_BLOCK_SIZE);
    openme_sha256_update(&ctx, data, data_len);
    openme_sha256_final(&ctx, inner);

    /* outer hash: SHA256(opad || inner) */
    openme_sha256_init(&ctx);
    openme_sha256_update(&ctx, opad, OPENME_SHA256_BLOCK_SIZE);
    openme_sha256_update(&ctx, inner, OPENME_SHA256_DIGEST_SIZE);
    openme_sha256_final(&ctx, mac);

    /* wipe sensitive material */
    memset(k,     0, sizeof(k));
    memset(ipad,  0, sizeof(ipad));
    memset(opad,  0, sizeof(opad));
    memset(inner, 0, sizeof(inner));
}

/* ─── HKDF-SHA-256 (RFC 5869) ──────────────────────────────────────────────── */

void openme_hkdf_sha256(
    uint8_t       *okm,      size_t okm_len,
    const uint8_t *ikm,      size_t ikm_len,
    const uint8_t *salt,     size_t salt_len,
    const uint8_t *info,     size_t info_len)
{
    /* Extract */
    uint8_t zero_salt[OPENME_SHA256_DIGEST_SIZE];
    const uint8_t *eff_salt;
    size_t         eff_salt_len;
    if (salt == NULL || salt_len == 0) {
        memset(zero_salt, 0, OPENME_SHA256_DIGEST_SIZE);
        eff_salt     = zero_salt;
        eff_salt_len = OPENME_SHA256_DIGEST_SIZE;
    } else {
        eff_salt     = salt;
        eff_salt_len = salt_len;
    }
    uint8_t prk[OPENME_SHA256_DIGEST_SIZE];
    openme_hmac_sha256(eff_salt, eff_salt_len, ikm, ikm_len, prk);

    /* Expand */
    uint8_t T[OPENME_SHA256_DIGEST_SIZE];
    uint8_t prev[OPENME_SHA256_DIGEST_SIZE];
    size_t  prev_len = 0;
    size_t  written  = 0;
    uint8_t counter  = 1;

    while (written < okm_len) {
        /* T(n) = HMAC-SHA256(PRK, T(n-1) || info || counter) */
        openme_sha256_ctx ctx;
        uint8_t ipad2[OPENME_SHA256_BLOCK_SIZE];
        uint8_t opad2[OPENME_SHA256_BLOCK_SIZE];
        uint8_t prk_block[OPENME_SHA256_BLOCK_SIZE];
        int j;
        memset(prk_block, 0, sizeof(prk_block));
        memcpy(prk_block, prk, OPENME_SHA256_DIGEST_SIZE);
        for (j = 0; j < OPENME_SHA256_BLOCK_SIZE; j++) {
            ipad2[j] = prk_block[j] ^ 0x36u;
            opad2[j] = prk_block[j] ^ 0x5cu;
        }

        openme_sha256_init(&ctx);
        openme_sha256_update(&ctx, ipad2, OPENME_SHA256_BLOCK_SIZE);
        if (prev_len > 0)
            openme_sha256_update(&ctx, prev, prev_len);
        openme_sha256_update(&ctx, info, info_len);
        openme_sha256_update(&ctx, &counter, 1);
        uint8_t inner2[OPENME_SHA256_DIGEST_SIZE];
        openme_sha256_final(&ctx, inner2);

        openme_sha256_init(&ctx);
        openme_sha256_update(&ctx, opad2, OPENME_SHA256_BLOCK_SIZE);
        openme_sha256_update(&ctx, inner2, OPENME_SHA256_DIGEST_SIZE);
        openme_sha256_final(&ctx, T);

        memset(prk_block, 0, sizeof(prk_block));
        memset(ipad2,     0, sizeof(ipad2));
        memset(opad2,     0, sizeof(opad2));
        memset(inner2,    0, sizeof(inner2));

        size_t n = okm_len - written;
        if (n > OPENME_SHA256_DIGEST_SIZE) n = OPENME_SHA256_DIGEST_SIZE;
        memcpy(okm + written, T, n);
        written += n;

        memcpy(prev, T, OPENME_SHA256_DIGEST_SIZE);
        prev_len = OPENME_SHA256_DIGEST_SIZE;
        counter++;
    }

    memset(prk,  0, sizeof(prk));
    memset(T,    0, sizeof(T));
    memset(prev, 0, sizeof(prev));
}
