package firewall_test

import (
	"context"
	"log/slog"
	"net"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/merlos/openme/cli/internal/config"
	"github.com/merlos/openme/cli/internal/firewall"
)

// mockBackend records Open/Close/SetupDropRules/TeardownDropRules calls for test assertions.
type mockBackend struct {
	mu                 sync.Mutex
	opened             []string
	closed             []string
	setupDropCalled    bool
	teardownDropCalled bool
	dropPorts          []config.PortRule
}

func (m *mockBackend) Name() string { return "mock" }

func (m *mockBackend) Setup(_ uint16, _ bool) error { return nil }
func (m *mockBackend) Teardown(_ uint16) error      { return nil }

func (m *mockBackend) SetupDropRules(ports []config.PortRule) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.setupDropCalled = true
	m.dropPorts = append(m.dropPorts, ports...)
	return nil
}

func (m *mockBackend) TeardownDropRules(_ []config.PortRule) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.teardownDropCalled = true
	return nil
}

func (m *mockBackend) Open(srcIP net.IP, ports []config.PortRule) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.opened = append(m.opened, srcIP.String())
	return nil
}

func (m *mockBackend) Close(srcIP net.IP, ports []config.PortRule) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.closed = append(m.closed, srcIP.String())
	return nil
}

func newTestManager(backend firewall.Backend, timeout time.Duration) *firewall.Manager {
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError}))
	// Pass empty stateFile to disable persistence in tests.
	return firewall.NewManager(backend, timeout, "", log)
}

func TestManager_OpenCallsBackend(t *testing.T) {
	mock := &mockBackend{}
	mgr := newTestManager(mock, time.Minute)

	ip := net.ParseIP("192.168.1.1")
	ports := []config.PortRule{{Port: 22, Proto: "tcp"}}

	if err := mgr.Open("test-client", ip, ports); err != nil {
		t.Fatalf("Open error = %v", err)
	}

	mock.mu.Lock()
	defer mock.mu.Unlock()
	if len(mock.opened) != 1 || mock.opened[0] != "192.168.1.1" {
		t.Errorf("backend opened = %v, want [192.168.1.1]", mock.opened)
	}
}

func TestManager_AutoExpiry(t *testing.T) {
	mock := &mockBackend{}
	timeout := 50 * time.Millisecond
	mgr := newTestManager(mock, timeout)

	ip := net.ParseIP("10.0.0.1")
	ports := []config.PortRule{{Port: 22, Proto: "tcp"}}

	if err := mgr.Open("test-client", ip, ports); err != nil {
		t.Fatal(err)
	}

	// Wait for the timer to fire.
	time.Sleep(timeout + 100*time.Millisecond)

	mock.mu.Lock()
	defer mock.mu.Unlock()
	if len(mock.closed) != 1 {
		t.Errorf("auto-close: backend.Close called %d times, want 1", len(mock.closed))
	}
}

func TestManager_CloseAll(t *testing.T) {
	mock := &mockBackend{}
	mgr := newTestManager(mock, time.Minute)

	ips := []string{"10.0.0.1", "10.0.0.2"}
	ports := []config.PortRule{{Port: 22, Proto: "tcp"}}

	for _, ip := range ips {
		if err := mgr.Open("test-client", net.ParseIP(ip), ports); err != nil {
			t.Fatal(err)
		}
	}

	mgr.CloseAll(context.Background())
	// Timers should be cancelled; backend.Close is not called by CloseAll itself,
	// but timers are stopped. Verify no panics or hangs.
}

func TestNewBackend_Invalid(t *testing.T) {
	if _, err := firewall.NewBackend("unknown", slog.Default(), ""); err == nil {
		t.Error("NewBackend with unknown name should return error")
	}
}

func TestNewBackend_Valid(t *testing.T) {
	for _, name := range []string{"iptables", "nft"} {
		if _, err := firewall.NewBackend(name, slog.Default(), ""); err != nil {
			t.Errorf("NewBackend(%q) error = %v", name, err)
		}
	}
}

func TestMockBackend_SetupDropRules(t *testing.T) {
	mock := &mockBackend{}
	ports := []config.PortRule{
		{Port: 22, Proto: "tcp"},
		{Port: 443, Proto: "tcp"},
	}
	if err := mock.SetupDropRules(ports); err != nil {
		t.Fatalf("SetupDropRules error = %v", err)
	}

	mock.mu.Lock()
	defer mock.mu.Unlock()
	if !mock.setupDropCalled {
		t.Error("SetupDropRules was not called")
	}
	if len(mock.dropPorts) != 2 {
		t.Errorf("dropPorts = %v, want 2 entries", mock.dropPorts)
	}
}

