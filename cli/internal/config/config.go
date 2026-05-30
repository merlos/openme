// Package config handles reading and writing openme configuration files in YAML format.
//
// Server config is stored at /etc/openme/config.yaml (default).
// Client config is stored at ~/.openme/config.yaml.
package config

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// PortRule defines a port (or port range) and protocol to be opened on a successful knock.
// When EndPort is zero the rule matches exactly Port.
// When EndPort is non-zero it is the inclusive upper bound of the range [Port, EndPort].
type PortRule struct {
	Port    uint16 `yaml:"port"`
	Proto   string `yaml:"proto"`              // "tcp" or "udp"
	EndPort uint16 `yaml:"end_port,omitempty"` // non-zero when this rule represents a range
}

// PortSpec is a compact string representation of one or more port rules.
// Accepted forms:
//
//		"22"          — port 22, both tcp and udp
//		"22/tcp"      — port 22, tcp only
//	 "22/udp"      — port 22, udp only
//		"80-82"       — ports 80, 81, 82 on both tcp and udp
//		"80-82/tcp"   — ports 80, 81, 82 on tcp only
//
// A PortSpec may also be the name of a group defined in the top-level
// ports map (e.g. "default", "admin"). Group names are resolved by
// EffectivePorts and must not contain a "/" character.
type PortSpec string

// ExpandPortSpec parses a single inline PortSpec into one or more PortRule
// values. It does not resolve group names — call EffectivePorts for that.
//
// A range spec (e.g. "80-82/tcp") produces one PortRule per protocol with
// EndPort set, not one PortRule per individual port number.
//
// See PortSpec for accepted syntax.
func ExpandPortSpec(spec PortSpec) ([]PortRule, error) {
	s := strings.TrimSpace(string(spec))
	if s == "" {
		return nil, fmt.Errorf("empty port spec")
	}

	// Split optional protocol suffix.
	var protos []string
	portPart := s
	if idx := strings.LastIndex(s, "/"); idx >= 0 {
		proto := strings.ToLower(s[idx+1:])
		if proto != "tcp" && proto != "udp" {
			return nil, fmt.Errorf("invalid protocol %q in port spec %q (expected tcp or udp)", proto, spec)
		}
		protos = []string{proto}
		portPart = s[:idx]
	} else {
		protos = []string{"tcp", "udp"}
	}

	// Parse port or range.
	var startPort, endPort uint16
	if dashIdx := strings.Index(portPart, "-"); dashIdx >= 0 {
		lo, err := parsePort(portPart[:dashIdx], spec)
		if err != nil {
			return nil, err
		}
		hi, err := parsePort(portPart[dashIdx+1:], spec)
		if err != nil {
			return nil, err
		}
		if lo > hi {
			return nil, fmt.Errorf("invalid port range %q: start port %d is greater than end port %d", spec, lo, hi)
		}
		startPort, endPort = lo, hi
	} else {
		p, err := parsePort(portPart, spec)
		if err != nil {
			return nil, err
		}
		startPort, endPort = p, p
	}

	var rules []PortRule
	for _, proto := range protos {
		r := PortRule{Port: startPort, Proto: proto}
		if endPort != startPort {
			r.EndPort = endPort
		}
		rules = append(rules, r)
	}
	return rules, nil
}

func parsePort(s string, spec PortSpec) (uint16, error) {
	n, err := strconv.ParseUint(strings.TrimSpace(s), 10, 16)
	if err != nil || n == 0 || n > 65535 {
		return 0, fmt.Errorf("invalid port %q in spec %q", s, spec)
	}
	return uint16(n), nil
}

func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// ClientEntry represents a registered client on the server.
type ClientEntry struct {
	// Ed25519PubKey is the base64-encoded Ed25519 public key of the client.
	Ed25519PubKey string `yaml:"ed25519_pubkey"`

	// AllowedPorts is a list of port group names and/or inline port specs
	// that define which ports this client may open after a successful knock.
	//
	// Examples:
	//   allowed_ports: [default]            # use the "default" port group
	//   allowed_ports: [default, 443/tcp]   # default group plus HTTPS
	//   allowed_ports: [22/tcp, 8080-8090]  # explicit ports only
	//
	// If the list is empty the server falls back to the "default" group
	// (ports.default) when it exists.
	AllowedPorts []PortSpec `yaml:"allowed_ports,omitempty"`

	// Expires is an optional RFC3339 date after which the client key is rejected.
	// Omit or leave zero to never expire.
	Expires *time.Time `yaml:"expires,omitempty"`

	// DisableHealthPort disables automatic inclusion of the server health port
	// in this client's firewall rules. When true, openme status will not work
	// after knocking. Defaults to false (health port is always included).
	DisableHealthPort bool `yaml:"disable_health_port,omitempty"`
}

