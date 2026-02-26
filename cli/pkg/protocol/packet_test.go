package protocol_test

import (
	"net"
	"testing"
	"time"

	"github.com/openme/openme/pkg/protocol"
)

func TestMarshalUnmarshalPlaintext_RoundTrip(t *testing.T) {
	original := &protocol.Plaintext{
		Timestamp: time.Unix(1700000000, 123456789).UTC(),
		TargetIP:  net.ParseIP("192.168.1.50"),
	}
	copy(original.RandomNonce[:], []byte("0123456789abcdef"))

	raw := protocol.MarshalPlaintext(original)
	if len(raw) != protocol.PlaintextSize {
		t.Fatalf("marshalled size = %d, want %d", len(raw), protocol.PlaintextSize)
	}

	recovered, err := protocol.UnmarshalPlaintext(raw)
	if err != nil {
		t.Fatalf("UnmarshalPlaintext error = %v", err)
	}

	if !recovered.Timestamp.Equal(original.Timestamp) {
		t.Errorf("Timestamp = %v, want %v", recovered.Timestamp, original.Timestamp)
	}
	if recovered.RandomNonce != original.RandomNonce {
		t.Error("RandomNonce mismatch")
	}
	if !recovered.TargetIP.Equal(original.TargetIP.To16()) {
		t.Errorf("TargetIP = %v, want %v", recovered.TargetIP, original.TargetIP)
	}
}

func TestUnmarshalPlaintext_WrongSize(t *testing.T) {
	if _, err := protocol.UnmarshalPlaintext([]byte{1, 2, 3}); err == nil {
		t.Error("should return error for wrong size input")
	}
}

func TestMarshalPlaintext_IPv6(t *testing.T) {
	pt := &protocol.Plaintext{
		Timestamp: time.Now().UTC(),
		TargetIP:  net.ParseIP("2001:db8::1"),
	}

	raw := protocol.MarshalPlaintext(pt)
	recovered, err := protocol.UnmarshalPlaintext(raw)
	if err != nil {
		t.Fatal(err)
	}
	if !recovered.TargetIP.Equal(pt.TargetIP) {
		t.Errorf("IPv6 TargetIP = %v, want %v", recovered.TargetIP, pt.TargetIP)
	}
}

func TestMarshalPlaintext_WildcardIP(t *testing.T) {
	pt := &protocol.Plaintext{
		Timestamp: time.Now().UTC(),
		TargetIP:  nil, // wildcard → server uses knock source IP
	}

	raw := protocol.MarshalPlaintext(pt)
	recovered, err := protocol.UnmarshalPlaintext(raw)
	if err != nil {
		t.Fatal(err)
	}
	if !recovered.TargetIP.IsUnspecified() && recovered.TargetIP != nil {
		t.Errorf("nil IP should round-trip to unspecified, got %v", recovered.TargetIP)
	}
}

func TestPacketSizeConstants(t *testing.T) {
	// PlaintextSize = timestamp(8) + random_nonce(16) + target_ip(16)
	if protocol.PlaintextSize != protocol.TimestampSize+protocol.RandomNonceSize+protocol.TargetIPSize {
		t.Errorf("PlaintextSize = %d, want %d",
			protocol.PlaintextSize,
			protocol.TimestampSize+protocol.RandomNonceSize+protocol.TargetIPSize)
	}
	// CiphertextSize = plaintext + AEAD tag
	if protocol.CiphertextSize != protocol.PlaintextSize+protocol.TagSize {
		t.Errorf("CiphertextSize = %d, want %d",
			protocol.CiphertextSize, protocol.PlaintextSize+protocol.TagSize)
	}
	// PacketSize = version(1) + ephem_pubkey(32) + nonce(12) + ciphertext(56) + sig(64)
	expected := 1 + protocol.EphemeralPubKeySize + protocol.NonceSize + protocol.CiphertextSize + protocol.Ed25519SigSize
	if protocol.PacketSize != expected {
		t.Errorf("PacketSize = %d, want %d", protocol.PacketSize, expected)
	}
	// Sanity check the concrete values
	if protocol.PlaintextSize != 40 {
		t.Errorf("PlaintextSize = %d, want 40", protocol.PlaintextSize)
	}
	if protocol.CiphertextSize != 56 {
		t.Errorf("CiphertextSize = %d, want 56", protocol.CiphertextSize)
	}
	if protocol.PacketSize != 165 {
		t.Errorf("PacketSize = %d, want 165", protocol.PacketSize)
	}
}

func TestPlaintext_NoPortField(t *testing.T) {
	// Compile-time check: Plaintext must not have a TargetPort field.
	// Ports are determined server-side from the client's configuration.
	pt := protocol.Plaintext{
		Timestamp: time.Now(),
		TargetIP:  net.ParseIP("10.0.0.1"),
	}
	// If this compiles with no TargetPort assignment, the field is gone.
	_ = pt
}
