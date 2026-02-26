// Command openme is a Single Packet Authentication (SPA) tool for temporarily
// opening firewall ports using ephemeral ECDH + Ed25519 authenticated knock packets.
//
// Usage:
//
//	openme serve                    # start the server
//	openme connect                  # knock using the default profile
//	openme connect home             # knock using the 'home' profile
//	openme status [profile]         # check if server is reachable
//	openme add <name>               # register a new client on the server
//	openme add <name> --qr          # also display a QR code
//	openme list                     # list all registered clients
//	openme revoke <name>            # revoke a client key
package main

import (
	"context"
	"crypto/ed25519"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/cobra"
	internlcrypto "github.com/openme/openme/internal/crypto"
	"github.com/openme/openme/internal/client"
	"github.com/openme/openme/internal/config"
	"github.com/openme/openme/internal/firewall"
	"github.com/openme/openme/internal/qr"
	"github.com/openme/openme/internal/server"
)

const defaultServerConfigPath = "/etc/openme/config.yaml"

var (
	serverConfigPath string
	clientConfigPath string
	logLevel         string
)

func main() {
	root := &cobra.Command{
		Use:   "openme",
		Short: "Single Packet Authentication firewall knocking tool",
		Long: `openme implements SPA (Single Packet Authentication) using ephemeral
Curve25519 ECDH key exchange, ChaCha20-Poly1305 encryption and Ed25519 signatures
to securely and stealthily open firewall ports.`,
	}

	root.PersistentFlags().StringVar(&serverConfigPath, "config", defaultServerConfigPath, "server config file path")
	root.PersistentFlags().StringVar(&clientConfigPath, "client-config", config.DefaultClientConfigPath(), "client config file path")
	root.PersistentFlags().StringVar(&logLevel, "log-level", "info", "log level (debug, info, warn, error)")

	root.AddCommand(
		newInitCmd(),
		newServeCmd(),
		newConnectCmd(),
		newStatusCmd(),
		newAddCmd(),
		newListCmd(),
		newRevokeCmd(),
	)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

// newLogger creates a slog.Logger at the configured level.
func newLogger() *slog.Logger {
	var level slog.Level
	switch logLevel {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))
}

// ────────────────────────────────────────────────────────────────────────────
// openme serve
// ────────────────────────────────────────────────────────────────────────────

// ────────────────────────────────────────────────────────────────────────────
// openme init
// ────────────────────────────────────────────────────────────────────────────

// newInitCmd creates the `openme init` command.
func newInitCmd() *cobra.Command {
	var (
		force          bool
		serverHost     string
		udpPort        uint16
		firewallBackend string
	)

	cmd := &cobra.Command{
		Use:   "init",
		Short: "Initialise a new openme server configuration",
		Long: `Generate a fresh Curve25519 keypair and write a default server config.

By default the config is written to /etc/openme/config.yaml.
Use --config to override the path.

Example:
  sudo openme init --server myserver.example.com
  sudo openme init --server 1.2.3.4 --firewall iptables --port 9999`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runInit(force, serverHost, udpPort, firewallBackend)
		},
	}

	cmd.Flags().BoolVar(&force, "force", false, "overwrite existing config without prompting")
	cmd.Flags().StringVar(&serverHost, "server", "", "public hostname or IP of this server (required)")
	cmd.Flags().Uint16Var(&udpPort, "port", 7777, "UDP (and TCP health) port")
	cmd.Flags().StringVar(&firewallBackend, "firewall", "nft", "firewall backend: nft or iptables")
	_ = cmd.MarkFlagRequired("server")

	return cmd
}