// ServerConfig is the top-level structure for /etc/openme/config.yaml.
type ServerConfig struct {
	Server struct {
		// Host is the public hostname or IP address of this server,
		// used when generating client config files via `openme add`.
		Host string `yaml:"host"`

		// UDPPort is the port the server listens on for SPA knock packets.
		UDPPort uint16 `yaml:"udp_port"`

		// HealthPort is the TCP port used for liveness checks.
		// Defaults to the same value as UDPPort.
		HealthPort uint16 `yaml:"health_port"`

		// Firewall selects the firewall backend: "iptables" or "nft".
		Firewall string `yaml:"firewall"`

		// KnockTimeout is how long a firewall rule stays open after a valid knock.
		KnockTimeout Duration `yaml:"knock_timeout"`

		// ReplayWindow is the maximum age of an accepted knock timestamp.
		ReplayWindow Duration `yaml:"replay_window"`

		// PrivateKey is the base64-encoded Curve25519 private key.
		PrivateKey string `yaml:"private_key"`

		// PublicKey is the base64-encoded Curve25519 public key (derived from PrivateKey).
		// Stored for convenience so clients can be provisioned easily.
		PublicKey string `yaml:"public_key"`

		// OpenKnockPort controls whether the server installs a firewall rule
		// that accepts UDP traffic on UDPPort when it starts.
		// Defaults to true. Set to false when the host's existing firewall
		// configuration already opens the knock port and you do not want
		// openme to manage that rule.
		OpenKnockPort *bool `yaml:"open_knock_port,omitempty"`

		// DefaultProfile is the profile name written into client configs
		// generated by `openme add`. Defaults to "default" when empty.
		// Can be overridden per-invocation with `openme add --profile NAME`.
		DefaultProfile string `yaml:"default_profile,omitempty"`

		// DropPorts controls whether the server installs DROP rules for all
		// ports managed by openme (i.e. every port in the ports map and any
		// inline port spec assigned to a client).
		//
		// When true the server adds DROP rules at startup so all managed ports
		// are blocked by default; the per-client ACCEPT rules inserted on a
		// successful knock take effect first (they appear before the DROP in the
		// chain). The DROP rules are removed when the server stops.
		//
		// Set to false (default) when your base firewall policy already drops
		// traffic on the managed ports and you do not want openme to add
		// duplicate rules.
		DropPorts *bool `yaml:"drop_ports,omitempty"`
	} `yaml:"server"`

	// Ports defines named groups of port specs available to clients.
	// The group named "default" is used as a fallback for clients whose
	// allowed_ports list is empty.
	//
	// Example:
	//   ports:
	//     default:
	//       - 22/tcp
	//     admin:
	//       - 22/tcp
	//       - 443/tcp
	//       - 8080-8090/tcp
	Ports map[string][]PortSpec `yaml:"ports,omitempty"`

	// Clients maps a client name (e.g. "alice") to its configuration.
	Clients map[string]*ClientEntry `yaml:"clients"`
}

// DefaultServerConfig returns a ServerConfig with sensible defaults.
func DefaultServerConfig() *ServerConfig {
	cfg := &ServerConfig{}
	cfg.Server.UDPPort = 54154
	cfg.Server.HealthPort = 54154
	cfg.Server.Firewall = "nft"
	cfg.Server.KnockTimeout = Duration{30 * time.Second}
	cfg.Server.ReplayWindow = Duration{60 * time.Second}
	cfg.Ports = map[string][]PortSpec{"default": {"22/tcp"}}
	cfg.Clients = make(map[string]*ClientEntry)
	return cfg
}

// Profile is a single named client profile in the client config.
type Profile struct {
	// ServerHost is the hostname or IP of the openme server.
	ServerHost string `yaml:"server_host"`

	// ServerUDPPort is the UDP port to send knock packets to.
	ServerUDPPort uint16 `yaml:"server_udp_port"`

	// ServerPubKey is the base64-encoded Curve25519 public key of the server.
	ServerPubKey string `yaml:"server_pubkey"`

	// PrivateKey is the base64-encoded Ed25519 private key of this client.
	PrivateKey string `yaml:"private_key"`

	// PublicKey is the base64-encoded Ed25519 public key of this client.
	PublicKey string `yaml:"public_key"`

	// PostKnock is an optional shell command to run after a successful knock.
	PostKnock string `yaml:"post_knock,omitempty"`
}

