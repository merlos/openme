// Package protocol defines the openme Single Packet Authentication (SPA) wire format.
//
// Packet layout (165 bytes total):
//
//	[version(1)] [ephemeral_pubkey(32)] [nonce(12)] [ciphertext(56)] [ed25519_sig(64)]
//
// The ciphertext decrypts to:
//
//	[timestamp(8)] [random_nonce(16)] [target_ip(16)]
//
// Ports to open are determined entirely by the server's per-client configuration.
// The client does not specify ports in the knock packet — this simplifies the
// wire format and prevents clients from requesting ports they are not authorised for.
//
// Security properties:
//   - Forward secrecy via ephemeral Curve25519 ECDH key per knock
//   - Payload opacity via ChaCha20-Poly1305 AEAD encryption
//   - Authentication via Ed25519 signature over the full packet (minus sig field)
//   - Replay protection via timestamp window + random nonce cache
package protocol

import (
	"encoding/binary"
	"net"
	"time"
)

const (
	// Version is the current protocol version.
	Version = 1

	// EphemeralPubKeySize is the size of the ephemeral Curve25519 public key in bytes.
	EphemeralPubKeySize = 32

	// NonceSize is the ChaCha20-Poly1305 nonce size in bytes.
	NonceSize = 12

	// TagSize is the ChaCha20-Poly1305 authentication tag size in bytes.
	TagSize = 16

	// Ed25519SigSize is the Ed25519 signature size in bytes.
	Ed25519SigSize = 64

	// TimestampSize is the size of the Unix timestamp (int64) in bytes.
	TimestampSize = 8

	// RandomNonceSize is the size of the random replay-protection nonce in bytes.
	RandomNonceSize = 16

	// TargetIPSize is the size of the target IP field (IPv6-compatible, 16 bytes).
	TargetIPSize = 16

	// PlaintextSize is the total size of the unencrypted payload.
	// timestamp(8) + random_nonce(16) + target_ip(16) = 40 bytes.
	PlaintextSize = TimestampSize + RandomNonceSize + TargetIPSize // 40 bytes

	// CiphertextSize is PlaintextSize + TagSize.
	CiphertextSize = PlaintextSize + TagSize // 56 bytes

	// PacketSize is the total wire size of a SPA packet.
	PacketSize = 1 + EphemeralPubKeySize + NonceSize + CiphertextSize + Ed25519SigSize // 165 bytes

	// SignedPortionSize is the number of bytes covered by the Ed25519 signature.
	SignedPortionSize = PacketSize - Ed25519SigSize

	// ReplayWindowDuration is the maximum allowed age of a knock timestamp.
	ReplayWindowDuration = 60 * time.Second

	// WildcardIP represents "use the connecting client's source IP".
	WildcardIP = "0.0.0.0"
)

// Offsets into the raw packet byte slice.
const (
	OffVersion         = 0
	OffEphemeralPubKey = 1
	OffNonce           = OffEphemeralPubKey + EphemeralPubKeySize // 33
	OffCiphertext      = OffNonce + NonceSize                     // 45
	OffSignature       = OffCiphertext + CiphertextSize           // 101
)

// Plaintext holds the decrypted payload of a SPA packet.
type Plaintext struct {
	// Timestamp is the Unix nanosecond time the knock was created.
	Timestamp time.Time

	// RandomNonce is a random 16-byte value used for replay protection.
	RandomNonce [RandomNonceSize]byte

	// TargetIP is the IP address to open the firewall to.
	// Use net.IPv4zero or net.IPv6zero for "source IP of knock packet".
	// Ports are determined by the server's per-client configuration, not by
	// this field — the client has no say over which ports are opened.
	TargetIP net.IP
}

// MarshalPlaintext serialises a Plaintext into a fixed-size byte slice.
func MarshalPlaintext(p *Plaintext) []byte {
	buf := make([]byte, PlaintextSize)

	binary.BigEndian.PutUint64(buf[0:], uint64(p.Timestamp.UnixNano()))
	copy(buf[TimestampSize:], p.RandomNonce[:])

	ip := p.TargetIP.To16()
	if ip == nil {
		ip = make([]byte, 16) // zero = wildcard → use knock source IP
	}
	copy(buf[TimestampSize+RandomNonceSize:], ip)

	return buf
}

// UnmarshalPlaintext deserialises a fixed-size byte slice into a Plaintext.
// Returns an error if the slice is not exactly PlaintextSize bytes.
func UnmarshalPlaintext(raw []byte) (*Plaintext, error) {
	if len(raw) != PlaintextSize {
		return nil, ErrInvalidPacketSize
	}

	ts := int64(binary.BigEndian.Uint64(raw[0:]))

	var rn [RandomNonceSize]byte
	copy(rn[:], raw[TimestampSize:TimestampSize+RandomNonceSize])

	ip := make(net.IP, 16)
	copy(ip, raw[TimestampSize+RandomNonceSize:])

	return &Plaintext{
		Timestamp:   time.Unix(0, ts),
		RandomNonce: rn,
		TargetIP:    ip,
	}, nil
}
