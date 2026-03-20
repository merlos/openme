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
	// Setup installs any infrastructure rules required by the backend.
	// Should be called once when the server starts, before the first Open.
	// When openKnockPort is true the backend also inserts a rule that accepts
	// UDP traffic on udpPort so knock packets can reach the server.
	// Set openKnockPort to false when the host firewall already opens that port.
	Setup(udpPort uint16, openKnockPort bool) error

	// Teardown removes the infrastructure rules installed by Setup.
	// Should be called once when the server stops, after CloseAll.
	Teardown(udpPort uint16) error

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
	// Do NOT call backend.Open again — the rule is already in place.
	if sess, ok := m.sessions[key]; ok {
		sess.entry.ExpiresAt = expiresAt
		sess.entry.OpenedAt = now
		sess.timer.Reset(m.timeout)
		m.log.Debug("firewall rule timer reset", "ip", srcIP, "timeout", m.timeout)
		m.log.Info("firewall rule refreshed", "client", clientName, "ip", srcIP, "timeout", m.timeout)
		m.persistState()
		return nil
	}

	if err := m.backend.Open(srcIP, ports); err != nil {
		return fmt.Errorf("opening firewall rules: %w", err)
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

// Setup creates the openme chain in both iptables and ip6tables and jumps from
// INPUT into it. When openKnockPort is true it also inserts a rule that accepts
// UDP traffic on udpPort so knock packets can reach the server.
//
// A best-effort Teardown is run first so a server restart after a crash does
// not leave duplicate rules.
//
// See https://openme.merlos.org/docs/configuration/server.html
func (b *IPTablesBackend) Setup(udpPort uint16, openKnockPort bool) error {
	// Best-effort cleanup of any rules left by a previous run.
	_ = b.Teardown(udpPort)

	port := fmt.Sprint(udpPort)
	for _, cmd := range []string{"iptables", "ip6tables"} {
		// Create the openme chain (ignore error if it already exists).
		_ = runCmd(b.Log, cmd, "-N", "openme")

		// Optionally accept knock packets on the SPA UDP port.
		if openKnockPort {
			if err := runCmd(b.Log, cmd, "-I", "INPUT",
				"-p", "udp", "--dport", port, "-j", "ACCEPT",
				"-m", "comment", "--comment", "openme-knock"); err != nil {
				return fmt.Errorf("iptables setup (%s): adding knock accept rule: %w", cmd, err)
			}
		}

		// Jump from INPUT into the openme chain.
		if err := runCmd(b.Log, cmd, "-A", "INPUT", "-j", "openme",
			"-m", "comment", "--comment", "openme-jump"); err != nil {
			return fmt.Errorf("iptables setup (%s): adding jump rule: %w", cmd, err)
		}
	}
	b.Log.Info("iptables infrastructure rules installed",
		"udp_port", udpPort, "open_knock_port", openKnockPort)
	return nil
}

// Teardown removes the jump and knock-accept rules from INPUT and deletes the
// openme chain from both iptables and ip6tables. All operations are
// best-effort so Teardown is safe to call even when no rules exist.
//
// See https://openme.merlos.org/docs/configuration/server.html
func (b *IPTablesBackend) Teardown(udpPort uint16) error {
	port := fmt.Sprint(udpPort)
	for _, cmd := range []string{"iptables", "ip6tables"} {
		_ = runCmd(b.Log, cmd, "-D", "INPUT", "-j", "openme",
			"-m", "comment", "--comment", "openme-jump")
		_ = runCmd(b.Log, cmd, "-D", "INPUT",
			"-p", "udp", "--dport", port, "-j", "ACCEPT",
			"-m", "comment", "--comment", "openme-knock")
		_ = runCmd(b.Log, cmd, "-F", "openme")
		_ = runCmd(b.Log, cmd, "-X", "openme")
	}
	b.Log.Info("iptables infrastructure rules removed")
	return nil
}

// Open inserts an ACCEPT rule for each port into the openme chain.
func (b *IPTablesBackend) Open(srcIP net.IP, ports []config.PortRule) error {
	cmd := ipTablesCmd(srcIP)
	for _, p := range ports {
		if err := runCmd(b.Log, cmd, "-A", "openme", "-s", srcIP.String(),
			"-p", p.Proto, "--dport", fmt.Sprint(p.Port), "-j", "ACCEPT",
			"-m", "comment", "--comment", "openme"); err != nil {
			return err
		}
	}
	return nil
}

// Close deletes the ACCEPT rules previously inserted by Open from the openme chain.
func (b *IPTablesBackend) Close(srcIP net.IP, ports []config.PortRule) error {
	cmd := ipTablesCmd(srcIP)
	for _, p := range ports {
		// Best-effort: ignore errors (rule may already be gone).
		_ = runCmd(b.Log, cmd, "-D", "openme", "-s", srcIP.String(),
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

// Setup creates the "openme" chain inside the inet filter table and adds a jump
// from the input chain into it. When openKnockPort is true it also inserts a
// rule that accepts UDP traffic on udpPort so knock packets can reach the server.
//
// A best-effort Teardown is run first so a server restart after a crash does
// not leave duplicate rules.
//
// See https://openme.merlos.org/docs/configuration/server.html
func (b *NFTablesBackend) Setup(udpPort uint16, openKnockPort bool) error {
	// Best-effort cleanup of any rules left by a previous run.
	_ = b.Teardown(udpPort)

	// Ensure the base table and openme chain exist.
	if err := b.ensureChain(); err != nil {
		return err
	}

	// Optionally allow knock packets to reach the server's UDP listener.
	if openKnockPort {
		if err := runCmd(b.Log, "nft",
			"add", "rule", "inet", "filter", "input",
			"udp", "dport", fmt.Sprint(udpPort), "accept",
			"comment", "openme-knock"); err != nil {
			return fmt.Errorf("nft setup: adding knock accept rule: %w", err)
		}
	}

	// Route INPUT traffic through the per-client openme chain.
	if err := runCmd(b.Log, "nft",
		"add", "rule", "inet", "filter", "input",
		"jump", "openme",
		"comment", "openme-jump"); err != nil {
		return fmt.Errorf("nft setup: adding jump rule: %w", err)
	}

	b.Log.Info("nft infrastructure rules installed",
		"udp_port", udpPort, "open_knock_port", openKnockPort)
	return nil
}

// Teardown removes the infrastructure rules added by Setup and cleans up the
// openme chain. All operations are best-effort; errors are ignored so that
// Teardown is safe to call even when no rules exist.
//
// See https://openme.merlos.org/docs/configuration/server.html
func (b *NFTablesBackend) Teardown(_ uint16) error {
	for _, comment := range []string{"openme-jump", "openme-knock"} {
		script := fmt.Sprintf(
			`nft -a list chain inet filter input 2>/dev/null | `+
				`grep 'comment "%s"' | `+
				`awk '{print $NF}' | `+
				`xargs -r -I{} nft delete rule inet filter input handle {}`,
			comment,
		)
		_ = runCmd(b.Log, "sh", "-c", script)
	}
	// Flush any remaining per-client rules and remove the chain.
	_ = runCmd(b.Log, "nft", "flush", "chain", "inet", "filter", "openme")
	_ = runCmd(b.Log, "nft", "delete", "chain", "inet", "filter", "openme")
	b.Log.Info("nft infrastructure rules removed")
	return nil
}

// Open adds nft accept rules for each port. Creates the chain on first use.
func (b *NFTablesBackend) Open(srcIP net.IP, ports []config.PortRule) error {
	// Ensure the table and chain exist (idempotent).
	if err := b.ensureChain(); err != nil {
		return err
	}
	family := nftFamily(srcIP)
	for _, p := range ports {
		// Each word must be a separate argument — exec.Command does not use a shell
		// and will not split a single string on spaces.
		if err := runCmd(b.Log, "nft",
			"add", "rule", "inet", "filter", "openme",
			family, "saddr", srcIP.String(),
			p.Proto, "dport", fmt.Sprint(p.Port),
			"accept", "comment", "openme"); err != nil {
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
	// Each word must be a separate argument — exec.Command does not use a shell.
	cmds := [][]string{
		{"add", "table", "inet", "filter"},
		{"add", "chain", "inet", "filter", "openme"},
	}
	for _, args := range cmds {
		// Ignore "already exists" errors.
		_ = runCmd(b.Log, "nft", args...)
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
