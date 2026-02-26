// Package client implements the openme SPA knock client.
//
// To send a knock:
//  1. Generate an ephemeral Curve25519 keypair.
//  2. Derive a shared secret via ECDH with the server's static public key.
//  3. Encrypt the plaintext payload (timestamp + nonce + target IP).
//  4. Sign the full packet with the client's Ed25519 private key.
//  5. Send the packet as a single UDP datagram.
//
// Ports to open are not specified in the packet. They are determined entirely
// by the server's per-client configuration, which prevents clients from
// requesting ports they are not authorised for.
package client

import (
	"crypto/ed25519"
	"fmt"
	"net"
	"time"

	internlcrypto "github.com/openme/openme/internal/crypto"
	"github.com/openme/openme/pkg/protocol"
)

// KnockOptions holds the parameters for a single SPA knock.
type KnockOptions struct {
	// ServerHost is the hostname or IP address of the openme server.
	ServerHost string

	// ServerUDPPort is the UDP port to send the knock to.
	ServerUDPPort uint16

	// ServerCurve25519PubKey is the server's static Curve25519 public key (32 bytes).
	ServerCurve25519PubKey [internlcrypto.Curve25519KeySize]byte

	// ClientEd25519PrivKey is the client's Ed25519 private key for signing.
	ClientEd25519PrivKey ed25519.PrivateKey

	// TargetIP is the IP address the server should open the firewall to.
	// Use "0.0.0.0" or "::" to indicate "use my source IP".
	// Ports are determined by the server's per-client config, not by the client.
	TargetIP net.IP
}

// Knock builds and sends a single SPA knock packet to the server.
// It returns an error if packet construction or sending fails.
func Knock(opts *KnockOptions) error {
	pkt, err := BuildPacket(opts)
	if err != nil {
		return fmt.Errorf("building knock packet: %w", err)
	}

	addr := fmt.Sprintf("%s:%d", opts.ServerHost, opts.ServerUDPPort)
	conn, err := net.Dial("udp", addr)
	if err != nil {
		return fmt.Errorf("dialing UDP %s: %w", addr, err)
	}
	defer conn.Close()

	if _, err := conn.Write(pkt); err != nil {
		return fmt.Errorf("sending knock packet: %w", err)
	}
	return nil
}

// BuildPacket constructs the raw SPA packet bytes without sending them.
// Useful for testing and debugging.
//
// Packet layout:
//
//	[version(1)] [ephemeral_pubkey(32)] [nonce(12)] [ciphertext+tag(56)] [ed25519_sig(64)]
//
// Total: 165 bytes.
func BuildPacket(opts *KnockOptions) ([]byte, error) {
	// Step 1: generate ephemeral Curve25519 keypair (discarded after use).
	ephemeral, err := internlcrypto.GenerateCurve25519KeyPair()
	if err != nil {
		return nil, fmt.Errorf("generating ephemeral keypair: %w", err)
	}

	// Step 2: ECDH → shared secret → symmetric key via HKDF.
	sharedKey, err := internlcrypto.ECDHSharedSecret(ephemeral.PrivateKey, opts.ServerCurve25519PubKey)
	if err != nil {
		return nil, fmt.Errorf("ECDH: %w", err)
	}

	// Step 3: build plaintext and encrypt.
	randNonce, err := internlcrypto.RandomNonce(protocol.RandomNonceSize)
	if err != nil {
		return nil, err
	}
	aeadNonce, err := internlcrypto.RandomNonce(protocol.NonceSize)
	if err != nil {
		return nil, err
	}

	pt := &protocol.Plaintext{
		Timestamp: time.Now().UTC(),
		TargetIP:  normaliseTargetIP(opts.TargetIP),
	}
	copy(pt.RandomNonce[:], randNonce)

	ciphertext, err := internlcrypto.Encrypt(sharedKey, aeadNonce, protocol.MarshalPlaintext(pt))
	if err != nil {
		return nil, fmt.Errorf("encrypting payload: %w", err)
	}

	// Step 4: assemble packet (minus signature).
	pkt := make([]byte, protocol.PacketSize)
	pkt[protocol.OffVersion] = protocol.Version
	copy(pkt[protocol.OffEphemeralPubKey:], ephemeral.PublicKey[:])
	copy(pkt[protocol.OffNonce:], aeadNonce)
	copy(pkt[protocol.OffCiphertext:], ciphertext)

	// Step 5: sign bytes 0..SignedPortionSize and append.
	sig := internlcrypto.Sign(opts.ClientEd25519PrivKey, pkt[:protocol.SignedPortionSize])
	copy(pkt[protocol.OffSignature:], sig)

	return pkt, nil
}

// HealthCheck attempts a TCP connection to the server's health port and returns
// true if the connection succeeds.
//
// Important: the health port is only open after a successful knock. A false
// return may mean the server is unreachable, but it more commonly means the
// client has not knocked yet (or the knock_timeout has expired).
// Use openme status --knock to knock and check in one step.
func HealthCheck(host string, port uint16, timeout time.Duration) bool {
	addr := fmt.Sprintf("%s:%d", host, port)
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

// normaliseTargetIP converts a nil or wildcard IP to the canonical zero form.
// All-zero 16 bytes signals the server to use the knock packet's source IP.
func normaliseTargetIP(ip net.IP) net.IP {
	if ip == nil || ip.IsUnspecified() {
		return net.IPv6zero
	}
	return ip
}
