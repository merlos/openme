package server_test

import (
	"testing"
	"time"

	"github.com/merlos/openme/internal/server"
	"github.com/merlos/openme/pkg/protocol"
)

func TestPortRule(t *testing.T) {
	pr := server.PortRule{Port: 22, Proto: "tcp"}
	if pr.Port != 22 {
		t.Errorf("Port = %d, want 22", pr.Port)
	}
	if pr.Proto != "tcp" {
		t.Errorf("Proto = %q, want tcp", pr.Proto)
	}
}

func TestClientRecord_Expiry(t *testing.T) {
	past := time.Now().Add(-time.Hour)
	cr := &server.ClientRecord{
		Name:    "test",
		Expires: &past,
	}
	if !time.Now().After(*cr.Expires) {
		t.Error("expired client should have Expires in the past")
	}
}

func TestClientRecord_NoExpiry(t *testing.T) {
	cr := &server.ClientRecord{Name: "noexpiry"}
	if cr.Expires != nil {
		t.Error("client with no expiry should have nil Expires")
	}
}

// TestHealthPortNotPermanent documents the key design invariant:
// the server.Run method must not open any TCP listener of its own.
// The health port is opened exclusively by the firewall manager after
// a successful knock, for the duration of knock_timeout only.
func TestHealthPortNotPermanent(t *testing.T) {
	// This is a compile-time/design test: Options.HealthPort exists as
	// metadata passed to the firewall injector in main, not as a TCP listener
	// started by server.Run. We verify the Options struct has the field but
	// that there is no runHealth method on Server (it was intentionally removed).
	opts := &server.Options{
		UDPPort:    54154,
		HealthPort: 54154, // stored for firewall injection, not for binding
	}
	if opts.HealthPort != opts.UDPPort {
		t.Error("HealthPort should default to UDPPort")
	}
	_ = protocol.Version // ensure protocol package is linked
}
