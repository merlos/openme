# openme

> Single Packet Authentication (SPA) for Linux firewall port knocking — secure, stealthy, modern.

`openme` lets an authenticated client send a single encrypted UDP packet to a server to temporarily open a firewall port. To a network scanner, the port is always closed. Only clients with a valid Ed25519 key can trigger the firewall rule.

---

## Table of Contents

- [Features](#features)
- [How It Works — Protocol](#how-it-works--protocol)
- [Quick Start](#quick-start)
- [Installation](#installation)
  - [Build from Source](#build-from-source)
  - [Cross-Compilation](#cross-compilation)
- [Server Setup](#server-setup)
- [Client Setup](#client-setup)
- [Adding Clients](#adding-clients)
- [Commands](#commands)
- [Configuration Reference](#configuration-reference)
  - [Server Config](#server-config-etcopenmeconfig)
  - [Client Config](#client-config-openmeconfig)
- [Testing](#testing)
- [Security Model](#security-model)
- [License](#license)

---

## Features

- **Single packet** — one UDP datagram triggers the rule; the port appears closed at all times
- **Forward secrecy** — ephemeral Curve25519 ECDH per knock; captured packets cannot be decrypted later
- **Opaque payloads** — ChaCha20-Poly1305 AEAD encryption; the packet looks like random noise
- **Strong authentication** — Ed25519 signatures; only registered clients can knock
- **Replay protection** — timestamp window + random nonce cache
- **IPv4 and IPv6** support
- **Multiple firewall backends** — `iptables`/`ip6tables` and `nftables`
- **Named profiles** — clients can connect to multiple servers (`openme connect home`, `openme connect work`)
- **Post-knock hooks** — automatically run SSH or any command after a successful knock
- **QR code provisioning** — scan a QR to bootstrap mobile clients
- **Automatic rule expiry** — firewall rules are removed after a configurable timeout

---

## How It Works — Protocol

### Packet Structure

```
┌──────────┬───────────────────┬───────┬─────────────────┬───────────────┐
│ version  │  ephemeral_pubkey │ nonce │   ciphertext    │  ed25519_sig  │
│  1 byte  │      32 bytes     │ 12 B  │    58 bytes     │   64 bytes    │
└──────────┴───────────────────┴───────┴─────────────────┴───────────────┘
                                        ▲                  ▲
                                  ChaCha20-Poly1305    signs everything
                                  AEAD tag included    to the left
Total: 167 bytes
```

The **ciphertext** decrypts to:

```
┌─────────────┬──────────────┬─────────────┬─────────────┐
│  timestamp  │ random_nonce │  target_ip  │ target_port │
│   8 bytes   │   16 bytes   │  16 bytes   │   2 bytes   │
└─────────────┴──────────────┴─────────────┴─────────────┘
```

### Knock Flow

```
Client                                Server (sniffing UDP)
  │                                       │
  │  1. Generate ephemeral Curve25519 keypair (per knock)
  │  2. ECDH(ephemeral_priv, server_pub) → shared_secret
  │  3. Encrypt(shared_secret, timestamp+nonce+ip+port)
  │  4. Sign(ed25519_priv, version+ephem_pub+nonce+ciphertext)
  │                                       │
  │──────── UDP knock packet ────────────>│ (port appears CLOSED)
  │                                       │
  │                     5. ECDH(server_priv, ephemeral_pub) → shared_secret
  │                     6. Decrypt → plaintext
  │                     7. Verify Ed25519 signature against whitelist
  │                     8. Check timestamp ±60s window
  │                     9. Check nonce not seen before
  │                    10. Resolve target IP (0.0.0.0 = source IP)
  │                    11. Open firewall rule for target IP + ports
  │                    12. Schedule auto-removal after knock_timeout
  │                                       │
  │<═══════ TCP connect (SSH etc.) ══════>│ (port now OPEN for client IP)
```

### Cryptographic Primitives

| Purpose | Algorithm |
|---------|-----------|
| Key exchange | Curve25519 ECDH (RFC 7748) |
| Key derivation | HKDF-SHA256 |
| Symmetric encryption | ChaCha20-Poly1305 (RFC 8439) |
| Authentication | Ed25519 (RFC 8032) |
| Replay nonce | 16 bytes CSPRNG |

### Security Properties

| Property | Mechanism |
|----------|-----------|
| Forward secrecy | Ephemeral ECDH keypair per knock |
| Payload opacity | Full AEAD encryption — packet indistinguishable from noise |
| Authentication | Ed25519 signature; only whitelisted clients accepted |
| Replay protection | Timestamp window (±60s) + random nonce seen-cache |
| Key compromise isolation | Revoking a key takes effect immediately without restart |

---

## Quick Start

```bash
# On the server — initialise and start
openme init                         # generates /etc/openme/config.yaml with fresh keys
openme add alice                    # registers a client, prints client config + QR
openme serve                        # start listening

# On the client — paste config from above, then:
openme status                       # check server is reachable
openme connect                      # send knock, optionally run post_knock command
```

---

## Installation

### Build from Source

Requires **Go 1.21+**.

```bash
git clone https://github.com/openme/openme
cd openme
go build -o openme ./cmd/openme
sudo mv openme /usr/local/bin/
```

### Cross-Compilation

Go's built-in cross-compilation requires no extra tooling:

```bash
# Linux amd64 (server)
GOOS=linux GOARCH=amd64 go build -o openme-linux-amd64 ./cmd/openme

# macOS arm64 (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -o openme-darwin-arm64 ./cmd/openme

# Windows amd64
GOOS=windows GOARCH=amd64 go build -o openme-windows-amd64.exe ./cmd/openme

# Linux arm64 (Raspberry Pi, cloud ARM)
GOOS=linux GOARCH=arm64 go build -o openme-linux-arm64 ./cmd/openme
```

---

## Server Setup

### 1. Initialise

```bash
sudo openme init
```

This generates `/etc/openme/config.yaml` with a fresh Curve25519 keypair and
sensible defaults. Edit it to suit your environment:

```yaml
server:
  udp_port: 7777
  health_port: 7777       # same number, TCP
  firewall: nft           # or iptables
  knock_timeout: 30s
  replay_window: 60s
  private_key: "base64..."
  public_key:  "base64..."

defaults:
  server: "myserver.example.com"   # used when generating client configs
  ports:
    - port: 22
      proto: tcp

clients: {}
```

### 2. Firewall — allow the knock port

The server's UDP port must be reachable. The simplest allow rule:

```bash
# nftables
nft add rule inet filter input udp dport 7777 accept

# iptables
iptables -A INPUT -p udp --dport 7777 -j ACCEPT
```

### 3. Run as a systemd service

```ini
# /etc/systemd/system/openme.service
[Unit]
Description=openme SPA server
After=network.target

[Service]
ExecStart=/usr/local/bin/openme serve
Restart=on-failure
AmbientCapabilities=CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now openme
```

---

## Client Setup

The client config lives at `~/.openme/config.yaml`. It is created automatically
by `openme add` on the server, or you can write it manually.

```yaml
profiles:
  default:
    server_host: "myserver.example.com"
    server_udp_port: 7777
    server_pubkey: "base64..."     # server's Curve25519 public key
    private_key: "base64..."       # your Ed25519 private key
    public_key:  "base64..."       # your Ed25519 public key
    post_knock: "ssh user@myserver.example.com"   # optional

  work:
    server_host: "work.example.com"
    server_udp_port: 7777
    server_pubkey: "base64..."
    private_key: "base64..."
    public_key:  "base64..."
```

> **Security note:** `~/.openme/config.yaml` is written with `0600` permissions
> because it contains your private key. Back it up securely.

---

## Adding Clients

Run on the **server**:

```bash
# Register a client with default port access (SSH only)
sudo openme add alice

# Register with extra ports
sudo openme add bob --port-mode default_plus --port 2222/tcp --port 8080/tcp

# Register with only custom ports (no default SSH)
sudo openme add ci-runner --port-mode only --port 443/tcp

# With expiry
sudo openme add contractor --expires 2026-06-01T00:00:00Z

# Show QR code in terminal (contains private key — treat as secret!)
sudo openme add alice --qr

# Write QR to PNG file
sudo openme add alice --qr-out /tmp/alice-qr.png

# QR without private key (mobile generates own keypair)
sudo openme add alice-mobile --qr --no-privkey
```

The command prints a ready-to-use client config block. Copy it to
`~/.openme/config.yaml` on the client machine.

---

## Commands

| Command | Description |
|---------|-------------|
| `openme serve` | Start the SPA server |
| `openme connect [profile]` | Send a knock (default profile if omitted) |
| `openme connect home` | Knock using the `home` profile |
| `openme connect --ip 10.0.0.5` | Open firewall to a specific IP |
| `openme status [profile]` | TCP health check against the server |
| `openme add <name>` | Register a new client on the server |
| `openme list` | List all registered clients and their status |
| `openme revoke <name>` | Remove a client key immediately |
| `openme --log-level debug serve` | Verbose server logging |

---

## Configuration Reference

### Server Config (`/etc/openme/config.yaml`)

```yaml
server:
  udp_port: 7777            # UDP port for knock packets
  health_port: 7777         # TCP port for health checks (same by default)
  firewall: nft             # "nft" or "iptables"
  knock_timeout: 30s        # how long firewall rule stays open
  replay_window: 60s        # max accepted packet age
  private_key: "base64..."  # Curve25519 private key (keep secret)
  public_key:  "base64..."  # Curve25519 public key (share with clients)

defaults:
  server: "server.example.com"   # hostname/IP used in generated client configs
  ports:
    - port: 22
      proto: tcp

clients:
  alice:
    ed25519_pubkey: "base64..."
    allowed_ports:
      mode: default             # default | only | default_plus
      ports: []                 # extra ports (for default_plus or only)
    expires: "2027-01-01T00:00:00Z"   # optional; omit = never expires

  bob:
    ed25519_pubkey: "base64..."
    allowed_ports:
      mode: default_plus
      ports:
        - port: 2222
          proto: tcp
```

**Port modes:**

| Mode | Opens |
|------|-------|
| `default` | Server's `defaults.ports` only |
| `only` | Only the ports listed in the client's `ports` field |
| `default_plus` | Server defaults **plus** the client's extra ports |

### Client Config (`~/.openme/config.yaml`)

```yaml
profiles:
  default:                               # used by `openme connect`
    server_host: "server.example.com"
    server_udp_port: 7777
    server_pubkey: "base64..."           # server's Curve25519 public key
    private_key:   "base64..."           # your Ed25519 private key
    public_key:    "base64..."           # your Ed25519 public key
    post_knock:    "ssh user@server"     # optional shell command

  home:                                  # used by `openme connect home`
    server_host: "home.example.com"
    server_udp_port: 7777
    server_pubkey: "base64..."
    private_key:   "base64..."
    public_key:    "base64..."
```

---

## Testing

```bash
# Run all tests
go test ./...

# Run with verbose output
go test -v ./...

# Run a specific package
go test -v ./internal/crypto/...

# Run with race detector
go test -race ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

---

## Security Model

### What is protected

- An attacker capturing all UDP traffic **cannot decrypt** old knock packets (forward secrecy via ephemeral ECDH).
- An attacker replaying a captured packet is rejected by the timestamp window and nonce cache.
- A port scanner sees the knock port as **closed** at all times.
- Stolen server private key does not reveal which clients have knocked in the past (forward secrecy).

### What is not protected

- **DoS**: the UDP port is open to receive packets. Rate limiting (planned) will mitigate this.
- **Source IP spoofing**: if an attacker can spoof the client's source IP _and_ replay within the window before the nonce is cached, the rule would open to the attacker's IP. The random nonce makes this window effectively zero for replay.
- **Client private key theft**: if a client's Ed25519 private key is stolen, revoke it immediately with `openme revoke <name>`.

### Key distribution

- The server's **Curve25519 public key** is not secret and is included in client configs.
- The client's **Ed25519 private key** is secret and must be stored at `0600`.
- Out-of-band exchange (copy/paste or QR scan) is intentional — no PKI infrastructure required.

---

## License

MIT — see [LICENSE](LICENSE).
