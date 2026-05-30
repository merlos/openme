package main

// Tests for the allManagedPorts helper used by runServe when drop_ports is true.

import (
	"testing"

	"github.com/merlos/openme/cli/internal/config"
)

func TestAllManagedPorts_NamedGroups(t *testing.T) {
	cfg := &config.ServerConfig{
		Ports: map[string][]config.PortSpec{
			"default": {"22/tcp", "80/tcp"},
		},
	}
	ports, err := allManagedPorts(cfg)
	if err != nil {
		t.Fatalf("allManagedPorts error = %v", err)
	}
	if len(ports) != 2 {
		t.Errorf("got %d ports, want 2: %v", len(ports), ports)
	}
}

func TestAllManagedPorts_ClientInlineSpecs(t *testing.T) {
	cfg := &config.ServerConfig{
		Ports: map[string][]config.PortSpec{
			"default": {"22/tcp"},
		},
		Clients: map[string]*config.ClientEntry{
			"alice": {AllowedPorts: []config.PortSpec{"default", "443/tcp"}},
		},
	}
	ports, err := allManagedPorts(cfg)
	if err != nil {
		t.Fatalf("allManagedPorts error = %v", err)
	}
	// Should have 22/tcp (from default group) + 443/tcp (alice's inline spec).
	if len(ports) != 2 {
		t.Errorf("got %d ports, want 2: %v", len(ports), ports)
	}
}

func TestAllManagedPorts_Deduplication(t *testing.T) {
	cfg := &config.ServerConfig{
		Ports: map[string][]config.PortSpec{
			"default": {"22/tcp"},
			"extra":   {"22/tcp", "80/tcp"},
		},
		Clients: map[string]*config.ClientEntry{
			"alice": {AllowedPorts: []config.PortSpec{"default", "22/tcp"}},
		},
	}
	ports, err := allManagedPorts(cfg)
	if err != nil {
		t.Fatalf("allManagedPorts error = %v", err)
	}
	// Should have exactly 22/tcp and 80/tcp — duplicates collapsed.
	if len(ports) != 2 {
		t.Errorf("got %d ports, want 2: %v", len(ports), ports)
	}
}

func TestAllManagedPorts_Empty(t *testing.T) {
	cfg := &config.ServerConfig{}
	ports, err := allManagedPorts(cfg)
	if err != nil {
		t.Fatalf("allManagedPorts error = %v", err)
	}
	if len(ports) != 0 {
		t.Errorf("got %d ports, want 0", len(ports))
	}
}

func TestAllManagedPorts_PortRange(t *testing.T) {
	cfg := &config.ServerConfig{
		Ports: map[string][]config.PortSpec{
			"web": {"8080-8082/tcp"},
		},
	}
	ports, err := allManagedPorts(cfg)
	if err != nil {
		t.Fatalf("allManagedPorts error = %v", err)
	}
	// A range produces one rule with EndPort set, not one rule per port.
	if len(ports) != 1 {
		t.Errorf("got %d rules, want 1: %v", len(ports), ports)
	}
	p := ports[0]
	if p.Port != 8080 || p.EndPort != 8082 || p.Proto != "tcp" {
		t.Errorf("unexpected rule: %+v, want {Port:8080 Proto:tcp EndPort:8082}", p)
	}
}
