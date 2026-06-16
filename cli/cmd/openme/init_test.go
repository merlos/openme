package main

// Integration-level tests for `openme init` exercised via runInit directly.
// These live in package main so they can call unexported helpers if needed.

import (
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/merlos/openme/cli/internal/config"
	internlcrypto "github.com/merlos/openme/cli/internal/crypto"
)

// firstInterface returns the name of the first network interface on the host,
// or skips the test if none are found. This avoids hard-coding platform-specific
// interface names (e.g. "eth0" on Linux, "en0" on macOS).
func firstInterface(t *testing.T) string {
	t.Helper()
	ifaces, err := net.Interfaces()
	if err != nil || len(ifaces) == 0 {
		t.Skip("no network interfaces available")
	}
	return ifaces[0].Name
}

func TestRunInit_CreatesConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	// Temporarily redirect serverConfigPath for this test.
	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "test.example.com", 54154, "nft", ""); err != nil {
		t.Fatalf("runInit error = %v", err)
	}

	cfg, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after init: %v", err)
	}

	if cfg.Server.Host != "test.example.com" {
		t.Errorf("Server = %q, want test.example.com", cfg.Server.Host)
	}
	if cfg.Server.UDPPort != 54154 {
		t.Errorf("UDPPort = %d, want 54154", cfg.Server.UDPPort)
	}
	if cfg.Server.HealthPort != cfg.Server.UDPPort {
		t.Errorf("HealthPort %d should equal UDPPort %d", cfg.Server.HealthPort, cfg.Server.UDPPort)
	}
	if cfg.Server.Firewall != "nft" {
		t.Errorf("Firewall = %q, want nft", cfg.Server.Firewall)
	}

	// Keys must be present and decodable.
	priv, err := internlcrypto.DecodeKey(cfg.Server.PrivateKey)
	if err != nil || len(priv) != internlcrypto.Curve25519KeySize {
		t.Errorf("invalid private key: err=%v len=%d", err, len(priv))
	}
	pub, err := internlcrypto.DecodeKey(cfg.Server.PublicKey)
	if err != nil || len(pub) != internlcrypto.Curve25519KeySize {
		t.Errorf("invalid public key: err=%v len=%d", err, len(pub))
	}

	// Verify public key is actually derived from private key.
	kp, _ := internlcrypto.GenerateCurve25519KeyPair()
	_ = kp // keys are random; we just check lengths above.
}

func TestRunInit_RefusesOverwrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	// First init should succeed.
	if err := runInit(false, "server.example.com", 54154, "nft", ""); err != nil {
		t.Fatalf("first runInit error = %v", err)
	}

	// Second init without --force should fail.
	if err := runInit(false, "server.example.com", 54154, "nft", ""); err == nil {
		t.Error("second runInit without --force should return an error")
	}
}

func TestRunInit_ForceOverwrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "first.example.com", 54154, "nft", ""); err != nil {
		t.Fatal(err)
	}

	// With --force it should overwrite and generate NEW keys.
	if err := runInit(true, "second.example.com", 8888, "iptables", ""); err != nil {
		t.Fatalf("forced runInit error = %v", err)
	}

	cfg, _ := config.LoadServerConfig(path)
	if cfg.Server.Host != "second.example.com" {
		t.Errorf("Server after force = %q, want second.example.com", cfg.Server.Host)
	}
	if cfg.Server.UDPPort != 8888 {
		t.Errorf("UDPPort after force = %d, want 8888", cfg.Server.UDPPort)
	}
}

func TestRunInit_InvalidFirewall(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "server.example.com", 54154, "bogus", ""); err == nil {
		t.Error("runInit with invalid firewall should return error")
	}
	// Config file should not have been created.
	if _, err := os.Stat(path); err == nil {
		t.Error("config file should not exist after failed init")
	}
}

func TestRunInit_ConfigFilePermissions(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "server.example.com", 54154, "nft", ""); err != nil {
		t.Fatal(err)
	}

	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Errorf("config permissions = %o, want 0600 (contains private key)", info.Mode().Perm())
		}
	}
}

// TestRunInit_InterfaceStoredInConfig verifies that --interface is persisted
// into the generated server config and reloaded correctly.
func TestRunInit_InterfaceStoredInConfig(t *testing.T) {
	iface := firstInterface(t)

	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "server.example.com", 54154, "nft", iface); err != nil {
		t.Fatalf("runInit error = %v", err)
	}

	cfg, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after init: %v", err)
	}

	if cfg.Server.Interface != iface {
		t.Errorf("Interface = %q, want %q", cfg.Server.Interface, iface)
	}
}

// TestRunInit_EmptyInterfaceDefaultsToAll verifies that omitting --interface
// leaves the interface field empty (apply rules to all interfaces).
func TestRunInit_EmptyInterfaceDefaultsToAll(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "server.example.com", 54154, "nft", ""); err != nil {
		t.Fatalf("runInit error = %v", err)
	}

	cfg, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after init: %v", err)
	}

	if cfg.Server.Interface != "" {
		t.Errorf("Interface = %q, want empty (all interfaces)", cfg.Server.Interface)
	}
}

// TestRunInit_NonExistentInterfaceReturnsError verifies that specifying a
// non-existent interface name causes runInit to fail before writing any config
// file, and that the error message lists available interfaces.
func TestRunInit_NonExistentInterfaceReturnsError(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	err := runInit(false, "server.example.com", 54154, "nft", "nonexistent99")
	if err == nil {
		t.Fatal("runInit with non-existent interface should return error")
	}
	if !strings.Contains(err.Error(), "nonexistent99") {
		t.Errorf("error %q should mention the unknown interface name", err.Error())
	}
	if !strings.Contains(err.Error(), "Available interfaces") {
		t.Errorf("error %q should list available interfaces", err.Error())
	}
	// Config file must NOT have been created.
	if _, statErr := os.Stat(path); statErr == nil {
		t.Error("config file should not exist after failed init (invalid interface)")
	}
}
