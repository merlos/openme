package main

// Tests for withHelpHint and the SilenceUsage / error-hint wiring on cobra
// subcommands.

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/cobra"
)

// ─── withHelpHint unit tests ──────────────────────────────────────────────────

func TestWithHelpHint_PropagatesNil(t *testing.T) {
	cmd := &cobra.Command{Use: "dummy"}
	wrapped := withHelpHint(func(_ *cobra.Command, _ []string) error {
		return nil
	})
	if err := wrapped(cmd, nil); err != nil {
		t.Errorf("expected nil, got %v", err)
	}
}

func TestWithHelpHint_AppendsHint(t *testing.T) {
	cmd := &cobra.Command{Use: "mycommand"}
	wrapped := withHelpHint(func(_ *cobra.Command, _ []string) error {
		return errors.New("something went wrong")
	})
	err := wrapped(cmd, nil)
	if err == nil {
		t.Fatal("expected non-nil error")
	}
	msg := err.Error()
	if !strings.Contains(msg, "something went wrong") {
		t.Errorf("original error missing from %q", msg)
	}
	if !strings.Contains(msg, "For more details run: openme mycommand --help") {
		t.Errorf("help hint missing from %q", msg)
	}
}

func TestWithHelpHint_WrapsOriginalError(t *testing.T) {
	sentinel := errors.New("sentinel")
	cmd := &cobra.Command{Use: "cmd"}
	wrapped := withHelpHint(func(_ *cobra.Command, _ []string) error {
		return sentinel
	})
	err := wrapped(cmd, nil)
	if !errors.Is(err, sentinel) {
		t.Errorf("errors.Is chain broken; want sentinel in %v", err)
	}
}

func TestWithHelpHint_UsesCommandName(t *testing.T) {
	for _, name := range []string{"init", "add", "serve", "knock"} {
		name := name
		t.Run(name, func(t *testing.T) {
			cmd := &cobra.Command{Use: name}
			wrapped := withHelpHint(func(_ *cobra.Command, _ []string) error {
				return errors.New("fail")
			})
			msg := wrapped(cmd, nil).Error()
			want := "openme " + name + " --help"
			if !strings.Contains(msg, want) {
				t.Errorf("hint %q not found in %q", want, msg)
			}
		})
	}
}

// ─── Cobra command integration tests ─────────────────────────────────────────
// These exercise the full cobra path (cmd.Execute) to verify:
//   1. SilenceUsage prevents the usage block from being printed.
//   2. The --help hint appears in the error message returned by Execute.

// buildRootForTest wires up a minimal root with the subcommand under test,
// executes the given args, and returns the error string (or "").
func buildRootForTest(sub *cobra.Command, args ...string) string {
	root := &cobra.Command{Use: "openme", SilenceErrors: true}
	// Register the same groups as main() so GroupID refs don't panic.
	root.AddGroup(
		&cobra.Group{ID: "server", Title: "Server commands:"},
		&cobra.Group{ID: "client", Title: "Client commands:"},
	)
	root.AddCommand(sub)
	sub.SilenceUsage = true // mirrors what main() does for all subcommands
	root.SetArgs(args)
	err := root.Execute()
	if err == nil {
		return ""
	}
	return err.Error()
}

func TestSilenceUsage_NoUsageOnError(t *testing.T) {
	// A command that always fails should NOT print usage text.
	collect := captureStdout(t)

	sub := &cobra.Command{
		Use:          "fail",
		SilenceUsage: true,
		RunE: withHelpHint(func(_ *cobra.Command, _ []string) error {
			return errors.New("always fails")
		}),
	}
	root := &cobra.Command{Use: "openme", SilenceErrors: true}
	root.AddCommand(sub)
	root.SetArgs([]string{"fail"})
	_ = root.Execute()

	out := collect()
	if strings.Contains(out, "Usage:") {
		t.Errorf("usage block printed despite SilenceUsage=true:\n%s", out)
	}
}

func TestInitCmd_MissingServerFlag(t *testing.T) {
	dir := t.TempDir()

	orig := serverConfigPath
	serverConfigPath = filepath.Join(dir, "config.yaml")
	defer func() { serverConfigPath = orig }()

	msg := buildRootForTest(newInitCmd(), "init")
	if msg == "" {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(msg, "--server is required") {
		t.Errorf("expected '--server is required' in error, got: %s", msg)
	}
	if !strings.Contains(msg, "For more details run: openme init --help") {
		t.Errorf("help hint missing from error: %s", msg)
	}
}

func TestInitCmd_HintPresentOnAnyError(t *testing.T) {
	dir := t.TempDir()

	orig := serverConfigPath
	serverConfigPath = filepath.Join(dir, "config.yaml")
	defer func() { serverConfigPath = orig }()

	// invalid firewall backend → runInit returns error → hint must be appended
	msg := buildRootForTest(newInitCmd(), "init", "--server", "host.example.com", "--firewall", "bogus")
	if msg == "" {
		t.Fatal("expected error for invalid firewall, got nil")
	}
	if !strings.Contains(msg, "For more details run: openme init --help") {
		t.Errorf("help hint missing from firewall error: %s", msg)
	}
}

func TestAddCmd_HintPresentOnMissingConfig(t *testing.T) {
	orig := serverConfigPath
	serverConfigPath = "/nonexistent/path/config.yaml"
	defer func() { serverConfigPath = orig }()

	msg := buildRootForTest(newAddCmd(), "add", "alice")
	if msg == "" {
		t.Fatal("expected error when config is missing")
	}
	if !strings.Contains(msg, "For more details run: openme add --help") {
		t.Errorf("help hint missing: %s", msg)
	}
}
