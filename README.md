# openme

> Open your firewall with a single encrypted packet. Nothing else is ever visible.

openme is a **Single Packet Authentication (SPA)** tool. To a port scanner, every port is always closed. Only clients holding a valid Ed25519 key can send a knock that temporarily opens a firewall rule — and the knock itself looks like random noise on the wire.

```
Client                              Server (port always CLOSED to scanners)
  │                                     │
  │──── 167 bytes of encrypted UDP ────>│  verify signature
  │                                     │  decrypt payload
  │                                     │  open firewall rule for 30s
  │<══════════ SSH / HTTPS / etc. ══════│
```

---

## Repository Layout

```
openme/
├── cli/          Go server daemon + cross-platform CLI
├── windows/      Windows GUI client          (planned)
├── macos/        macOS menu bar client       (planned)
├── android/      Android app                 (planned)
├── ios/          iOS app                     (planned)
├── docs/         Quarto documentation site
└── website/      Marketing landing page
```

---

## Getting Started with the CLI

### Install

```bash
# Build from source (requires Go 1.21+)
git clone https://github.com/openme/openme
cd openme/cli
go build -o openme ./cmd/openme
sudo mv openme /usr/local/bin/
```

Pre-built binaries for Linux, macOS and Windows are available on the [Releases](https://github.com/openme/openme/releases) page.

### Server setup

```bash
# 1. Initialise — generates keys and writes /etc/openme/config.yaml
sudo openme init --server myserver.example.com

# 2. Register a client
sudo openme add alice

# 3. Start the server
sudo openme serve
```

`openme add alice` prints a ready-to-use client config block and an optional QR code. Copy it to `~/.openme/config.yaml` on the client machine.

### Client usage

```bash
# Check the server is reachable
openme status

# Send a knock (opens firewall for your source IP)
openme connect

# Knock a named profile, then SSH automatically
openme connect home

# Connect to a specific IP instead of your source IP
openme connect --ip 10.0.0.5
```

See [cli/README.md](cli/README.md) for the full CLI reference, configuration options, and cross-compilation instructions.

---

## Documentation

Full documentation lives in [`docs/`](docs/) and is built with [Quarto](https://quarto.org).

| Section | Description |
|---------|-------------|
| [Protocol](docs/protocol/) | Wire format, cryptographic design, security properties |
| [Getting Started](docs/getting-started/) | Step-by-step server and client setup |
| [Configuration](docs/configuration/) | All config options for server and client |
| [Security Model](docs/security/) | Threat model, what is and isn't protected |
| [FAQ](docs/faq/) | Common questions |
| [API Reference](docs/api/) | Auto-generated from Go source via pkgsite |

To build and preview the docs locally:

```bash
cd docs
quarto preview
```

---

## Platform Status

| Platform | Status | Notes |
|----------|--------|-------|
| Linux (CLI + server) | ✅ Active | iptables & nftables |
| macOS (CLI client) | ✅ Active | Cross-compiled from Go |
| Windows (CLI client) | ✅ Active | Cross-compiled from Go |
| Windows GUI | 🔜 Planned | WinUI 3 / C# |
| macOS GUI | 🔜 Planned | SwiftUI menu bar |
| Android | 🔜 Planned | Jetpack Compose |
| iOS | 🔜 Planned | SwiftUI + Secure Enclave |

---

## Contributing

Each platform has its own subdirectory, build toolchain and README. Start with the directory most relevant to what you want to work on. All cryptographic protocol changes should be discussed in an issue first.

## License

MIT
