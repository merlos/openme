package config_test

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/merlos/openme/internal/config"
)

func TestDefaultServerConfig(t *testing.T) {
	cfg := config.DefaultServerConfig()
	if cfg.Server.UDPPort != 54154 {
		t.Errorf("UDPPort = %d, want 54154", cfg.Server.UDPPort)
	}
	if cfg.Server.Firewall != "nft" {
		t.Errorf("Firewall = %q, want nft", cfg.Server.Firewall)
	}
	if len(cfg.Defaults.Ports) == 0 {
		t.Error("default ports should not be empty")
	}
}

func TestSaveLoadServerConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	cfg := config.DefaultServerConfig()
	cfg.Server.PrivateKey = "testprivkey=="
	cfg.Server.PublicKey = "testpubkey=="
	cfg.Defaults.Server = "myserver.example.com"
	cfg.Clients["alice"] = &config.ClientEntry{
		Ed25519PubKey: "alicepub==",
		AllowedPorts: config.AllowedPorts{
			Mode: config.ModeDefault,
		},
	}

	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig error = %v", err)
	}

	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig error = %v", err)
	}

	if loaded.Defaults.Server != "myserver.example.com" {
		t.Errorf("Server = %q, want myserver.example.com", loaded.Defaults.Server)
	}
	if _, ok := loaded.Clients["alice"]; !ok {
		t.Error("client 'alice' not found after reload")
	}
}

func TestSaveLoadClientConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	cfg := &config.ClientConfig{
		Profiles: map[string]*config.Profile{
			"default": {
				ServerHost:    "1.2.3.4",
				ServerUDPPort: 54154,
				ServerPubKey:  "serverpub==",
				PrivateKey:    "clientpriv==",
				PublicKey:     "clientpub==",
				PostKnock:     "ssh user@1.2.3.4",
			},
		},
	}

	if err := config.SaveClientConfig(path, cfg); err != nil {
		t.Fatalf("SaveClientConfig error = %v", err)
	}

	// Check file permissions (secret key material). Windows does not support Unix permissions.
	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Errorf("config file permissions = %o, want 0600", info.Mode().Perm())
		}
	}

	loaded, err := config.LoadClientConfig(path)
	if err != nil {
		t.Fatalf("LoadClientConfig error = %v", err)
	}

	p, err := config.GetProfile(loaded, "default")
	if err != nil {
		t.Fatalf("GetProfile error = %v", err)
	}
	if p.ServerHost != "1.2.3.4" {
		t.Errorf("ServerHost = %q, want 1.2.3.4", p.ServerHost)
	}
	if p.PostKnock != "ssh user@1.2.3.4" {
		t.Errorf("PostKnock = %q, want 'ssh user@1.2.3.4'", p.PostKnock)
	}
}

func TestGetProfile_FallbackToDefault(t *testing.T) {
	cfg := &config.ClientConfig{
		Profiles: map[string]*config.Profile{
			"default": {ServerHost: "default-host"},
			"home":    {ServerHost: "home-host"},
		},
	}

	p, err := config.GetProfile(cfg, "")
	if err != nil {
		t.Fatalf("GetProfile(\"\") error = %v", err)
	}
	if p.ServerHost != "default-host" {
		t.Errorf("ServerHost = %q, want default-host", p.ServerHost)
	}
}

func TestGetProfile_NotFound(t *testing.T) {
	cfg := &config.ClientConfig{Profiles: map[string]*config.Profile{}}
	if _, err := config.GetProfile(cfg, "nonexistent"); err == nil {
		t.Error("GetProfile should return error for nonexistent profile")
	}
}

func TestEffectivePorts(t *testing.T) {
	defaults := []config.PortRule{{Port: 22, Proto: "tcp"}}
	extra := []config.PortRule{{Port: 2222, Proto: "tcp"}}

	tests := []struct {
		mode     config.AllowedPortsMode
		extra    []config.PortRule
		wantLen  int
		wantPort uint16
	}{
		{config.ModeDefault, nil, 1, 22},
		{config.ModeOnly, extra, 1, 2222},
		{config.ModeDefaultPlus, extra, 2, 22},
	}

	for _, tt := range tests {
		client := &config.ClientEntry{
			AllowedPorts: config.AllowedPorts{Mode: tt.mode, Ports: tt.extra},
		}
		ports := config.EffectivePorts(defaults, client)
		if len(ports) != tt.wantLen {
			t.Errorf("mode=%s: got %d ports, want %d", tt.mode, len(ports), tt.wantLen)
		}
		if ports[0].Port != tt.wantPort {
			t.Errorf("mode=%s: first port = %d, want %d", tt.mode, ports[0].Port, tt.wantPort)
		}
	}
}

func TestClientEntry_Expiry(t *testing.T) {
	past := time.Now().Add(-time.Hour)
	future := time.Now().Add(time.Hour)

	expired := &config.ClientEntry{Expires: &past}
	valid := &config.ClientEntry{Expires: &future}
	noExpiry := &config.ClientEntry{}

	if !expired.Expires.Before(time.Now()) {
		// Should be expired
		t.Error("expired entry should be before now")
	}
	if valid.Expires.Before(time.Now()) {
		t.Error("future entry should not be before now")
	}
	if noExpiry.Expires != nil {
		t.Error("nil expiry should mean no expiry")
	}
}