func TestMockBackend_TeardownDropRules(t *testing.T) {
	mock := &mockBackend{}
	if err := mock.TeardownDropRules(nil); err != nil {
		t.Fatalf("TeardownDropRules error = %v", err)
	}

	mock.mu.Lock()
	defer mock.mu.Unlock()
	if !mock.teardownDropCalled {
		t.Error("TeardownDropRules was not called")
	}
}

func TestMockBackend_DropRulesIndependentOfOpenClose(t *testing.T) {
	// Verifies that DROP rule calls do not affect Open/Close tracking.
	mock := &mockBackend{}
	ports := []config.PortRule{{Port: 80, Proto: "tcp"}}

	_ = mock.SetupDropRules(ports)
	_ = mock.Open(net.ParseIP("1.2.3.4"), ports)
	_ = mock.TeardownDropRules(ports)

	mock.mu.Lock()
	defer mock.mu.Unlock()
	if len(mock.opened) != 1 {
		t.Errorf("opened = %v, want 1 entry", mock.opened)
	}
	if len(mock.closed) != 0 {
		t.Errorf("closed = %v, want 0 entries", mock.closed)
	}
	if !mock.setupDropCalled || !mock.teardownDropCalled {
		t.Error("expected both SetupDropRules and TeardownDropRules to be called")
	}
}

// ────────────────────────────────────────────────────────────────────────────
// Interface field tests
// ────────────────────────────────────────────────────────────────────────────

// TestNewBackend_InterfaceStoredOnNFT verifies that NewBackend stores the
// requested interface name on the returned NFTablesBackend concrete type.
func TestNewBackend_InterfaceStoredOnNFT(t *testing.T) {
	b, err := firewall.NewBackend("nft", slog.Default(), "eth0")
	if err != nil {
		t.Fatalf("NewBackend error = %v", err)
	}
	nftB, ok := b.(*firewall.NFTablesBackend)
	if !ok {
		t.Fatalf("expected *firewall.NFTablesBackend, got %T", b)
	}
	if nftB.Interface != "eth0" {
		t.Errorf("NFTablesBackend.Interface = %q, want eth0", nftB.Interface)
	}
}

// TestNewBackend_InterfaceStoredOnIPTables verifies that NewBackend stores the
// requested interface name on the returned IPTablesBackend concrete type.
func TestNewBackend_InterfaceStoredOnIPTables(t *testing.T) {
	b, err := firewall.NewBackend("iptables", slog.Default(), "eth0")
	if err != nil {
		t.Fatalf("NewBackend error = %v", err)
	}
	iptB, ok := b.(*firewall.IPTablesBackend)
	if !ok {
		t.Fatalf("expected *firewall.IPTablesBackend, got %T", b)
	}
	if iptB.Interface != "eth0" {
		t.Errorf("IPTablesBackend.Interface = %q, want eth0", iptB.Interface)
	}
}

// TestNewBackend_EmptyInterfaceMeansAllInterfaces verifies that an empty
// interface string is stored as-is (signifying all interfaces).
func TestNewBackend_EmptyInterfaceMeansAllInterfaces(t *testing.T) {
	b, err := firewall.NewBackend("nft", slog.Default(), "")
	if err != nil {
		t.Fatalf("NewBackend error = %v", err)
	}
	nftB, ok := b.(*firewall.NFTablesBackend)
	if !ok {
		t.Fatalf("expected *firewall.NFTablesBackend, got %T", b)
	}
	if nftB.Interface != "" {
		t.Errorf("NFTablesBackend.Interface = %q, want empty (all interfaces)", nftB.Interface)
	}
}

// TestIPTablesBackend_InterfaceField verifies the IPTablesBackend Interface
// field can be set directly and is read back correctly.
func TestIPTablesBackend_InterfaceField(t *testing.T) {
	b := &firewall.IPTablesBackend{
		Log:       slog.Default(),
		Interface: "wlan0",
	}
	if b.Interface != "wlan0" {
		t.Errorf("Interface = %q, want wlan0", b.Interface)
	}
}

// TestNFTablesBackend_InterfaceField verifies the NFTablesBackend Interface
// field can be set directly and is read back correctly.
func TestNFTablesBackend_InterfaceField(t *testing.T) {
	b := &firewall.NFTablesBackend{
		Log:       slog.Default(),
		Interface: "wlan0",
	}
	if b.Interface != "wlan0" {
		t.Errorf("Interface = %q, want wlan0", b.Interface)
	}
}
