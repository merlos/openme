// Package config handles reading and writing openme configuration files in YAML format.
//
// Server config is stored at /etc/openme/config.yaml (default).
// Client config is stored at ~/.openme/config.yaml.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

// PortRule defines a port and protocol to be opened on a successful knock.
type PortRule struct {
	Port  uint16 `yaml:"port"`
	Proto string `yaml:"proto"` // "tcp" or "udp"
}

// AllowedPortsMode controls how a client's allowed_ports relates to the server defaults.
type AllowedPortsMode string

const (
	// ModeDefault opens only the server's default ports.
	ModeDefault AllowedPortsMode = "default"

	// ModeOnly opens only the ports listed in the client's ports field.
	ModeOnly AllowedPortsMode = "only"

	// ModeDefaultPlus opens the server's default ports plus the client's extra ports.
	ModeDefaultPlus AllowedPortsMode = "default_plus"
)

// AllowedPorts defines which ports a client is permitted to open.
type AllowedPorts struct {
	Mode  AllowedPortsMode `yaml:"mode"`
	Ports []PortRule       `yaml:"ports,omitempty"`
}

// ClientEntry represents a registered client on the server.
type ClientEntry struct {
	// Ed25519PubKey is the base64-encoded Ed25519 public key of the client.
	Ed25519PubKey string `yaml:"ed25519_pubkey"`

	// AllowedPorts controls which ports this client may open.
	AllowedPorts AllowedPorts `yaml:"allowed_ports"`

	// Expires is an optional RFC3339 date after which the client key is rejected.
	// Omit or leave zero to never expire.
	Expires *time.Time `yaml:"expires,omitempty"`

	// DisableHealthPort disables automatic inclusion of the server health port
	// in this client's firewall rules. When true, openme status will not work
	// after knocking. Defaults to false (health port is always included).
	DisableHealthPort bool `yaml:"disable_health_port,omitempty"`
}

// ServerDefaults holds server-wide default settings.
type ServerDefaults struct {
	// Server is the public hostname or IP address of this server,
	// used when generating client config files via `openme add`.
	Server string `yaml:"server"`

	// Ports is the list of ports opened for every authenticated client
	// unless overridden by the client's AllowedPorts mode.
	Ports []PortRule `yaml:"ports"`
}

// ServerConfig is the top-level structure for /etc/openme/config.yaml.
type ServerConfig struct {
	Server struct {
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
	} `yaml:"server"`

	Defaults ServerDefaults `yaml:"defaults"`

	// Clients maps a client name (e.g. "rayan") to its configuration.
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
	cfg.Defaults.Ports = []PortRule{{Port: 22, Proto: "tcp"}}
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

// SaveServerConfig writes the server config to path, creating directories as needed.
func SaveServerConfig(path string, cfg *ServerConfig) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("creating config directory: %w", err)
	}
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

// EffectivePorts returns the list of ports to open for a client, considering
// the client's AllowedPorts mode and the server's defaults.
func EffectivePorts(defaults []PortRule, client *ClientEntry) []PortRule {
	switch client.AllowedPorts.Mode {
	case ModeOnly:
		return client.AllowedPorts.Ports
	case ModeDefaultPlus:
		combined := make([]PortRule, 0, len(defaults)+len(client.AllowedPorts.Ports))
		combined = append(combined, defaults...)
		combined = append(combined, client.AllowedPorts.Ports...)
		return combined
	default: // ModeDefault or unset
		return defaults
	}
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
