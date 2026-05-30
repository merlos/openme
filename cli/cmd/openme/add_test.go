package main

// Tests for `openme add` exercised via runAdd directly.

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/merlos/openme/cli/internal/config"
)

// initServerConfig runs openme init into a temp file, sets the global
// serverConfigPath for the duration of the test, and returns the path.
func initServerConfig(t *testing.T, host string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.yaml")
	orig := serverConfigPath
	serverConfigPath = path
	t.Cleanup(func() { serverConfigPath = orig })
	if err := runInit(false, host, 54154, "nft"); err != nil {
		t.Fatalf("runInit: %v", err)
	}
	return path
}

// captureStdout redirects os.Stdout to a buffer for the duration of the test
// and returns the captured string when the returned function is called.
func captureStdout(t *testing.T) func() string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	orig := os.Stdout
	os.Stdout = w
	return func() string {
		w.Close()
		os.Stdout = orig
		var buf bytes.Buffer
		io.Copy(&buf, r) //nolint:errcheck
		r.Close()
		return buf.String()
	}
}

func TestRunAdd_AddsClientToConfig(t *testing.T) {
	initServerConfig(t, "server.example.com")

	if err := runAdd("alice", false, "", false, "", "", ""); err != nil {
		t.Fatalf("runAdd error = %v", err)
	}

	cfg, err := config.LoadServerConfig(serverConfigPath)
	if err != nil {
		t.Fatalf("LoadServerConfig: %v", err)
	}

	entry, ok := cfg.Clients["alice"]
	if !ok {
		t.Fatal("client alice not found in config")
	}
	if entry.Ed25519PubKey == "" {
		t.Error("ed25519_pubkey is empty")
	}
}

func TestRunAdd_DefaultProfileName(t *testing.T) {
	initServerConfig(t, "server.example.com")
	collect := captureStdout(t)

	if err := runAdd("alice", false, "", false, "", "", ""); err != nil {
		collect()
		t.Fatalf("runAdd error = %v", err)
	}

	output := collect()
	// The generated YAML must contain "default:" as the profile key.
	if !strings.Contains(output, "default:") {
		t.Errorf("expected profile key %q in output, got:\n%s", "default:", output)
	}
}

func TestRunAdd_ProfileFlagOverridesDefault(t *testing.T) {
	initServerConfig(t, "server.example.com")
	collect := captureStdout(t)

	if err := runAdd("alice", false, "", false, "", "", "home"); err != nil {
		collect()
		t.Fatalf("runAdd error = %v", err)
	}

	output := collect()
	if !strings.Contains(output, "home:") {
		t.Errorf("expected profile key %q in output, got:\n%s", "home:", output)
	}
	if strings.Contains(output, "default:") {
		t.Errorf("output should not contain profile key %q when --profile home is set:\n%s", "default:", output)
	}
}

func TestRunAdd_ServerDefaultProfile(t *testing.T) {
	path := initServerConfig(t, "server.example.com")

	// Set default_profile in the server config.
	cfg, _ := config.LoadServerConfig(path)
	cfg.Server.DefaultProfile = "work"
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}

	collect := captureStdout(t)
	// No --profile flag → must use server.default_profile = "work".
	if err := runAdd("alice", false, "", false, "", "", ""); err != nil {
		collect()
		t.Fatalf("runAdd error = %v", err)
	}

	output := collect()
	if !strings.Contains(output, "work:") {
		t.Errorf("expected profile key %q in output, got:\n%s", "work:", output)
	}
}

func TestRunAdd_ProfileFlagTakesPrecedenceOverServerDefault(t *testing.T) {
	path := initServerConfig(t, "server.example.com")

	cfg, _ := config.LoadServerConfig(path)
	cfg.Server.DefaultProfile = "work"
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}

	collect := captureStdout(t)
	// --profile home must win over server.default_profile = "work".
	if err := runAdd("alice", false, "", false, "", "", "home"); err != nil {
		collect()
		t.Fatalf("runAdd error = %v", err)
	}

	output := collect()
	if !strings.Contains(output, "home:") {
		t.Errorf("expected profile key %q in output, got:\n%s", "home:", output)
	}
	if strings.Contains(output, "work:") {
		t.Errorf("output should not contain server default %q when --profile is set:\n%s", "work:", output)
	}
}

func TestRunAdd_DuplicateClientRejected(t *testing.T) {
	initServerConfig(t, "server.example.com")

	if err := runAdd("alice", false, "", false, "", "", ""); err != nil {
		t.Fatalf("first runAdd error = %v", err)
	}
	if err := runAdd("alice", false, "", false, "", "", ""); err == nil {
		t.Error("second runAdd for same client should return an error")
	}
}

func TestRunAdd_PortsCSV(t *testing.T) {
	path := initServerConfig(t, "server.example.com")

	if err := runAdd("bob", false, "", false, "", "default,443/tcp", ""); err != nil {
		t.Fatalf("runAdd error = %v", err)
	}

	cfg, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig: %v", err)
	}

	entry := cfg.Clients["bob"]
	if len(entry.AllowedPorts) != 2 {
		t.Fatalf("expected 2 allowed_ports, got %d: %v", len(entry.AllowedPorts), entry.AllowedPorts)
	}
	if entry.AllowedPorts[0] != "default" {
		t.Errorf("AllowedPorts[0] = %q, want %q", entry.AllowedPorts[0], "default")
	}
	if entry.AllowedPorts[1] != "443/tcp" {
		t.Errorf("AllowedPorts[1] = %q, want %q", entry.AllowedPorts[1], "443/tcp")
	}
}
