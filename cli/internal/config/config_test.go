package config_test

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/merlos/openme/cli/internal/config"
)

func TestDefaultServerConfig(t *testing.T) {
	cfg := config.DefaultServerConfig()
	if cfg.Server.UDPPort != 54154 {
		t.Errorf("UDPPort = %d, want 54154", cfg.Server.UDPPort)
	}
	if cfg.Server.Firewall != "nft" {
		t.Errorf("Firewall = %q, want nft", cfg.Server.Firewall)
	}
	defaultGroup, ok := cfg.Ports["default"]
	if !ok || len(defaultGroup) == 0 {
		t.Error("default port group should be defined and non-empty")
	}
}

func TestSaveLoadServerConfig(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")

	cfg := config.DefaultServerConfig()
	cfg.Server.PrivateKey = "testprivkey=="
	cfg.Server.PublicKey = "testpubkey=="
	cfg.Server.Host = "myserver.example.com"
	cfg.Clients["alice"] = &config.ClientEntry{
		Ed25519PubKey: "alicepub==",
		AllowedPorts:  []config.PortSpec{"default"},
	}

	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig error = %v", err)
	}

	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig error = %v", err)
	}

	if loaded.Server.Host != "myserver.example.com" {
		t.Errorf("Host = %q, want myserver.example.com", loaded.Server.Host)
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

// ─── ExpandPortSpec tests ────────────────────────────────────────────────────

func TestExpandPortSpec(t *testing.T) {
	tests := []struct {
		spec      config.PortSpec
		wantPorts []config.PortRule
		wantErr   bool
	}{
		// Single port, explicit tcp
		{"22/tcp", []config.PortRule{{Port: 22, Proto: "tcp"}}, false},
		// Single port, explicit udp
		{"53/udp", []config.PortRule{{Port: 53, Proto: "udp"}}, false},
		// Single port, no protocol → both tcp and udp
		{"80", []config.PortRule{{Port: 80, Proto: "tcp"}, {Port: 80, Proto: "udp"}}, false},
		// Range, explicit tcp → one rule with EndPort set
		{"80-82/tcp", []config.PortRule{{Port: 80, Proto: "tcp", EndPort: 82}}, false},
		// Range, no protocol → one rule per proto, both with EndPort set
		{"80-81", []config.PortRule{{Port: 80, Proto: "tcp", EndPort: 81}, {Port: 80, Proto: "udp", EndPort: 81}}, false},
		// Single port range (lo == hi) → treated as single port, no EndPort
		{"443-443/tcp", []config.PortRule{{Port: 443, Proto: "tcp"}}, false},
		// Errors
		{"", nil, true},          // empty
		{"0/tcp", nil, true},     // port 0 invalid
		{"65536/tcp", nil, true}, // port too high
		{"abc/tcp", nil, true},   // non-numeric
		{"80-70/tcp", nil, true}, // reversed range
		{"22/icmp", nil, true},   // bad proto
		{"22/", nil, true},       // missing proto
	}

	for _, tt := range tests {
		rules, err := config.ExpandPortSpec(tt.spec)
		if tt.wantErr {
			if err == nil {
				t.Errorf("ExpandPortSpec(%q): expected error, got nil", tt.spec)
			}
			continue
		}
		if err != nil {
			t.Errorf("ExpandPortSpec(%q): unexpected error: %v", tt.spec, err)
			continue
		}
		if len(rules) != len(tt.wantPorts) {
			t.Errorf("ExpandPortSpec(%q): got %d rules, want %d", tt.spec, len(rules), len(tt.wantPorts))
			continue
		}
		for i, r := range rules {
			if r != tt.wantPorts[i] {
				t.Errorf("ExpandPortSpec(%q)[%d]: got %+v, want %+v", tt.spec, i, r, tt.wantPorts[i])
			}
		}
	}
}

// ─── EffectivePorts tests ────────────────────────────────────────────────────

func TestEffectivePorts_NamedGroup(t *testing.T) {
	groups := map[string][]config.PortSpec{
		"default": {"22/tcp"},
		"admin":   {"22/tcp", "443/tcp"},
	}

	client := &config.ClientEntry{AllowedPorts: []config.PortSpec{"admin"}}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 2 {
		t.Fatalf("got %d rules, want 2", len(rules))
	}
	if rules[0].Port != 22 || rules[1].Port != 443 {
		t.Errorf("unexpected rules: %+v", rules)
	}
}

func TestEffectivePorts_InlineSpec(t *testing.T) {
	groups := map[string][]config.PortSpec{"default": {"22/tcp"}}

	client := &config.ClientEntry{AllowedPorts: []config.PortSpec{"443/tcp", "8080/tcp"}}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 2 || rules[0].Port != 443 || rules[1].Port != 8080 {
		t.Errorf("unexpected rules: %+v", rules)
	}
}

func TestEffectivePorts_MixedGroupAndInline(t *testing.T) {
	groups := map[string][]config.PortSpec{
		"default": {"22/tcp"},
	}

	client := &config.ClientEntry{AllowedPorts: []config.PortSpec{"default", "443/tcp"}}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// default expands to 22/tcp; then 443/tcp → 2 rules total
	if len(rules) != 2 {
		t.Fatalf("got %d rules, want 2", len(rules))
	}
	if rules[0].Port != 22 || rules[1].Port != 443 {
		t.Errorf("unexpected rules: %+v", rules)
	}
}

func TestEffectivePorts_EmptyFallsBackToDefault(t *testing.T) {
	groups := map[string][]config.PortSpec{
		"default": {"22/tcp"},
	}

	client := &config.ClientEntry{AllowedPorts: nil}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 1 || rules[0].Port != 22 {
		t.Errorf("unexpected rules: %+v", rules)
	}
}

func TestEffectivePorts_EmptyWithNoDefaultGroup(t *testing.T) {
	groups := map[string][]config.PortSpec{} // no "default" group

	client := &config.ClientEntry{AllowedPorts: nil}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 0 {
		t.Errorf("expected empty rules, got %+v", rules)
	}
}

func TestEffectivePorts_UnknownGroup(t *testing.T) {
	groups := map[string][]config.PortSpec{"default": {"22/tcp"}}

	client := &config.ClientEntry{AllowedPorts: []config.PortSpec{"nonexistent"}}
	_, err := config.EffectivePorts(groups, client)
	if err == nil {
		t.Error("expected error for unknown group, got nil")
	}
}

func TestEffectivePorts_RangeSpec(t *testing.T) {
	groups := map[string][]config.PortSpec{}

	client := &config.ClientEntry{AllowedPorts: []config.PortSpec{"80-82/tcp"}}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// A range produces one rule with EndPort set.
	if len(rules) != 1 {
		t.Fatalf("got %d rules, want 1", len(rules))
	}
	if rules[0].Port != 80 || rules[0].EndPort != 82 || rules[0].Proto != "tcp" {
		t.Errorf("unexpected rule: %+v", rules[0])
	}
}

func TestEffectivePorts_NoProtoSpec(t *testing.T) {
	groups := map[string][]config.PortSpec{}

	// "8080" with no protocol → both tcp and udp
	client := &config.ClientEntry{AllowedPorts: []config.PortSpec{"8080"}}
	rules, err := config.EffectivePorts(groups, client)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(rules) != 2 {
		t.Fatalf("got %d rules, want 2", len(rules))
	}
}

// ─── ValidatePortSpec tests ───────────────────────────────────────────────────

func TestValidatePortSpec_KnownGroup(t *testing.T) {
	groups := map[string][]config.PortSpec{"default": {"22/tcp"}, "admin": {"443/tcp"}}

	if _, err := config.ValidatePortSpec("default", groups); err != nil {
		t.Errorf("expected no error for known group, got %v", err)
	}
	if _, err := config.ValidatePortSpec("admin", groups); err != nil {
		t.Errorf("expected no error for known group, got %v", err)
	}
}

func TestValidatePortSpec_UnknownGroup(t *testing.T) {
	groups := map[string][]config.PortSpec{"default": {"22/tcp"}}

	_, err := config.ValidatePortSpec("doesnotexist", groups)
	if err == nil {
		t.Fatal("expected error for unknown group, got nil")
	}
	// Error message should include the bad name and the list of valid groups.
	if !strings.Contains(err.Error(), "doesnotexist") {
		t.Errorf("error %q should mention the bad group name", err)
	}
	if !strings.Contains(err.Error(), "default") {
		t.Errorf("error %q should list defined groups", err)
	}
}

func TestValidatePortSpec_ValidInlineSpec(t *testing.T) {
	groups := map[string][]config.PortSpec{}

	cases := []config.PortSpec{"22/tcp", "53/udp", "8080", "80-82/tcp", "2000-2010"}
	for _, spec := range cases {
		if _, err := config.ValidatePortSpec(spec, groups); err != nil {
			t.Errorf("spec %q: unexpected error: %v", spec, err)
		}
	}
}

func TestValidatePortSpec_InvalidInlineSpec(t *testing.T) {
	groups := map[string][]config.PortSpec{}

	cases := []config.PortSpec{"99999/tcp", "abc/tcp", "22/icmp", ""}
	for _, spec := range cases {
		if _, err := config.ValidatePortSpec(spec, groups); err == nil {
			t.Errorf("spec %q: expected error, got nil", spec)
		}
	}
}

func TestValidatePortSpec_EmptyGroups(t *testing.T) {
	// A named group reference against an empty groups map should fail.
	groups := map[string][]config.PortSpec{}

	_, err := config.ValidatePortSpec("default", groups)
	if err == nil {
		t.Fatal("expected error when no groups are defined, got nil")
	}
}

func TestClientEntry_Expiry(t *testing.T) {
	past := time.Now().Add(-time.Hour)
	future := time.Now().Add(time.Hour)

	expired := &config.ClientEntry{Expires: &past}
	valid := &config.ClientEntry{Expires: &future}
	noExpiry := &config.ClientEntry{}

	if !expired.Expires.Before(time.Now()) {
		t.Error("expired entry should be before now")
	}
	if valid.Expires.Before(time.Now()) {
		t.Error("future entry should not be before now")
	}
	if noExpiry.Expires != nil {
		t.Error("nil expiry should mean no expiry")
	}
}

// ─── SaveServerConfig AST comment-preservation tests ─────────────────────────

// annotatedConfig writes a minimal server config with comments scattered in
// the header, server block, ports block, and directly above clients — no
// special markers needed. Returns the file path.
func annotatedConfig(t *testing.T, dir string) string {
	t.Helper()
	path := filepath.Join(dir, "config.yaml")
	content := "# openme server configuration\n" +
		"# my precious header comment\n" +
		"server:\n" +
		"  # server host comment\n" +
		"  host: testserver\n" +
		"  udp_port: 54154\n" +
		"  firewall: nft\n" +
		"  knock_timeout: 30s\n" +
		"  replay_window: 1m0s\n" +
		"  private_key: priv==\n" +
		"  public_key:  pub==\n" +
		"ports:\n" +
		"  # ports section comment\n" +
		"  default:\n" +
		"    - 22/tcp # SSH\n" +
		"# clients comment — use openme add to manage\n" +
		"clients: {}\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("writing annotated config: %v", err)
	}
	return path
}

