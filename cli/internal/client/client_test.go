package client_test

import (
	"net"
	"testing"
	"time"

	"github.com/openme/openme/internal/client"
	internlcrypto "github.com/openme/openme/internal/crypto"
	"github.com/openme/openme/pkg/protocol"
)

// buildTestOptions creates a KnockOptions with freshly generated keys.
func buildTestOptions(t *testing.T, targetIP net.IP, port uint16) *client.KnockOptions {
	t.Helper()

	serverKP, err := internlcrypto.GenerateCurve25519KeyPair()
	if err != nil {
		t.Fatalf("server keypair: %v", err)
	}
	clientKP, err := internlcrypto.GenerateEd25519KeyPair()
	if err != nil {
		t.Fatalf("client keypair: %v", err)
	}

	return &client.KnockOptions{
		ServerHost:             "127.0.0.1",
		ServerUDPPort:          7777,
		ServerCurve25519PubKey: serverKP.PublicKey,
		ClientEd25519PrivKey:   clientKP.PrivateKey,
		TargetIP:               targetIP,
		TargetPort:             port,
	}
}

func TestBuildPacket_Size(t *testing.T) {
	opts := buildTestOptions(t, net.ParseIP("10.0.0.1"), 22)
	pkt, err := client.BuildPacket(opts)
	if err != nil {
		t.Fatalf("BuildPacket error = %v", err)
	}
	if len(pkt) != protocol.PacketSize {
		t.Errorf("packet size = %d, want %d", len(pkt), protocol.PacketSize)
	}
}

func TestBuildPacket_Version(t *testing.T) {
	opts := buildTestOptions(t, nil, 22)
	pkt, _ := client.BuildPacket(opts)
	if pkt[protocol.OffVersion] != protocol.Version {
		t.Errorf("version byte = %d, want %d", pkt[0], protocol.Version)
	}
}

func TestBuildPacket_UniquePerCall(t *testing.T) {
	opts := buildTestOptions(t, net.ParseIP("10.0.0.1"), 22)
	p1, _ := client.BuildPacket(opts)
	p2, _ := client.BuildPacket(opts)

	// Ephemeral key and nonce should differ between calls.
	ephem1 := p1[protocol.OffEphemeralPubKey : protocol.OffEphemeralPubKey+internlcrypto.Curve25519KeySize]
	ephem2 := p2[protocol.OffEphemeralPubKey : protocol.OffEphemeralPubKey+internlcrypto.Curve25519KeySize]

	same := true
	for i := range ephem1 {
		if ephem1[i] != ephem2[i] {
			same = false
			break
		}
	}
	if same {
		t.Error("two packets have identical ephemeral public keys (should be random)")
	}
}

func TestBuildPacket_WildcardIP(t *testing.T) {
	// nil IP should not cause a panic and should produce a valid packet.
	opts := buildTestOptions(t, nil, 22)
	pkt, err := client.BuildPacket(opts)
	if err != nil {
		t.Fatalf("BuildPacket with nil IP error = %v", err)
	}
	if len(pkt) != protocol.PacketSize {
		t.Errorf("packet size = %d, want %d", len(pkt), protocol.PacketSize)
	}
}

func TestHealthCheck_NoServer(t *testing.T) {
	// Port 1 is almost certainly not open; should return false quickly.
	if client.HealthCheck("127.0.0.1", 1, 200*time.Millisecond) {
		t.Error("HealthCheck should return false when no server is listening")
	}
}