// runInit generates a new server config with fresh cryptographic keys.
// It refuses to overwrite an existing config unless --force is given.
func runInit(force bool, serverHost string, udpPort uint16, firewallBackend string) error {
	// Validate firewall backend early so we fail before writing anything.
	if _, err := firewall.NewBackend(firewallBackend, slog.Default()); err != nil {
		return err
	}

	// Refuse to clobber an existing config unless explicitly asked.
	if _, err := os.Stat(serverConfigPath); err == nil && !force {
		return fmt.Errorf(
			"config already exists at %s\nUse --force to overwrite, or 'openme add' to register new clients",
			serverConfigPath,
		)
	}

	// Generate a fresh Curve25519 keypair for the server.
	kp, err := internlcrypto.GenerateCurve25519KeyPair()
	if err != nil {
		return fmt.Errorf("generating server keypair: %w", err)
	}

	cfg := config.DefaultServerConfig()
	cfg.Server.UDPPort = udpPort
	cfg.Server.HealthPort = udpPort
	cfg.Server.Firewall = firewallBackend
	cfg.Server.PrivateKey = internlcrypto.EncodeKey(kp.PrivateKey[:])
	cfg.Server.PublicKey = internlcrypto.EncodeKey(kp.PublicKey[:])
	cfg.Defaults.Server = serverHost

	if err := config.SaveServerConfig(serverConfigPath, cfg); err != nil {
		return fmt.Errorf("writing server config: %w", err)
	}

	fmt.Printf(`openme server initialised successfully!

  Config:    %s
  Server:    %s
  UDP port:  %d
  Firewall:  %s

  Public key (share with clients):
    %s

Next steps:
  1. Register your first client:
       sudo openme add <name>

  2. Start the server:
       sudo openme serve

  3. (Optional) Install as a systemd service:
       sudo systemctl enable --now openme

`, serverConfigPath, serverHost, udpPort, firewallBackend, cfg.Server.PublicKey)

	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// openme serve
// ────────────────────────────────────────────────────────────────────────────

func newServeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "serve",
		Short: "Start the openme SPA server",
		RunE:  runServe,
	}
}

func runServe(cmd *cobra.Command, args []string) error {
	log := newLogger()

	cfg, err := config.LoadServerConfig(serverConfigPath)
	if err != nil {
		return fmt.Errorf("loading server config: %w", err)
	}

	privKeyBytes, err := internlcrypto.DecodeKey(cfg.Server.PrivateKey)
	if err != nil {
		return fmt.Errorf("decoding server private key: %w", err)
	}
	var privKey [internlcrypto.Curve25519KeySize]byte
	copy(privKey[:], privKeyBytes)

	// Build client records from config.
	clients, err := buildClientRecords(cfg)
	if err != nil {
		return err
	}

	// Set up firewall manager.
	fw, err := firewall.NewBackend(cfg.Server.Firewall, log)
	if err != nil {
		return err
	}
	fwMgr := firewall.NewManager(fw, cfg.Server.KnockTimeout.Duration, log)

	srv := server.New(&server.Options{
		UDPPort:      cfg.Server.UDPPort,
		HealthPort:   cfg.Server.HealthPort,
		ServerPrivKey: privKey,
		ReplayWindow: cfg.Server.ReplayWindow.Duration,
		Clients:      clients,
		Log:          log,
		OnKnock: func(clientName string, srcIP, targetIP net.IP, ports []server.PortRule) {
			log.Info("firewall: IP added", "client", clientName, "ip", targetIP)
			cfgPorts := make([]config.PortRule, len(ports))
			for i, p := range ports {
				cfgPorts[i] = config.PortRule{Port: p.Port, Proto: p.Proto}
			}
			if err := fwMgr.Open(targetIP, cfgPorts); err != nil {
				log.Error("opening firewall", "err", err)
			}
		},
	})

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := srv.Run(ctx); err != nil {
		return fmt.Errorf("server error: %w", err)
	}
	fwMgr.CloseAll(context.Background())
	return nil
}

// buildClientRecords converts config.ClientEntry map into server.ClientRecord slice.
// The health port (TCP) is automatically prepended to every client's port list
// unless the client has DisableHealthPort set to true. This ensures openme status
// works after a successful knock without any special-casing in the server.
func buildClientRecords(cfg *config.ServerConfig) ([]*server.ClientRecord, error) {
	var records []*server.ClientRecord
	for name, entry := range cfg.Clients {
		pubKeyBytes, err := internlcrypto.DecodeKey(entry.Ed25519PubKey)
		if err != nil {
			return nil, fmt.Errorf("client %q: decoding ed25519 pubkey: %w", name, err)
		}
		ports := config.EffectivePorts(cfg.Defaults.Ports, entry)
		srvPorts := make([]server.PortRule, 0, len(ports)+1)

		// Prepend the health port so it opens alongside the client's other ports.
		// This is the only way the health port becomes reachable — it is never
		// permanently open on the server.
		if !entry.DisableHealthPort {
			srvPorts = append(srvPorts, server.PortRule{
				Port:  cfg.Server.HealthPort,
				Proto: "tcp",
			})
		}

		for _, p := range ports {
			srvPorts = append(srvPorts, server.PortRule{Port: p.Port, Proto: p.Proto})
		}
		records = append(records, &server.ClientRecord{
			Name:          name,
			Ed25519PubKey: ed25519.PublicKey(pubKeyBytes),
			Ports:         srvPorts,
			Expires:       entry.Expires,
		})
	}
	return records, nil
}