// ClientConfig is the top-level structure for ~/.openme/config.yaml.
type ClientConfig struct {
	// Profiles maps profile names to their configuration.
	// The profile named "default" is used when no profile is specified.
	Profiles map[string]*Profile `yaml:"profiles"`
}

// DefaultClientConfigPath returns the default path to the client config file.
func DefaultClientConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ".openme/config.yaml"
	}
	return filepath.Join(home, ".openme", "config.yaml")
}

// LoadServerConfig reads and parses a server config file from path.
func LoadServerConfig(path string) (*ServerConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading server config %s: %w", path, err)
	}
	cfg := DefaultServerConfig()
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parsing server config: %w", err)
	}
	return cfg, nil
}

// clientsOnly is used to marshal only the clients map into YAML.
type clientsOnly struct {
	Clients map[string]*ClientEntry `yaml:"clients"`
}

// clientsMapToNode marshals clients into a *yaml.Node representing the value
// of the "clients" mapping key. This node can be spliced into an existing AST.
func clientsMapToNode(clients map[string]*ClientEntry) (*yaml.Node, error) {
	if clients == nil {
		clients = make(map[string]*ClientEntry)
	}
	data, err := yaml.Marshal(clientsOnly{Clients: clients})
	if err != nil {
		return nil, fmt.Errorf("marshalling clients: %w", err)
	}
	var tmpDoc yaml.Node
	if err := yaml.Unmarshal(data, &tmpDoc); err != nil {
		return nil, fmt.Errorf("parsing clients node: %w", err)
	}
	if tmpDoc.Kind != yaml.DocumentNode || len(tmpDoc.Content) == 0 {
		return nil, fmt.Errorf("unexpected clients marshal structure")
	}
	mapping := tmpDoc.Content[0]
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		if mapping.Content[i].Value == "clients" {
			return mapping.Content[i+1], nil
		}
	}
	// Fallback: return an empty mapping node (clients: {}).
	return &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}, nil
}

// updateClientsInAST parses existing YAML bytes into an AST, replaces (or
// appends) the "clients" value node with one freshly marshalled from clients,
// and returns the re-serialised YAML. All comments and non-clients content are
// preserved exactly.
func updateClientsInAST(existing []byte, clients map[string]*ClientEntry) ([]byte, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(existing, &doc); err != nil {
		return nil, fmt.Errorf("parsing config AST: %w", err)
	}
	if doc.Kind != yaml.DocumentNode || len(doc.Content) == 0 {
		return nil, fmt.Errorf("config is not a YAML document")
	}
	root := doc.Content[0]
	if root.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("config top-level value is not a mapping")
	}

	newValNode, err := clientsMapToNode(clients)
	if err != nil {
		return nil, err
	}

	found := false
	for i := 0; i+1 < len(root.Content); i += 2 {
		keyNode := root.Content[i]
		if keyNode.Kind == yaml.ScalarNode && keyNode.Value == "clients" {
			// Preserve any foot comment on the old value node (e.g. trailing comments).
			newValNode.FootComment = root.Content[i+1].FootComment
			root.Content[i+1] = newValNode
			found = true
			break
		}
	}
	if !found {
		// Append a new "clients:" key-value pair if the key does not exist.
		keyNode := &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: "clients"}
		root.Content = append(root.Content, keyNode, newValNode)
	}

	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return nil, fmt.Errorf("encoding updated config: %w", err)
	}
	if err := enc.Close(); err != nil {
		return nil, fmt.Errorf("closing yaml encoder: %w", err)
	}
	return buf.Bytes(), nil
}

// SaveServerConfig writes the server config to path, creating directories as needed.
//
// When the file already exists its YAML AST is parsed and only the "clients"
// mapping is replaced — all other content (comments, custom port groups,
// custom formatting) is preserved. Falls back to a full marshal when the
// existing file cannot be parsed or when the file does not yet exist.
func SaveServerConfig(path string, cfg *ServerConfig) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("creating config directory: %w", err)
	}

	// Try AST-surgical update when the file already exists.
	if existing, err := os.ReadFile(path); err == nil {
		updated, err := updateClientsInAST(existing, cfg.Clients)
		if err == nil {
			return os.WriteFile(path, updated, 0o600)
		}
		// AST update failed (e.g. corrupt YAML) — fall through to full marshal.
	}

	// New file or unrecoverable AST: full marshal (comments not preserved).
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshalling server config: %w", err)
	}
	return os.WriteFile(path, data, 0o600)
}

