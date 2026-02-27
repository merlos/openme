# openme

> Open your firewall with a single encrypted packet. Nothing else is ever visible.

openme is a **Single Packet Authentication (SPA)** tool. To a port scanner, every port is always closed. Only clients holding a valid Ed25519 key can send a knock that temporarily opens a firewall rule — and the knock itself looks like random noise on the wire.

```
Client                              Server (port always CLOSED to scanners)
  │                                     │
  │──── 165 bytes of encrypted UDP ────>│  verify signature
  │                                     │  decrypt payload
  │                                     │  open firewall rule for 30s
  │<══════════ SSH / HTTPS / etc. ══════│
```

---

## Repository Layout

```
openme/
├── cli/          Go server daemon + cross-platform CLI
├── apple/
│   ├── OpenMeKit/      Swift package — shared SPA client library (iOS, macOS, watchOS)
│   ├── openme-ios/     iOS app (SwiftUI, Profiles, QR/YAML import, knock widget)
│   ├── openme-macos/   macOS app (SwiftUI menu-bar, Profiles, AppleScript post-knock)
│   ├── openme-watch/   watchOS app (WatchConnectivity sync from iPhone)
│   ├── openme-widget/  iOS/macOS WidgetKit widget (one-tap knock from home screen)
│   └── openme.xcworkspace/
├── android/
│   ├── openmekit/      Kotlin library — SPA protocol, profile storage, YAML/QR import
│   └── app/            Android app (Jetpack Compose, Material 3)
├── windows/
│   ├── OpenMeKit/      .NET client library (Kotlin-equivalent)
│   ├── openme-windows/ WPF system-tray application
│   └── OpenMeKit.Tests/
├── docs/         Quarto documentation site   → openme.merlos.org/docs/
└── website/      Marketing landing page      → openme.merlos.org
```

---

## Getting Started with the CLI

### Install

```bash
# Build from source (requires Go 1.21+)
git clone https://github.com/merlos/openme
cd openme/cli
go mod download
go build -o openme ./cmd/openme
sudo mv openme /usr/local/bin/
```

Pre-built binaries for Linux, macOS and Windows are available on the [Releases](https://github.com/merlos/openme/releases) page.

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

The full documentation is published at **[openme.merlos.org/docs](https://openme.merlos.org/docs)**.

| Section | Description |
|---------|-------------|
| [Protocol](docs/protocol/) | Wire format, cryptographic design, security properties |
| [Getting Started](docs/getting-started/) | Step-by-step server and client setup |
| [Configuration](docs/configuration/) | All config options for server and client |
| [Security Model](docs/security/) | Threat model, what is and isn't protected |
| [FAQ](docs/faq/) | Common questions |
| [API Reference](docs/api/) | Auto-generated from Go source via pkgsite |
| [OpenMeKit SDK Reference](docs/openmekit/) | Swift API reference for the Apple client library |
| [Android SDK](docs/android-sdk/) | Kotlin/Android library reference (KDoc via Dokka) |

### Build the Quarto docs locally

```bash
cd docs
quarto preview
```

---

## Platform Status

| Platform | Status | Notes |
|----------|--------|-------|
| **Linux** (server + CLI) | ✅ Active | iptables & nftables backends |
| **macOS** (CLI client) | ✅ Active | Cross-compiled from Go |
| **Windows** (CLI client) | ✅ Active | Cross-compiled from Go |
| **iOS** app | ✅ Active | SwiftUI · QR + YAML import · swipe-to-knock · inline feedback · countdown timer |
| **macOS** app | ✅ Active | SwiftUI · menu-bar style · post-knock AppleScript |
| **watchOS** app | ✅ Active | WatchConnectivity sync from iPhone · pull-to-refresh |
| **iOS/macOS Widget** | ✅ Active | WidgetKit one-tap knock from home/lock screen |
| **Android** app | ✅ Active | Jetpack Compose · Material 3 · swipe-to-knock / swipe-to-delete |
| **Android** library (openmekit) | ✅ Active | Kotlin · Ed25519 + X25519 + ChaCha20-Poly1305 · DataStore profiles |
| **Windows** GUI | ✅ Active | WPF (.NET 8), system tray, profile manager, YAML import, continuous knock |

---

## Contributing

Each platform has its own subdirectory, build toolchain and README:

| Directory | README |
|-----------|--------|
| Go CLI + server | [cli/README.md](cli/README.md) |
| Swift library (iOS / macOS / watchOS) | [apple/OpenMeKit/README.md](apple/OpenMeKit/README.md) |
| iOS, macOS, watchOS, widget apps | [apple/openme-ios/README.md](apple/openme-ios/README.md) · [apple/openme-macos/README.md](apple/openme-macos/README.md) |
| Android app + Kotlin library | [android/README.md](android/README.md) |
| Windows app + .NET library | [windows/README.md](windows/README.md) |

All cryptographic protocol changes should be discussed in an issue first.

## License

MIT — see [LICENSE](LICENSE).