// ────────────────────────────────────────────────────────────────────────────
// openme connect [profile]
// ────────────────────────────────────────────────────────────────────────────

func newConnectCmd() *cobra.Command {
	var targetIP string

	cmd := &cobra.Command{
		Use:   "connect [profile]",
		Short: "Send a knock packet to open a firewall port",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			profileName := ""
			if len(args) > 0 {
				profileName = args[0]
			}
			return runConnect(profileName, targetIP)
		},
	}
	cmd.Flags().StringVar(&targetIP, "ip", "0.0.0.0", "target IP to open the firewall for (0.0.0.0 = source IP)")
	return cmd
}

func runConnect(profileName, targetIPStr string) error {
	cfg, err := config.LoadClientConfig(clientConfigPath)
	if err != nil {
		return fmt.Errorf("loading client config: %w", err)
	}

	profile, err := config.GetProfile(cfg, profileName)
	if err != nil {
		return err
	}

	serverPubBytes, err := internlcrypto.DecodeKey(profile.ServerPubKey)
	if err != nil {
		return fmt.Errorf("decoding server pubkey: %w", err)
	}
	var serverPub [internlcrypto.Curve25519KeySize]byte
	copy(serverPub[:], serverPubBytes)

	privKeyBytes, err := internlcrypto.DecodeKey(profile.PrivateKey)
	if err != nil {
		return fmt.Errorf("decoding client private key: %w", err)
	}

	targetIP := net.ParseIP(targetIPStr)

	opts := &client.KnockOptions{
		ServerHost:             profile.ServerHost,
		ServerUDPPort:          profile.ServerUDPPort,
		ServerCurve25519PubKey: serverPub,
		ClientEd25519PrivKey:   ed25519.PrivateKey(privKeyBytes),
		TargetIP:               targetIP,
	}

	fmt.Printf("Knocking %s:%d ...\n", profile.ServerHost, profile.ServerUDPPort)
	if err := client.Knock(opts); err != nil {
		return fmt.Errorf("knock failed: %w", err)
	}
	fmt.Println("Knock sent.")

	if profile.PostKnock != "" {
		fmt.Printf("Running post-knock: %s\n", profile.PostKnock)
		c := exec.Command("sh", "-c", profile.PostKnock)
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		c.Stdin = os.Stdin
		return c.Run()
	}
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// openme status [profile]
// ────────────────────────────────────────────────────────────────────────────

func newStatusCmd() *cobra.Command {
	var knockFirst bool

	cmd := &cobra.Command{
		Use:   "status [profile]",
		Short: "Check if the health port is open (requires prior authentication)",
		Long: `Check reachability of the server's TCP health port.

The health port is only open after a successful knock — it is never permanently
accessible. Running openme status without --knock requires you to have already
knocked (within the knock_timeout window).

Use --knock to perform a knock first, then check the health port. This
validates the full authentication round trip end-to-end.`,
		Args: cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			profileName := ""
			if len(args) > 0 {
				profileName = args[0]
			}
			return runStatus(profileName, knockFirst)
		},
	}
	cmd.Flags().BoolVar(&knockFirst, "knock", false, "knock first, then check the health port")
	return cmd
}

