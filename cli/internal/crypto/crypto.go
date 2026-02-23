// Package crypto provides all cryptographic primitives used by openme.
//
// Key types:
//   - Curve25519 (ECDH): used for ephemeral key exchange to derive shared secrets.
//   - Ed25519 (signing): used to authenticate knock packets.
//
// Encryption: ChaCha20-Poly1305 AEAD with the ECDH-derived shared secret.
// Key derivation: HKDF-SHA256 applied to the raw ECDH output to produce a 32-byte key.
package crypto

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"
)

const (
	// Curve25519KeySize is the size in bytes of a Curve25519 key (public or private).
	Curve25519KeySize = 32

	// Ed25519PrivateKeySize is the size in bytes of an Ed25519 private key (seed + public).
	Ed25519PrivateKeySize = ed25519.PrivateKeySize

	// Ed25519PublicKeySize is the size in bytes of an Ed25519 public key.
	Ed25519PublicKeySize = ed25519.PublicKeySize

	// hkdfInfo is the HKDF info string used during key derivation.
	hkdfInfo = "openme-v1-chacha20poly1305"
)

// Curve25519KeyPair holds a static or ephemeral Curve25519 keypair.
type Curve25519KeyPair struct {
	PrivateKey [Curve25519KeySize]byte
	PublicKey  [Curve25519KeySize]byte
}

// Ed25519KeyPair holds an Ed25519 signing keypair.
type Ed25519KeyPair struct {
	PrivateKey ed25519.PrivateKey
	PublicKey  ed25519.PublicKey
}

// GenerateCurve25519KeyPair generates a new random Curve25519 keypair.
// The private key is clamped per the Curve25519 specification.
func GenerateCurve25519KeyPair() (*Curve25519KeyPair, error) {
	var priv [Curve25519KeySize]byte
	if _, err := io.ReadFull(rand.Reader, priv[:]); err != nil {
		return nil, fmt.Errorf("generating curve25519 private key: %w", err)
	}

	// Clamp per RFC 7748 §5
	priv[0] &= 248
	priv[31] &= 127
	priv[31] |= 64

	pub, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		return nil, fmt.Errorf("deriving curve25519 public key: %w", err)
	}

	kp := &Curve25519KeyPair{}
	copy(kp.PrivateKey[:], priv[:])
	copy(kp.PublicKey[:], pub)
	return kp, nil
}

// GenerateEd25519KeyPair generates a new random Ed25519 signing keypair.
func GenerateEd25519KeyPair() (*Ed25519KeyPair, error) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generating ed25519 keypair: %w", err)
	}
	return &Ed25519KeyPair{PrivateKey: priv, PublicKey: pub}, nil
}

// ECDHSharedSecret computes a Curve25519 ECDH shared secret from a local private key
// and a remote public key, then derives a 32-byte symmetric key via HKDF-SHA256.
func ECDHSharedSecret(localPriv [Curve25519KeySize]byte, remotePub [Curve25519KeySize]byte) ([]byte, error) {
	raw, err := curve25519.X25519(localPriv[:], remotePub[:])
	if err != nil {
		return nil, fmt.Errorf("curve25519 ECDH: %w", err)
	}

	// Derive a proper symmetric key from the raw DH output using HKDF.
	hk := hkdf.New(sha256.New, raw, nil, []byte(hkdfInfo))
	key := make([]byte, chacha20poly1305.KeySize)
	if _, err := io.ReadFull(hk, key); err != nil {
		return nil, fmt.Errorf("HKDF key derivation: %w", err)
	}
	return key, nil
}

// Encrypt encrypts plaintext using ChaCha20-Poly1305 with the given 32-byte key and nonce.
// Returns ciphertext+tag. The nonce must be exactly chacha20poly1305.NonceSize (12) bytes.
func Encrypt(key, nonce, plaintext []byte) ([]byte, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, fmt.Errorf("creating AEAD cipher: %w", err)
	}
	return aead.Seal(nil, nonce, plaintext, nil), nil
}

// Decrypt decrypts ciphertext using ChaCha20-Poly1305 with the given key and nonce.
// Returns an error if authentication fails (tampered data or wrong key).
func Decrypt(key, nonce, ciphertext []byte) ([]byte, error) {
	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, fmt.Errorf("creating AEAD cipher: %w", err)
	}
	plain, err := aead.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("AEAD open: %w", err)
	}
	return plain, nil
}

// Sign signs message with the Ed25519 private key and returns the 64-byte signature.
func Sign(priv ed25519.PrivateKey, message []byte) []byte {
	return ed25519.Sign(priv, message)
}

// Verify verifies an Ed25519 signature over message with the given public key.
func Verify(pub ed25519.PublicKey, message, sig []byte) bool {
	return ed25519.Verify(pub, message, sig)
}

// RandomNonce returns n cryptographically random bytes.
func RandomNonce(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return nil, fmt.Errorf("generating random nonce: %w", err)
	}
	return b, nil
}

// EncodeKey base64-encodes a key for storage in config files.
func EncodeKey(key []byte) string {
	return base64.StdEncoding.EncodeToString(key)
}

// DecodeKey base64-decodes a key from a config file.
func DecodeKey(s string) ([]byte, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, fmt.Errorf("base64 decode key: %w", err)
	}
	return b, nil
}

// FingerprintKey returns a short human-readable fingerprint (first 8 bytes hex) of a key.
func FingerprintKey(pub []byte) string {
	h := sha256.Sum256(pub)
	return fmt.Sprintf("%x", h[:8])
}