// LoadClientConfig reads and parses a client config file from path.
func LoadClientConfig(path string) (*ClientConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading client config %s: %w", path, err)
	}
	cfg := &ClientConfig{Profiles: make(map[string]*Profile)}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parsing client config: %w", err)
	}
	return cfg, nil
}

// SaveClientConfig writes the client config to path, creating directories as needed.
// The file is written with 0600 permissions since it contains private keys.
func SaveClientConfig(path string, cfg *ClientConfig) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("creating config directory: %w", err)
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshalling client config: %w", err)
	}
	return os.WriteFile(path, data, 0o600)
}

// GetProfile returns the named profile, falling back to "default" if name is empty.
// Returns an error if the profile does not exist.
func GetProfile(cfg *ClientConfig, name string) (*Profile, error) {
	if name == "" {
		name = "default"
	}
	p, ok := cfg.Profiles[name]
	if !ok {
		return nil, fmt.Errorf("profile %q not found in config", name)
	}
	return p, nil
}

// EffectivePorts resolves the full list of PortRule values for a client.
//
// Each item in client.AllowedPorts is either a named group (looked up in
// groups) or an inline PortSpec (e.g. "443/tcp", "80-82"). If the client's
// AllowedPorts list is empty, the "default" group is used as a fallback when
// it exists.
//
// Returns an error if a spec is malformed or a named group is not found.
func EffectivePorts(groups map[string][]PortSpec, client *ClientEntry) ([]PortRule, error) {
	specs := client.AllowedPorts
	if len(specs) == 0 {
		specs = []PortSpec{"default"}
	}

	var rules []PortRule
	for _, spec := range specs {
		s := strings.TrimSpace(string(spec))
		// A spec is treated as a named group when it contains no "/" and no "-"
		// and is not a pure decimal number (port numbers are all digits).
		looksLikeGroup := !strings.Contains(s, "/") && !strings.Contains(s, "-") && !isAllDigits(s)
		if looksLikeGroup {
			group, ok := groups[s]
			if !ok {
				if spec == "default" {
					// No default group defined — return empty list (no ports opened).
					continue
				}
				return nil, fmt.Errorf("unknown port group %q", s)
			}
			for _, gs := range group {
				expanded, err := ExpandPortSpec(gs)
				if err != nil {
					return nil, fmt.Errorf("group %q: %w", s, err)
				}
				rules = append(rules, expanded...)
			}
			continue
		}
		// Treat as an inline port spec.
		expanded, err := ExpandPortSpec(spec)
		if err != nil {
			return nil, err
		}
		rules = append(rules, expanded...)
	}
	return rules, nil
}

// ValidatePortSpec checks that a single PortSpec is either a valid inline port
// spec (parseable by ExpandPortSpec) or a named group that exists in groups.
// It returns nil on success, or a descriptive error on failure.
//
// Use this during client registration (openme add) to catch typos early.
func ValidatePortSpec(spec PortSpec, groups map[string][]PortSpec) ([]PortRule, error) {
	s := strings.TrimSpace(string(spec))
	looksLikeGroup := !strings.Contains(s, "/") && !strings.Contains(s, "-") && !isAllDigits(s)
	if looksLikeGroup {
		if _, ok := groups[s]; !ok {
			return nil, fmt.Errorf("unknown port group %q (defined groups: %s)",
				s, joinGroupNames(groups))
		}
		return nil, nil // group exists; full expansion not needed here
	}
	return ExpandPortSpec(spec)
}

// joinGroupNames returns a comma-separated sorted list of group names for
// inclusion in error messages.
func joinGroupNames(groups map[string][]PortSpec) string {
	names := make([]string, 0, len(groups))
	for k := range groups {
		names = append(names, k)
	}
	// Sort for deterministic output.
	for i := 1; i < len(names); i++ {
		for j := i; j > 0 && names[j] < names[j-1]; j-- {
			names[j], names[j-1] = names[j-1], names[j]
		}
	}
	return strings.Join(names, ", ")
}

// Duration is a wrapper around time.Duration that supports YAML marshalling
// in human-readable form (e.g. "30s", "1m").
type Duration struct {
	time.Duration
}

func (d Duration) MarshalYAML() (interface{}, error) {
	return d.String(), nil
}

func (d *Duration) UnmarshalYAML(value *yaml.Node) error {
	dur, err := time.ParseDuration(value.Value)
	if err != nil {
		return err
	}
	d.Duration = dur
	return nil
}
