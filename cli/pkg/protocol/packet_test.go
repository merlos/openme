package protocol_test

import (
	"net"
	"testing"
	"time"

	"github.com/openme/openme/pkg/protocol"
)

func TestMarshalUnmarshalPlaintext_RoundTrip(t *testing.T) {
	original := &protocol.Plaintext{
		Timestamp:  time.Unix(1700000000, 123456789).UTC(),
		TargetIP:   net.ParseIP("192.168.1.50"),
		TargetPort: 22,
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
	if recovered.TargetPort != original.TargetPort {
		t.Errorf("TargetPort = %d, want %d", recovered.TargetPort, original.TargetPort)
	}
	if recovered.RandomNonce != original.RandomNonce {
		t.Errorf("RandomNonce mismatch")
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
		Timestamp:  time.Now().UTC(),
		TargetIP:   net.ParseIP("2001:db8::1"),
		TargetPort: 443,
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
		Timestamp:  time.Now().UTC(),
		TargetIP:   nil, // wildcard
		TargetPort: 22,
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
	// Verify our size arithmetic is self-consistent.
	if protocol.PlaintextSize != protocol.TimestampSize+protocol.RandomNonceSize+protocol.TargetIPSize+protocol.TargetPortSize {
		t.Error("PlaintextSize constant mismatch")
	}
	if protocol.CiphertextSize != protocol.PlaintextSize+protocol.TagSize {
		t.Error("CiphertextSize constant mismatch")
	}
	expected := 1 + protocol.EphemeralPubKeySize + protocol.NonceSize + protocol.CiphertextSize + protocol.Ed25519SigSize
	if protocol.PacketSize != expected {
		t.Errorf("PacketSize = %d, want %d", protocol.PacketSize, expected)
	}
}
