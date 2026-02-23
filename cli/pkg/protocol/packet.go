// Package protocol defines the openme Single Packet Authentication (SPA) wire format.
//
// Packet layout (183 bytes total):
//
//	[version(1)] [ephemeral_pubkey(32)] [nonce(12)] [ciphertext(39)] [tag(16)] [ed25519_sig(64)] [reserved(19)]
//
// The ciphertext decrypts to:
//
//	[timestamp(8)] [random_nonce(16)] [target_ip(16)] [target_port(2)]
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

	// TargetPortSize is the size of the target port field in bytes.
	TargetPortSize = 2

	// PlaintextSize is the total size of the unencrypted payload.
	PlaintextSize = TimestampSize + RandomNonceSize + TargetIPSize + TargetPortSize // 42 bytes

	// CiphertextSize is PlaintextSize + TagSize.
	CiphertextSize = PlaintextSize + TagSize // 58 bytes

	// PacketSize is the total wire size of a SPA packet.
	PacketSize = 1 + EphemeralPubKeySize + NonceSize + CiphertextSize + Ed25519SigSize // 167 bytes

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
	OffSignature       = OffCiphertext + CiphertextSize           // 103
)

// Plaintext holds the decrypted payload of a SPA packet.
type Plaintext struct {
	// Timestamp is the Unix nanosecond time the knock was created.
	Timestamp time.Time

	// RandomNonce is a random 16-byte value used for replay protection.
	RandomNonce [RandomNonceSize]byte

	// TargetIP is the IP address to open the firewall to.
	// Use net.IPv4zero or net.IPv6zero for "source IP of knock packet".
	TargetIP net.IP

	// TargetPort is the port to open.
	TargetPort uint16
}

// MarshalPlaintext serialises a Plaintext into a fixed-size byte slice.
func MarshalPlaintext(p *Plaintext) []byte {
	buf := make([]byte, PlaintextSize)

	binary.BigEndian.PutUint64(buf[0:], uint64(p.Timestamp.UnixNano()))
	copy(buf[TimestampSize:], p.RandomNonce[:])

	ip := p.TargetIP.To16()
	if ip == nil {
		ip = make([]byte, 16) // zero = wildcard
	}
	copy(buf[TimestampSize+RandomNonceSize:], ip)
	binary.BigEndian.PutUint16(buf[TimestampSize+RandomNonceSize+TargetIPSize:], p.TargetPort)

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
	copy(ip, raw[TimestampSize+RandomNonceSize:TimestampSize+RandomNonceSize+TargetIPSize])

	port := binary.BigEndian.Uint16(raw[TimestampSize+RandomNonceSize+TargetIPSize:])

	return &Plaintext{
		Timestamp:   time.Unix(0, ts),
		RandomNonce: rn,
		TargetIP:    ip,
		TargetPort:  port,
	}, nil
}
