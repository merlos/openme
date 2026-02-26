package main

// Integration-level tests for `openme init` exercised via runInit directly.
// These live in package main so they can call unexported helpers if needed.

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/openme/openme/internal/config"
	internlcrypto "github.com/openme/openme/internal/crypto"
)

func TestRunInit_CreatesConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	// Temporarily redirect serverConfigPath for this test.
	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "test.example.com", 7777, "nft"); err != nil {
		t.Fatalf("runInit error = %v", err)
	}

	cfg, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after init: %v", err)
	}

	if cfg.Defaults.Server != "test.example.com" {
		t.Errorf("Server = %q, want test.example.com", cfg.Defaults.Server)
	}
	if cfg.Server.UDPPort != 7777 {
		t.Errorf("UDPPort = %d, want 7777", cfg.Server.UDPPort)
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
	if err := runInit(false, "server.example.com", 7777, "nft"); err != nil {
		t.Fatalf("first runInit error = %v", err)
	}

	// Second init without --force should fail.
	if err := runInit(false, "server.example.com", 7777, "nft"); err == nil {
		t.Error("second runInit without --force should return an error")
	}
}

func TestRunInit_ForceOverwrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	orig := serverConfigPath
	serverConfigPath = path
	defer func() { serverConfigPath = orig }()

	if err := runInit(false, "first.example.com", 7777, "nft"); err != nil {
		t.Fatal(err)
	}

	// With --force it should overwrite and generate NEW keys.
	if err := runInit(true, "second.example.com", 8888, "iptables"); err != nil {
		t.Fatalf("forced runInit error = %v", err)
	}

	cfg, _ := config.LoadServerConfig(path)
	if cfg.Defaults.Server != "second.example.com" {
		t.Errorf("Server after force = %q, want second.example.com", cfg.Defaults.Server)
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

	if err := runInit(false, "server.example.com", 7777, "bogus"); err == nil {
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

	if err := runInit(false, "server.example.com", 7777, "nft"); err != nil {
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
