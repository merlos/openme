package protocol

import "errors"

var (
	// ErrInvalidPacketSize is returned when a packet is not exactly PacketSize bytes.
	ErrInvalidPacketSize = errors.New("invalid packet size")

	// ErrInvalidVersion is returned when the packet version byte does not match Version.
	ErrInvalidVersion = errors.New("invalid protocol version")

	// ErrInvalidSignature is returned when the Ed25519 signature verification fails.
	ErrInvalidSignature = errors.New("invalid signature")

	// ErrReplay is returned when the packet timestamp is outside the replay window
	// or the nonce has already been seen.
	ErrReplay = errors.New("replay detected: packet too old or nonce reused")

	// ErrUnknownClient is returned when no registered client matches the signing key.
	ErrUnknownClient = errors.New("unknown client public key")

	// ErrDecrypt is returned when AEAD decryption fails (wrong key or tampered data).
	ErrDecrypt = errors.New("decryption failed")
)
