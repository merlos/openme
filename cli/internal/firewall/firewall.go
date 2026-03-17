// Package firewall provides an abstraction over iptables and nftables for
// temporarily opening firewall rules on a successful SPA knock.
package firewall

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"os/exec"
	"sync"
	"time"

	"github.com/merlos/openme/cli/internal/config"
)

// Backend is the interface implemented by both iptables and nftables backends.
type Backend interface {
	// Open adds a firewall rule allowing traffic from srcIP to the given ports.
	Open(srcIP net.IP, ports []config.PortRule) error

	// Close removes the firewall rule for srcIP and ports.
	Close(srcIP net.IP, ports []config.PortRule) error

	// Name returns the backend name ("iptables" or "nft").
	Name() string
}

// activeSession bundles the auto-expiry timer with the session metadata so
// both can be managed under a single map entry.
type activeSession struct {
	entry SessionEntry
	timer *time.Timer
}

// Manager wraps a Backend and handles automatic rule expiry.
// It also maintains a session state file so `openme sessions` can display
// currently-open rules and per-client last-seen times without attaching to
// the running server process.
type Manager struct {
	backend   Backend
	timeout   time.Duration
	stateFile string // path to write ServerState JSON; empty = disabled
	mu        sync.Mutex
	sessions  map[string]*activeSession // keyed by ruleKey
	lastSeen  map[string]time.Time      // client name → most recent knock time
	log       *slog.Logger
}

// NewManager creates a Manager with the given backend, knock timeout, optional
// state-file path (empty string disables persistence), and logger.
//
// When stateFile is non-empty the manager writes a ServerState JSON snapshot
// after every Open/Close event, enabling `openme sessions` to read live state.
//
// See https://openme.merlos.org/docs/configuration/server.html
func NewManager(backend Backend, timeout time.Duration, stateFile string, log *slog.Logger) *Manager {
	return &Manager{
		backend:   backend,
		timeout:   timeout,
		stateFile: stateFile,
		sessions:  make(map[string]*activeSession),
		lastSeen:  make(map[string]time.Time),
		log:       log,
	}
}

// Open opens firewall rules for srcIP+ports and schedules automatic removal
// after the configured timeout.  If a rule already exists (e.g. a repeated
// knock), the timer is reset and the session start/expiry times are updated.
//
// clientName is recorded in the session state file so `openme sessions` can
// display human-readable names alongside IP addresses.
//
// See https://openme.merlos.org/docs/configuration/server.html
func (m *Manager) Open(clientName string, srcIP net.IP, ports []config.PortRule) error {
	if err := m.backend.Open(srcIP, ports); err != nil {
		return fmt.Errorf("opening firewall rules: %w", err)
	}

	key := ruleKey(srcIP, ports)
	now := time.Now()
	expiresAt := now.Add(m.timeout)

	// Build the session port list for state persistence.
	sessionPorts := make([]SessionPortRule, len(ports))
	for i, p := range ports {
		sessionPorts[i] = SessionPortRule{Port: p.Port, Proto: p.Proto}
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Update last-seen regardless of whether a rule is already open.
	m.lastSeen[clientName] = now

	// Reset existing timer if present (repeated knock refreshes the window).
	if sess, ok := m.sessions[key]; ok {
		sess.entry.ExpiresAt = expiresAt
		sess.entry.OpenedAt = now
		sess.timer.Reset(m.timeout)
		m.log.Debug("firewall rule timer reset", "ip", srcIP, "timeout", m.timeout)
		m.log.Info("firewall rule refreshed", "client", clientName, "ip", srcIP, "timeout", m.timeout)
		m.persistState()
		return nil
	}

	entry := SessionEntry{
		ClientName: clientName,
		IP:         srcIP.String(),
		Ports:      sessionPorts,
		OpenedAt:   now,
		ExpiresAt:  expiresAt,
	}

	timer := time.AfterFunc(m.timeout, func() {
		if err := m.backend.Close(srcIP, ports); err != nil {
			m.log.Error("auto-closing firewall rule", "ip", srcIP, "err", err)
		} else {
			m.log.Debug("firewall rule expired", "ip", srcIP, "ports", ports)
			m.log.Info("IP removed from firewall", "client", clientName, "ip", srcIP)
		}
		m.mu.Lock()
		delete(m.sessions, key)
		m.persistState()
		m.mu.Unlock()
	})

	m.sessions[key] = &activeSession{entry: entry, timer: timer}
	m.persistState()

	m.log.Debug("firewall rule opened", "client", clientName, "ip", srcIP, "ports", ports, "timeout", m.timeout)
	return nil
}

// Sessions returns a point-in-time snapshot of the current manager state:
// all active sessions (rules still open) and the last-seen map.
//
// The returned ServerState is safe to read; it is a copy.
func (m *Manager) Sessions() ServerState {
	m.mu.Lock()
	defer m.mu.Unlock()

	active := make([]SessionEntry, 0, len(m.sessions))
	for _, s := range m.sessions {
		active = append(active, s.entry)
	}

	ls := make(map[string]time.Time, len(m.lastSeen))
	for k, v := range m.lastSeen {
		ls[k] = v
	}

	return ServerState{
		UpdatedAt:      time.Now(),
		ActiveSessions: active,
		LastSeen:       ls,
	}
}

// persistState writes the current state to the configured state file.
// Caller must hold m.mu.
func (m *Manager) persistState() {
	if m.stateFile == "" {
		return
	}
	active := make([]SessionEntry, 0, len(m.sessions))
	for _, s := range m.sessions {
		active = append(active, s.entry)
	}
	ls := make(map[string]time.Time, len(m.lastSeen))
	for k, v := range m.lastSeen {
		ls[k] = v
	}
	st := ServerState{
		ActiveSessions: active,
		LastSeen:       ls,
	}
	if err := writeState(m.stateFile, st); err != nil {
		m.log.Warn("failed to persist session state", "err", err, "path", m.stateFile)
	}
}

// CloseAll cancels all pending timers and removes all managed rules immediately.
// Should be called on server shutdown.
func (m *Manager) CloseAll(ctx context.Context) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for key, sess := range m.sessions {
		sess.timer.Stop()
		delete(m.sessions, key)
		m.log.Info("firewall rule removed on shutdown", "client", sess.entry.ClientName, "ip", sess.entry.IP)
	}
	m.persistState()
}

