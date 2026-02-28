/**
 * @file openme_sha256.h
 * @brief Minimal SHA-256 and HMAC-SHA-256 for internal HKDF use.
 *
 * Public domain.  Based on the FIPS 180-4 specification.
 * No dynamic memory allocation.  C99 compliant.
 */

#ifndef OPENME_SHA256_H
#define OPENME_SHA256_H

#include <stdint.h>
#include <stddef.h>

#define OPENME_SHA256_DIGEST_SIZE 32
#define OPENME_SHA256_BLOCK_SIZE  64

typedef struct {
    uint32_t state[8];
    uint64_t count;
    uint8_t  buf[OPENME_SHA256_BLOCK_SIZE];
} openme_sha256_ctx;

void openme_sha256_init   (openme_sha256_ctx *ctx);
void openme_sha256_update  (openme_sha256_ctx *ctx, const uint8_t *data, size_t len);
void openme_sha256_final   (openme_sha256_ctx *ctx, uint8_t digest[OPENME_SHA256_DIGEST_SIZE]);
void openme_sha256         (const uint8_t *data, size_t len, uint8_t digest[OPENME_SHA256_DIGEST_SIZE]);

void openme_hmac_sha256(
    const uint8_t *key,  size_t key_len,
    const uint8_t *data, size_t data_len,
    uint8_t        mac[OPENME_SHA256_DIGEST_SIZE]
);

/**
 * HKDF-SHA-256 (RFC 5869), extract-and-expand.
 *
 * @param okm      Output key material buffer.
 * @param okm_len  Requested output length in bytes (max 32 * 255 = 8160).
 * @param ikm      Input key material (e.g. X25519 shared secret).
 * @param ikm_len  Length of ikm in bytes.
 * @param salt     Optional salt; may be NULL (treated as 32 zero bytes).
 * @param salt_len Length of salt in bytes.
 * @param info     Context / application specific information.
 * @param info_len Length of info in bytes.
 */
void openme_hkdf_sha256(
    uint8_t       *okm,      size_t okm_len,
    const uint8_t *ikm,      size_t ikm_len,
    const uint8_t *salt,     size_t salt_len,
    const uint8_t *info,     size_t info_len
);

#endif /* OPENME_SHA256_H */
