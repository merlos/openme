// Package server implements the openme SPA server.
//
// The server:
//  1. Listens on a UDP port for SPA knock packets.
//  2. Verifies each packet's Ed25519 signature against the client whitelist.
//  3. Decrypts the payload using ECDH with the ephemeral key in the packet.
//  4. Checks timestamp freshness and nonce uniqueness (replay protection).
//  5. Opens firewall rules (including the TCP health port) for the client's IP.
//
// The TCP health port is NOT permanently open. It is treated as a regular
// port rule and opened by the firewall manager only after a successful knock,
// for the duration of knock_timeout. This means openme status can only succeed
// after a valid knock — confirming the full authentication round trip worked.
package server

import (
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net"
	"sync"
	"time"

	internlcrypto "github.com/merlos/openme/internal/crypto"
	"github.com/merlos/openme/pkg/protocol"
)

// KnockHandler is called by the server for each valid knock with the client
// name, the resolved source IP, the decrypted target IP (or source IP if
// wildcard), and the port rules to open.
type KnockHandler func(clientName string, srcIP, targetIP net.IP, ports []PortRule)

// PortRule mirrors config.PortRule to avoid a circular import.
type PortRule struct {
	Port  uint16
	Proto string
}

// ClientRecord holds server-side data for a registered client.
type ClientRecord struct {
	// Name is the human-readable client identifier (e.g. "alice").
	Name string

	// Ed25519PubKey is the client's signing public key.
	Ed25519PubKey ed25519.PublicKey

	// Ports is the effective list of ports to open on a successful knock.
	// This already includes the health port unless DisableHealthPort is true.
	Ports []PortRule

	// Expires is an optional expiry time for this client's key.
	Expires *time.Time
}

// Options holds server startup configuration.
type Options struct {
	// UDPPort is the port to listen for SPA knock packets.
	UDPPort uint16

	// HealthPort is the TCP port used for post-knock liveness checks.
	// It is opened by the firewall manager alongside the client's other ports
	// after a successful knock. It is never permanently open.
	HealthPort uint16

	// ServerPrivKey is the server's Curve25519 private key (32 bytes).
	ServerPrivKey [internlcrypto.Curve25519KeySize]byte

	// ReplayWindow is the maximum accepted packet age.
	ReplayWindow time.Duration

	// Clients is the list of registered clients.
	Clients []*ClientRecord

	// OnKnock is called for each successfully verified knock.
	OnKnock KnockHandler

	// Log is the structured logger.
	Log *slog.Logger
}

// Server is the running openme server instance.
type Server struct {
	opts        *Options
	replayCache *replayCache
}

// New creates a new Server with the given options.
func New(opts *Options) *Server {
	return &Server{
		opts:        opts,
		replayCache: newReplayCache(opts.ReplayWindow),
	}
}

// Run starts the UDP listener. It blocks until ctx is cancelled.
// The health port is managed entirely by the firewall — this method no longer
// opens any TCP listener of its own.
func (s *Server) Run(ctx context.Context) error {
	addr := fmt.Sprintf(":%d", s.opts.UDPPort)
	conn, err := net.ListenPacket("udp", addr)
	if err != nil {
		return fmt.Errorf("listening UDP %s: %w", addr, err)
	}
	defer conn.Close()

	s.opts.Log.Info("openme server listening",
		"udp_port", s.opts.UDPPort,
		"health_port", s.opts.HealthPort,
		"note", "health port is closed until a client authenticates",
	)

	go func() {
		<-ctx.Done()
		conn.Close()
	}()

	buf := make([]byte, protocol.PacketSize*2) // oversized to detect bad packets
	for {
		n, srcAddr, err := conn.ReadFrom(buf)
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				s.opts.Log.Warn("UDP read error", "err", err)
				continue
			}
		}
		go s.handlePacket(buf[:n], srcAddr)
	}
}