// runStatus checks whether the server's TCP health port is reachable.
// If knockFirst is true it sends a knock packet first and waits briefly before
// checking, validating the full authentication round trip end-to-end.
func runStatus(profileName string, knockFirst bool) error {
	cfg, err := config.LoadClientConfig(clientConfigPath)
	if err != nil {
		return err
	}
	profile, err := config.GetProfile(cfg, profileName)
	if err != nil {
		return err
	}

	if knockFirst {
		fmt.Println("Knocking first...")
		if err := runConnect(profileName, "0.0.0.0"); err != nil {
			return fmt.Errorf("knock failed: %w", err)
		}
		// Give the firewall manager time to apply the rule before checking.
		fmt.Println("Waiting for firewall rule to propagate...")
		time.Sleep(500 * time.Millisecond)
	}

	fmt.Printf("Checking health port %s:%d (TCP)...\n", profile.ServerHost, profile.ServerUDPPort)
	if client.HealthCheck(profile.ServerHost, profile.ServerUDPPort, 3*time.Second) {
		fmt.Println("✓ Health port is open — authentication succeeded.")
		return nil
	}

	if knockFirst {
		fmt.Println("✗ Health port is still closed after knocking.")
		fmt.Println("  Check server logs and firewall configuration.")
	} else {
		fmt.Println("✗ Health port is closed.")
		fmt.Println("  The health port is only open after a successful knock.")
		fmt.Println("  Try: openme status --knock")
	}
	return fmt.Errorf("health port unreachable")
}

// ────────────────────────────────────────────────────────────────────────────
// openme add <name>
// ────────────────────────────────────────────────────────────────────────────

func newAddCmd() *cobra.Command {
	var (
		showQR         bool
		qrOutputPath   string
		omitPrivateKey bool
		expires        string
		portMode       string
		extraPorts     []string
	)

	cmd := &cobra.Command{
		Use:   "add <name>",
		Short: "Register a new client and generate their config",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runAdd(args[0], showQR, qrOutputPath, omitPrivateKey, expires, portMode, extraPorts)
		},
	}

	cmd.Flags().BoolVar(&showQR, "qr", false, "display QR code in terminal")
	cmd.Flags().StringVar(&qrOutputPath, "qr-out", "", "write QR PNG to this file path")
	cmd.Flags().BoolVar(&omitPrivateKey, "no-privkey", false, "omit private key from QR (mobile generates its own)")
	cmd.Flags().StringVar(&expires, "expires", "", "key expiry date (RFC3339, e.g. 2027-01-01T00:00:00Z)")
	cmd.Flags().StringVar(&portMode, "port-mode", "default", "port mode: default | only | default_plus")
	cmd.Flags().StringArrayVar(&extraPorts, "port", nil, "extra port rules, e.g. 2222/tcp (used with default_plus or only)")

	return cmd
}

func runAdd(name string, showQR bool, qrOut string, omitPriv bool, expires, portMode string, extraPortStrs []string) error {
	cfg, err := config.LoadServerConfig(serverConfigPath)
	if err != nil {
		return fmt.Errorf("loading server config: %w", err)
	}

	if _, exists := cfg.Clients[name]; exists {
		return fmt.Errorf("client %q already exists; use 'openme revoke %s' first", name, name)
	}

	// Generate Ed25519 keypair for the new client.
	kp, err := internlcrypto.GenerateEd25519KeyPair()
	if err != nil {
		return fmt.Errorf("generating client keypair: %w", err)
	}

	entry := &config.ClientEntry{
		Ed25519PubKey: internlcrypto.EncodeKey(kp.PublicKey),
		AllowedPorts: config.AllowedPorts{
			Mode: config.AllowedPortsMode(portMode),
		},
	}

	// Parse extra port rules.
	for _, ps := range extraPortStrs {
		var port uint16
		var proto string
		if _, err := fmt.Sscanf(ps, "%d/%s", &port, &proto); err != nil {
			return fmt.Errorf("invalid port rule %q (expected e.g. 2222/tcp): %w", ps, err)
		}
		entry.AllowedPorts.Ports = append(entry.AllowedPorts.Ports, config.PortRule{Port: port, Proto: proto})
	}

	// Parse optional expiry.
	if expires != "" {
		t, err := time.Parse(time.RFC3339, expires)
		if err != nil {
			return fmt.Errorf("invalid expires date %q (use RFC3339): %w", expires, err)
		}
		entry.Expires = &t
	}

	cfg.Clients[name] = entry

	if err := config.SaveServerConfig(serverConfigPath, cfg); err != nil {
		return fmt.Errorf("saving server config: %w", err)
	}
	fmt.Printf("Client %q added to server config.\n\n", name)

	// Build and print client config.
	clientCfg := &config.ClientConfig{
		Profiles: map[string]*config.Profile{
			name: {
				ServerHost:    cfg.Defaults.Server,
				ServerUDPPort: cfg.Server.UDPPort,
				ServerPubKey:  cfg.Server.PublicKey,
				PrivateKey:    internlcrypto.EncodeKey(kp.PrivateKey),
				PublicKey:     internlcrypto.EncodeKey(kp.PublicKey),
			},
		},
	}

	clientYAML, err := marshalYAML(clientCfg)
	if err != nil {
		return err
	}
	fmt.Printf("──── Client config for %s (copy to ~/.openme/config.yaml) ────\n", name)
	fmt.Println(clientYAML)
	fmt.Println("────────────────────────────────────────────────────────────────")
	fmt.Printf("Key fingerprint: %s\n", internlcrypto.FingerprintKey(kp.PublicKey))

	// QR code.
	if showQR || qrOut != "" {
		payload := &qr.Payload{
			ProfileName:   name,
			ServerHost:    cfg.Defaults.Server,
			ServerUDPPort: cfg.Server.UDPPort,
			ServerPubKey:  cfg.Server.PublicKey,
			ClientPrivKey: internlcrypto.EncodeKey(kp.PrivateKey),
			ClientPubKey:  internlcrypto.EncodeKey(kp.PublicKey),
		}
		if omitPriv {
			fmt.Println("\n⚠ QR does not include private key. The mobile app must generate its own keypair")
			fmt.Printf("  and you must run: openme add %s-mobile (with the mobile's public key)\n\n", name)
		} else {
			fmt.Println("\n⚠ WARNING: QR contains the client private key. Treat it as a secret!")
		}
		if err := qr.Generate(payload, &qr.GenerateOptions{
			OmitPrivateKey: omitPriv,
			OutputPath:     qrOut,
		}); err != nil {
			return fmt.Errorf("generating QR: %w", err)
		}
	}
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// openme list
// ────────────────────────────────────────────────────────────────────────────

func newListCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List all registered clients",
		RunE:  runList,
	}
}

