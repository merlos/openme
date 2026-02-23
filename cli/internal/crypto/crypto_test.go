package crypto_test

import (
	"bytes"
	"crypto/ed25519"
	"testing"

	"github.com/openme/openme/internal/crypto"
)

func TestGenerateCurve25519KeyPair(t *testing.T) {
	kp, err := crypto.GenerateCurve25519KeyPair()
	if err != nil {
		t.Fatalf("GenerateCurve25519KeyPair() error = %v", err)
	}
	if kp.PrivateKey == [32]byte{} {
		t.Error("private key is all zeros")
	}
	if kp.PublicKey == [32]byte{} {
		t.Error("public key is all zeros")
	}
	// Two calls should produce different keys.
	kp2, _ := crypto.GenerateCurve25519KeyPair()
	if kp.PrivateKey == kp2.PrivateKey {
		t.Error("two keypairs have identical private keys")
	}
}

func TestGenerateEd25519KeyPair(t *testing.T) {
	kp, err := crypto.GenerateEd25519KeyPair()
	if err != nil {
		t.Fatalf("GenerateEd25519KeyPair() error = %v", err)
	}
	if len(kp.PrivateKey) != ed25519.PrivateKeySize {
		t.Errorf("private key size = %d, want %d", len(kp.PrivateKey), ed25519.PrivateKeySize)
	}
	if len(kp.PublicKey) != ed25519.PublicKeySize {
		t.Errorf("public key size = %d, want %d", len(kp.PublicKey), ed25519.PublicKeySize)
	}
}

func TestECDHSharedSecret_Symmetric(t *testing.T) {
	// Both sides should derive the same shared secret.
	server, err := crypto.GenerateCurve25519KeyPair()
	if err != nil {
		t.Fatal(err)
	}
	client, err := crypto.GenerateCurve25519KeyPair()
	if err != nil {
		t.Fatal(err)
	}

	serverSecret, err := crypto.ECDHSharedSecret(server.PrivateKey, client.PublicKey)
	if err != nil {
		t.Fatalf("server ECDHSharedSecret error = %v", err)
	}
	clientSecret, err := crypto.ECDHSharedSecret(client.PrivateKey, server.PublicKey)
	if err != nil {
		t.Fatalf("client ECDHSharedSecret error = %v", err)
	}

	if !bytes.Equal(serverSecret, clientSecret) {
		t.Error("ECDH shared secrets do not match")
	}
}

func TestEncryptDecrypt(t *testing.T) {
	kp, _ := crypto.GenerateCurve25519KeyPair()
	key, _ := crypto.ECDHSharedSecret(kp.PrivateKey, kp.PublicKey)

	nonce, err := crypto.RandomNonce(12)
	if err != nil {
		t.Fatal(err)
	}

	plaintext := []byte("hello openme")
	ct, err := crypto.Encrypt(key, nonce, plaintext)
	if err != nil {
		t.Fatalf("Encrypt error = %v", err)
	}

	got, err := crypto.Decrypt(key, nonce, ct)
	if err != nil {
		t.Fatalf("Decrypt error = %v", err)
	}
	if !bytes.Equal(got, plaintext) {
		t.Errorf("Decrypt = %q, want %q", got, plaintext)
	}
}

func TestDecrypt_TamperedCiphertext(t *testing.T) {
	kp, _ := crypto.GenerateCurve25519KeyPair()
	key, _ := crypto.ECDHSharedSecret(kp.PrivateKey, kp.PublicKey)
	nonce, _ := crypto.RandomNonce(12)

	ct, _ := crypto.Encrypt(key, nonce, []byte("secret"))
	ct[0] ^= 0xFF // flip bits

	if _, err := crypto.Decrypt(key, nonce, ct); err == nil {
		t.Error("Decrypt should fail on tampered ciphertext")
	}
}

func TestSignVerify(t *testing.T) {
	kp, _ := crypto.GenerateEd25519KeyPair()
	msg := []byte("knock knock")

	sig := crypto.Sign(kp.PrivateKey, msg)
	if !crypto.Verify(kp.PublicKey, msg, sig) {
		t.Error("Verify returned false for valid signature")
	}

	// Wrong message should fail.
	if crypto.Verify(kp.PublicKey, []byte("wrong"), sig) {
		t.Error("Verify returned true for wrong message")
	}

	// Wrong key should fail.
	kp2, _ := crypto.GenerateEd25519KeyPair()
	if crypto.Verify(kp2.PublicKey, msg, sig) {
		t.Error("Verify returned true for wrong public key")
	}
}

func TestEncodeDecodeKey(t *testing.T) {
	original := []byte("0123456789abcdef0123456789abcdef")
	encoded := crypto.EncodeKey(original)
	decoded, err := crypto.DecodeKey(encoded)
	if err != nil {
		t.Fatalf("DecodeKey error = %v", err)
	}
	if !bytes.Equal(decoded, original) {
		t.Errorf("decoded key = %v, want %v", decoded, original)
	}
}

func TestFingerprintKey_Deterministic(t *testing.T) {
	pub := []byte("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1")
	fp1 := crypto.FingerprintKey(pub)
	fp2 := crypto.FingerprintKey(pub)
	if fp1 != fp2 {
		t.Error("FingerprintKey is not deterministic")
	}
	if len(fp1) != 16 { // 8 bytes = 16 hex chars
		t.Errorf("fingerprint length = %d, want 16", len(fp1))
	}
}