// handlePacket processes a single received UDP packet.
// Every failure path silently discards the packet — the server never responds.
func (s *Server) handlePacket(raw []byte, srcAddr net.Addr) {
	srcIP := extractIP(srcAddr)

	if len(raw) != protocol.PacketSize {
		s.opts.Log.Debug("dropping packet: wrong size", "size", len(raw), "src", srcIP)
		return
	}
	if raw[protocol.OffVersion] != protocol.Version {
		s.opts.Log.Debug("dropping packet: wrong version", "version", raw[0], "src", srcIP)
		return
	}

	var ephemeralPub [internlcrypto.Curve25519KeySize]byte
	copy(ephemeralPub[:], raw[protocol.OffEphemeralPubKey:protocol.OffEphemeralPubKey+internlcrypto.Curve25519KeySize])

	sharedKey, err := internlcrypto.ECDHSharedSecret(s.opts.ServerPrivKey, ephemeralPub)
	if err != nil {
		s.opts.Log.Debug("ECDH failed", "src", srcIP, "err", err)
		return
	}

	nonce := raw[protocol.OffNonce : protocol.OffNonce+protocol.NonceSize]
	ciphertext := raw[protocol.OffCiphertext : protocol.OffCiphertext+protocol.CiphertextSize]

	plainBytes, err := internlcrypto.Decrypt(sharedKey, nonce, ciphertext)
	if err != nil {
		s.opts.Log.Debug("decryption failed", "src", srcIP)
		return
	}

	pt, err := protocol.UnmarshalPlaintext(plainBytes)
	if err != nil {
		s.opts.Log.Debug("unmarshal plaintext failed", "src", srcIP, "err", err)
		return
	}

	if err := s.replayCache.Check(pt.Timestamp, pt.RandomNonce); err != nil {
		s.opts.Log.Warn("replay detected", "src", srcIP, "err", err)
		return
	}

	sigMsg := raw[:protocol.SignedPortionSize]
	sig := raw[protocol.OffSignature : protocol.OffSignature+internlcrypto.Curve25519KeySize*2]

	client := s.findClient(sigMsg, sig)
	if client == nil {
		s.opts.Log.Warn("unknown or invalid client signature", "src", srcIP)
		return
	}

	if client.Expires != nil && time.Now().After(*client.Expires) {
		s.opts.Log.Warn("client key expired", "client", client.Name, "expired", *client.Expires)
		return
	}

	targetIP := pt.TargetIP
	if targetIP.IsUnspecified() {
		targetIP = srcIP
	}

	s.opts.Log.Info("valid knock received",
		"client", client.Name,
		"src", srcIP,
		"target_ip", targetIP,
		"fingerprint", internlcrypto.FingerprintKey(client.Ed25519PubKey),
	)

	if s.opts.OnKnock != nil {
		// client.Ports already includes the health port rule (injected by buildClientRecords).
		s.opts.OnKnock(client.Name, srcIP, targetIP, client.Ports)
	}
}

// findClient iterates registered clients and returns the first whose Ed25519
// public key produces a valid signature over sigMsg. Returns nil if none match.
func (s *Server) findClient(sigMsg, sig []byte) *ClientRecord {
	for _, c := range s.opts.Clients {
		if internlcrypto.Verify(c.Ed25519PubKey, sigMsg, sig) {
			return c
		}
	}
	return nil
}

// extractIP parses the IP address from a net.Addr (UDP remote address).
func extractIP(addr net.Addr) net.IP {
	switch a := addr.(type) {
	case *net.UDPAddr:
		return a.IP
	}
	host, _, _ := net.SplitHostPort(addr.String())
	return net.ParseIP(host)
}

// ────────────────────────────────────────────────────────────────────────────
// Replay cache
// ────────────────────────────────────────────────────────────────────────────

type replayCache struct {
	mu     sync.Mutex
	seen   map[string]time.Time
	window time.Duration
}

func newReplayCache(window time.Duration) *replayCache {
	rc := &replayCache{seen: make(map[string]time.Time), window: window}
	go rc.prune()
	return rc
}

// Check validates the timestamp is within the replay window and the nonce is
// fresh. Returns an error if either check fails; on success records the nonce.
func (rc *replayCache) Check(ts time.Time, nonce [protocol.RandomNonceSize]byte) error {
	if time.Since(ts).Abs() > rc.window {
		return protocol.ErrReplay
	}
	key := hex.EncodeToString(nonce[:])
	rc.mu.Lock()
	defer rc.mu.Unlock()
	if _, seen := rc.seen[key]; seen {
		return protocol.ErrReplay
	}
	rc.seen[key] = time.Now()
	return nil
}

// prune removes expired nonces from the cache every window/2 interval.
func (rc *replayCache) prune() {
	ticker := time.NewTicker(rc.window / 2)
	defer ticker.Stop()
	for range ticker.C {
		rc.mu.Lock()
		cutoff := time.Now().Add(-rc.window)
		for k, t := range rc.seen {
			if t.Before(cutoff) {
				delete(rc.seen, k)
			}
		}
		rc.mu.Unlock()
	}
}