func runList(cmd *cobra.Command, args []string) error {
	cfg, err := config.LoadServerConfig(serverConfigPath)
	if err != nil {
		return err
	}
	if len(cfg.Clients) == 0 {
		fmt.Println("No clients registered.")
		return nil
	}
	fmt.Printf("%-20s %-18s %-12s %s\n", "NAME", "FINGERPRINT", "PORT MODE", "EXPIRES")
	fmt.Println("─────────────────────────────────────────────────────────────")
	for name, entry := range cfg.Clients {
		fp := "invalid"
		if b, err := internlcrypto.DecodeKey(entry.Ed25519PubKey); err == nil {
			fp = internlcrypto.FingerprintKey(b)
		}
		exp := "never"
		if entry.Expires != nil {
			exp = entry.Expires.Format("2006-01-02")
		}
		fmt.Printf("%-20s %-18s %-12s %s\n", name, fp, entry.AllowedPorts.Mode, exp)
	}
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// openme revoke <name>
// ────────────────────────────────────────────────────────────────────────────

func newRevokeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "revoke <name>",
		Short: "Revoke a client's key (removes it from the server config)",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runRevoke(args[0])
		},
	}
}

func runRevoke(name string) error {
	cfg, err := config.LoadServerConfig(serverConfigPath)
	if err != nil {
		return err
	}
	if _, ok := cfg.Clients[name]; !ok {
		return fmt.Errorf("client %q not found", name)
	}
	delete(cfg.Clients, name)
	if err := config.SaveServerConfig(serverConfigPath, cfg); err != nil {
		return err
	}
	fmt.Printf("Client %q revoked. Changes take effect immediately on next knock attempt.\n", name)
	return nil
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

// marshalYAML marshals v to a YAML string using the config package's yaml.Marshal.
func marshalYAML(v any) (string, error) {
	// We import yaml indirectly; use config's save path for simplicity.
	// For display purposes write to a temp file and read it back.
	f, err := os.CreateTemp("", "openme-*.yaml")
	if err != nil {
		return "", err
	}
	defer os.Remove(f.Name())
	f.Close()

	if err := config.SaveClientConfig(f.Name(), v.(*config.ClientConfig)); err != nil {
		return "", err
	}
	b, err := os.ReadFile(f.Name())
	return string(b), err
}