func TestSaveServerConfig_ASTPreservesAllComments(t *testing.T) {
	dir := t.TempDir()
	path := annotatedConfig(t, dir)

	cfg, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig: %v", err)
	}
	cfg.Clients["alice"] = &config.ClientEntry{
		Ed25519PubKey: "alicepub==",
		AllowedPorts:  []config.PortSpec{"default"},
	}

	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}

	raw, _ := os.ReadFile(path)
	content := string(raw)

	for _, comment := range []string{
		"my precious header comment",
		"server host comment",
		"ports section comment",
		"clients comment",
	} {
		if !strings.Contains(content, comment) {
			t.Errorf("comment %q was lost after SaveServerConfig", comment)
		}
	}
	if !strings.Contains(content, "alice") {
		t.Error("client 'alice' not found in saved file")
	}
	// Server settings must not be corrupted.
	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after save: %v", err)
	}
	if loaded.Server.Host != "testserver" {
		t.Errorf("Host = %q, want testserver", loaded.Server.Host)
	}
}

func TestSaveServerConfig_ASTRoundTrip(t *testing.T) {
	// Three saves: add alice, add bob, revoke alice — comments survive throughout.
	dir := t.TempDir()
	path := annotatedConfig(t, dir)

	cfg, _ := config.LoadServerConfig(path)
	cfg.Clients["alice"] = &config.ClientEntry{Ed25519PubKey: "alicepub=="}
	_ = config.SaveServerConfig(path, cfg)

	cfg2, _ := config.LoadServerConfig(path)
	cfg2.Clients["bob"] = &config.ClientEntry{Ed25519PubKey: "bobpub=="}
	_ = config.SaveServerConfig(path, cfg2)

	cfg3, _ := config.LoadServerConfig(path)
	delete(cfg3.Clients, "alice")
	if err := config.SaveServerConfig(path, cfg3); err != nil {
		t.Fatalf("SaveServerConfig (revoke): %v", err)
	}

	raw, _ := os.ReadFile(path)
	content := string(raw)

	if !strings.Contains(content, "my precious header comment") {
		t.Error("header comment lost after multi-step round-trip")
	}
	if strings.Contains(content, "alice") {
		t.Error("revoked client 'alice' still present")
	}
	if !strings.Contains(content, "bob") {
		t.Error("client 'bob' missing after round-trip")
	}
	// Clients key must not be duplicated.
	if count := strings.Count(content, "\nclients:"); count != 1 {
		t.Errorf("expected 1 'clients:' key, found %d", count)
	}
}

