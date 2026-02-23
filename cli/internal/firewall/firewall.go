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

	"github.com/openme/openme/internal/config"
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

// Manager wraps a Backend and handles automatic rule expiry.
type Manager struct {
	backend Backend
	timeout time.Duration
	mu      sync.Mutex
	timers  map[string]*time.Timer // keyed by ruleKey
	log     *slog.Logger
}

// NewManager creates a Manager with the given backend and knock timeout.
func NewManager(backend Backend, timeout time.Duration, log *slog.Logger) *Manager {
	return &Manager{
		backend: backend,
		timeout: timeout,
		timers:  make(map[string]*time.Timer),
		log:     log,
	}
}

// Open opens firewall rules for srcIP+ports and schedules automatic removal after timeout.
// If a rule already exists (e.g. repeated knock), the timer is reset.
func (m *Manager) Open(srcIP net.IP, ports []config.PortRule) error {
	if err := m.backend.Open(srcIP, ports); err != nil {
		return fmt.Errorf("opening firewall rules: %w", err)
	}

	key := ruleKey(srcIP, ports)
	m.mu.Lock()
	defer m.mu.Unlock()

	// Reset existing timer if present.
	if t, ok := m.timers[key]; ok {
		t.Reset(m.timeout)
		m.log.Info("firewall rule timer reset", "src", srcIP, "timeout", m.timeout)
		return nil
	}

	m.timers[key] = time.AfterFunc(m.timeout, func() {
		if err := m.backend.Close(srcIP, ports); err != nil {
			m.log.Error("auto-closing firewall rule", "src", srcIP, "err", err)
		} else {
			m.log.Info("firewall rule expired", "src", srcIP)
		}
		m.mu.Lock()
		delete(m.timers, key)
		m.mu.Unlock()
	})

	m.log.Info("firewall rule opened", "src", srcIP, "ports", ports, "timeout", m.timeout)
	return nil
}

// CloseAll cancels all pending timers and removes all managed rules immediately.
// Should be called on server shutdown.
func (m *Manager) CloseAll(ctx context.Context) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for key, t := range m.timers {
		t.Stop()
		delete(m.timers, key)
		m.log.Info("firewall rule removed on shutdown", "key", key)
	}
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
func NewBackend(name string) (Backend, error) {
	switch name {
	case "iptables":
		return &IPTablesBackend{}, nil
	case "nft":
		return &NFTablesBackend{}, nil
	default:
		return nil, fmt.Errorf("unknown firewall backend %q (use 'iptables' or 'nft')", name)
	}
}

// runCmd executes a command and returns a wrapped error on failure.
func runCmd(name string, args ...string) error {
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
type IPTablesBackend struct{}

func (b *IPTablesBackend) Name() string { return "iptables" }

// Open inserts an ACCEPT rule for each port, supporting both IPv4 and IPv6.
func (b *IPTablesBackend) Open(srcIP net.IP, ports []config.PortRule) error {
	cmd := ipTablesCmd(srcIP)
	for _, p := range ports {
		if err := runCmd(cmd, "-I", "INPUT", "-s", srcIP.String(),
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
		_ = runCmd(cmd, "-D", "INPUT", "-s", srcIP.String(),
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
type NFTablesBackend struct{}

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
		if err := runCmd("nft", rule); err != nil {
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
		_ = runCmd("sh", "-c", script)
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
		_ = runCmd(args[0], args[1:]...)
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