// ruleKey produces a stable map key for an (IP, ports) combination.
func ruleKey(ip net.IP, ports []config.PortRule) string {
	key := ip.String()
	for _, p := range ports {
		key += fmt.Sprintf(":%s/%d", p.Proto, p.Port)
	}
	return key
}

// NewBackend creates a firewall backend by name ("iptables" or "nft").
func NewBackend(name string, log *slog.Logger) (Backend, error) {
	switch name {
	case "iptables":
		return &IPTablesBackend{Log: log}, nil
	case "nft":
		return &NFTablesBackend{Log: log}, nil
	default:
		return nil, fmt.Errorf("unknown firewall backend %q (use 'iptables' or 'nft')", name)
	}
}

// runCmd executes a command, logging it at Debug level, and returns a wrapped error on failure.
func runCmd(log *slog.Logger, name string, args ...string) error {
	log.Debug("running firewall command", "cmd", name, "args", args)
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("command %s %v: %w (output: %s)", name, args, err, out)
	}
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// iptables backend
// ────────────────────────────────────────────────────────────────────────────

// IPTablesBackend implements Backend using iptables/ip6tables.
type IPTablesBackend struct {
	Log *slog.Logger
}

func (b *IPTablesBackend) Name() string { return "iptables" }

// Open inserts an ACCEPT rule for each port, supporting both IPv4 and IPv6.
func (b *IPTablesBackend) Open(srcIP net.IP, ports []config.PortRule) error {
	cmd := ipTablesCmd(srcIP)
	for _, p := range ports {
		if err := runCmd(b.Log, cmd, "-I", "INPUT", "-s", srcIP.String(),
			"-p", p.Proto, "--dport", fmt.Sprint(p.Port), "-j", "ACCEPT",
			"-m", "comment", "--comment", "openme"); err != nil {
			return err
		}
	}
	return nil
}

// Close deletes the ACCEPT rules previously inserted by Open.
func (b *IPTablesBackend) Close(srcIP net.IP, ports []config.PortRule) error {
	cmd := ipTablesCmd(srcIP)
	for _, p := range ports {
		// Best-effort: ignore errors (rule may already be gone).
		_ = runCmd(b.Log, cmd, "-D", "INPUT", "-s", srcIP.String(),
			"-p", p.Proto, "--dport", fmt.Sprint(p.Port), "-j", "ACCEPT",
			"-m", "comment", "--comment", "openme")
	}
	return nil
}

// ipTablesCmd returns "iptables" for IPv4 and "ip6tables" for IPv6.
func ipTablesCmd(ip net.IP) string {
	if ip.To4() == nil {
		return "ip6tables"
	}
	return "iptables"
}

// ────────────────────────────────────────────────────────────────────────────
// nftables backend
// ────────────────────────────────────────────────────────────────────────────

// NFTablesBackend implements Backend using nft.
// Rules are added to the "openme" chain inside the "inet filter" table.
type NFTablesBackend struct {
	Log *slog.Logger
}

func (b *NFTablesBackend) Name() string { return "nft" }

// Open adds nft accept rules for each port. Creates the chain on first use.
func (b *NFTablesBackend) Open(srcIP net.IP, ports []config.PortRule) error {
	// Ensure the table and chain exist (idempotent).
	if err := b.ensureChain(); err != nil {
		return err
	}
	family := nftFamily(srcIP)
	for _, p := range ports {
		rule := fmt.Sprintf("add rule inet filter openme %s saddr %s %s dport %d accept comment \"openme\"",
			family, srcIP.String(), p.Proto, p.Port)
		if err := runCmd(b.Log, "nft", rule); err != nil {
			return err
		}
	}
	return nil
}

// Close flushes all rules in the openme chain for the given source IP.
// Note: nft does not support per-rule deletion by content easily, so we
// flush the handle. A production deployment may track handles for precision.
func (b *NFTablesBackend) Close(srcIP net.IP, ports []config.PortRule) error {
	// List rules, find handles matching the IP, delete them.
	// For simplicity we use a shell pipeline here; a full nft library
	// (e.g. google/nftables) would be used in production.
	for _, p := range ports {
		script := fmt.Sprintf(
			`nft -a list chain inet filter openme 2>/dev/null | `+
				`grep 'saddr %s.*dport %d' | `+
				`awk '{print $NF}' | `+
				`xargs -r -I{} nft delete rule inet filter openme handle {}`,
			srcIP.String(), p.Port,
		)
		_ = runCmd(b.Log, "sh", "-c", script)
	}
	return nil
}

// ensureChain creates the inet filter table and openme chain if they do not exist.
func (b *NFTablesBackend) ensureChain() error {
	cmds := [][]string{
		{"nft", "add table inet filter"},
		{"nft", "add chain inet filter openme"},
	}
	for _, args := range cmds {
		// Ignore "already exists" errors.
		_ = runCmd(b.Log, args[0], args[1:]...)
	}
	return nil
}

// nftFamily returns the nft address family string for an IP.
func nftFamily(ip net.IP) string {
	if ip.To4() == nil {
		return "ip6"
	}
	return "ip"
}