func TestSaveServerConfig_ASTNoClientsKey(t *testing.T) {
	// A file without a "clients:" key gets the key appended cleanly.
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	content := "# top comment\n" +
		"server:\n" +
		"  host: x\n" +
		"  udp_port: 54154\n" +
		"  firewall: nft\n" +
		"  knock_timeout: 30s\n" +
		"  replay_window: 1m0s\n" +
		"  private_key: p==\n" +
		"  public_key: q==\n"
	_ = os.WriteFile(path, []byte(content), 0o600)

	cfg, _ := config.LoadServerConfig(path)
	cfg.Clients["alice"] = &config.ClientEntry{Ed25519PubKey: "alicepub=="}
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}

	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after add: %v", err)
	}
	if _, ok := loaded.Clients["alice"]; !ok {
		t.Error("client 'alice' not found after add")
	}
	raw, _ := os.ReadFile(path)
	if !strings.Contains(string(raw), "top comment") {
		t.Error("top comment lost when clients key was absent")
	}
}

func TestSaveServerConfig_ASTEmptyClients(t *testing.T) {
	// Saving an empty clients map produces valid YAML that round-trips correctly.
	dir := t.TempDir()
	path := annotatedConfig(t, dir)

	cfg, _ := config.LoadServerConfig(path)
	cfg.Clients = make(map[string]*config.ClientEntry)
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}
	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig: %v", err)
	}
	if len(loaded.Clients) != 0 {
		t.Errorf("expected 0 clients, got %d", len(loaded.Clients))
	}
}

