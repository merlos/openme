// Package firewall — session state persistence for `openme sessions`.
package firewall

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// SessionEntry holds metadata for one active or recently-expired knock event.
type SessionEntry struct {
	// ClientName is the human-readable client identifier (e.g. "alice").
	ClientName string `json:"client_name"`

	// IP is the firewall target IP that was opened.
	IP string `json:"ip"`

	// Ports lists the port rules that were unlocked.
	Ports []SessionPortRule `json:"ports"`

	// OpenedAt is when the firewall rule was created.
	OpenedAt time.Time `json:"opened_at"`

	// ExpiresAt is when the firewall rule will be automatically removed.
	ExpiresAt time.Time `json:"expires_at"`
}

// SessionPortRule is the JSON-serialisable form of a port rule stored in state.
type SessionPortRule struct {
	Port  uint16 `json:"port"`
	Proto string `json:"proto"`
}

// ServerState is the runtime snapshot written by `openme serve` and read by
// `openme sessions`.
//
// The file is written atomically (temp-file → rename) so readers never see a
// half-written state.
type ServerState struct {
	// UpdatedAt is the wall-clock time when this snapshot was last written.
	UpdatedAt time.Time `json:"updated_at"`

	// ActiveSessions lists clients whose firewall rules are currently open.
	ActiveSessions []SessionEntry `json:"active_sessions"`

	// LastSeen maps each client name to the time of their most recent
	// successful knock, regardless of whether the rule is still active.
	LastSeen map[string]time.Time `json:"last_seen"`
}

// ReadState reads a ServerState from path.
// Returns an empty state and a non-nil error if the file cannot be read or parsed.
//
// See https://openme.merlos.org/docs/configuration/server.html
func ReadState(path string) (ServerState, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return ServerState{}, err
	}
	var st ServerState
	if err := json.Unmarshal(b, &st); err != nil {
		return ServerState{}, err
	}
	return st, nil
}

// writeState serialises state to path atomically (write temp → rename).
// A no-op if path is empty, so callers can pass "" to disable persistence.
func writeState(path string, state ServerState) error {
	if path == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	state.UpdatedAt = time.Now()
	b, err := json.Marshal(state)
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
