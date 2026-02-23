package firewall_test

import (
	"context"
	"log/slog"
	"net"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/openme/openme/internal/config"
	"github.com/openme/openme/internal/firewall"
)

// mockBackend records Open/Close calls for test assertions.
type mockBackend struct {
	mu     sync.Mutex
	opened []string
	closed []string
}

func (m *mockBackend) Name() string { return "mock" }

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
	return firewall.NewManager(backend, timeout, log)
}

func TestManager_OpenCallsBackend(t *testing.T) {
	mock := &mockBackend{}
	mgr := newTestManager(mock, time.Minute)

	ip := net.ParseIP("192.168.1.1")
	ports := []config.PortRule{{Port: 22, Proto: "tcp"}}

	if err := mgr.Open(ip, ports); err != nil {
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

	if err := mgr.Open(ip, ports); err != nil {
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
		if err := mgr.Open(net.ParseIP(ip), ports); err != nil {
			t.Fatal(err)
		}
	}

	mgr.CloseAll(context.Background())
	// Timers should be cancelled; backend.Close is not called by CloseAll itself,
	// but timers are stopped. Verify no panics or hangs.
}

func TestNewBackend_Invalid(t *testing.T) {
	if _, err := firewall.NewBackend("unknown"); err == nil {
		t.Error("NewBackend with unknown name should return error")
	}
}

func TestNewBackend_Valid(t *testing.T) {
	for _, name := range []string{"iptables", "nft"} {
		if _, err := firewall.NewBackend(name); err != nil {
			t.Errorf("NewBackend(%q) error = %v", name, err)
		}
	}
}