func TestSaveServerConfig_ASTFallbackOnCorrupt(t *testing.T) {
	// A corrupt YAML file silently falls back to a full marshal — no error,
	// data is preserved (comments are lost, which is the acceptable trade-off).
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	_ = os.WriteFile(path, []byte("{{{{ not valid yaml"), 0o600)

	cfg := config.DefaultServerConfig()
	cfg.Server.Host = "recovered"
	cfg.Clients["alice"] = &config.ClientEntry{Ed25519PubKey: "alicepub=="}
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig on corrupt file: %v", err)
	}
	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig after fallback: %v", err)
	}
	if loaded.Server.Host != "recovered" {
		t.Errorf("Host = %q, want recovered", loaded.Server.Host)
	}
	if _, ok := loaded.Clients["alice"]; !ok {
		t.Error("client 'alice' not found after fallback save")
	}
}

func TestSaveServerConfig_ASTNewFile(t *testing.T) {
	// Saving to a path that does not exist creates dirs and the file via full marshal.
	dir := t.TempDir()
	path := filepath.Join(dir, "subdir", "config.yaml")

	cfg := config.DefaultServerConfig()
	cfg.Server.Host = "newserver"
	cfg.Clients["bob"] = &config.ClientEntry{Ed25519PubKey: "bobpub=="}
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}
	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig: %v", err)
	}
	if loaded.Server.Host != "newserver" {
		t.Errorf("Host = %q, want newserver", loaded.Server.Host)
	}
	if _, ok := loaded.Clients["bob"]; !ok {
		t.Error("client 'bob' not found")
	}
}

func TestSaveServerConfig_ASTPreservesPortsGroup(t *testing.T) {
	// A custom ports group added by the user is not removed by SaveServerConfig.
	dir := t.TempDir()
	path := annotatedConfig(t, dir)

	// Manually add a custom ports group to the on-disk file.
	raw, _ := os.ReadFile(path)
	raw = []byte(strings.Replace(string(raw),
		"  default:\n    - 22/tcp # SSH\n",
		"  default:\n    - 22/tcp # SSH\n  admin:\n    - 22/tcp\n    - 443/tcp\n", 1))
	_ = os.WriteFile(path, raw, 0o600)

	cfg, _ := config.LoadServerConfig(path)
	cfg.Clients["alice"] = &config.ClientEntry{Ed25519PubKey: "alicepub=="}
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}

	loaded, err := config.LoadServerConfig(path)
	if err != nil {
		t.Fatalf("LoadServerConfig: %v", err)
	}
	if _, ok := loaded.Ports["admin"]; !ok {
		t.Error("custom 'admin' port group was removed by SaveServerConfig")
	}
	if _, ok := loaded.Clients["alice"]; !ok {
		t.Error("client 'alice' not found")
	}
}

func TestSaveServerConfig_ASTMultipleClients(t *testing.T) {
	// Save several clients, verify all survive a reload.
	dir := t.TempDir()
	path := annotatedConfig(t, dir)

	cfg, _ := config.LoadServerConfig(path)
	for _, name := range []string{"alice", "bob", "carol", "dave"} {
		cfg.Clients[name] = &config.ClientEntry{
			Ed25519PubKey: name + "pub==",
			AllowedPorts:  []config.PortSpec{"default"},
		}
	}
	if err := config.SaveServerConfig(path, cfg); err != nil {
		t.Fatalf("SaveServerConfig: %v", err)
	}

	loaded, _ := config.LoadServerConfig(path)
	for _, name := range []string{"alice", "bob", "carol", "dave"} {
		if _, ok := loaded.Clients[name]; !ok {
			t.Errorf("client %q missing after save", name)
		}
	}
}
