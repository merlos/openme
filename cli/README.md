# openme

> Single Packet Authentication (SPA) — open your firewall with one encrypted packet.

`openme` lets authenticated clients send a single encrypted UDP packet to temporarily open a firewall port. To a port scanner the port is always closed. Only clients holding a valid Ed25519 key can knock.

**→ Full documentation at [openme.merlos.org/docs](https://openme.merlos.org/docs)**

---

## Quick Start

```bash
# Server
sudo openme init --server myserver.example.com
sudo openme add alice
sudo openme serve

# Client
openme connect
```

See the [Getting Started guide](https://openme.merlos.org/docs/getting-started/) for a full walkthrough.

---

## Build from Source

Requires **Go 1.21+**.

```bash
git clone https://github.com/merlos/openme
cd openme/cli
go mod download
go build -o openme ./cmd/openme
sudo mv openme /usr/local/bin/
```

### Cross-Compilation

```bash
GOOS=linux   GOARCH=amd64 go build -o openme-linux-amd64        ./cmd/openme
GOOS=linux   GOARCH=arm64 go build -o openme-linux-arm64         ./cmd/openme
GOOS=darwin  GOARCH=arm64 go build -o openme-darwin-arm64        ./cmd/openme
GOOS=windows GOARCH=amd64 go build -o openme-windows-amd64.exe   ./cmd/openme
```

Pre-built binaries are available on the [Releases](https://github.com/merlos/openme/releases) page.\
Full notes: [openme.merlos.org/docs/getting-started/cross-compilation](https://openme.merlos.org/docs/getting-started/cross-compilation)

---

## Documentation

| Topic | Link |
|-------|------|
| Getting Started | [openme.merlos.org/docs/getting-started](https://openme.merlos.org/docs/getting-started/) |
| Server Setup | [openme.merlos.org/docs/getting-started/server-setup](https://openme.merlos.org/docs/getting-started/server-setup) |
| Client Setup | [openme.merlos.org/docs/getting-started/client-setup](https://openme.merlos.org/docs/getting-started/client-setup) |
| Adding Clients | [openme.merlos.org/docs/getting-started/adding-clients](https://openme.merlos.org/docs/getting-started/adding-clients) |
| Configuration — Server | [openme.merlos.org/docs/configuration/server](https://openme.merlos.org/docs/configuration/server) |
| Configuration — Client | [openme.merlos.org/docs/configuration/client](https://openme.merlos.org/docs/configuration/client) |
| Firewall Backends | [openme.merlos.org/docs/configuration/firewall](https://openme.merlos.org/docs/configuration/firewall) |
| Protocol | [openme.merlos.org/docs/protocol](https://openme.merlos.org/docs/protocol/) |
| Security Model | [openme.merlos.org/docs/security](https://openme.merlos.org/docs/security/) |
| FAQ | [openme.merlos.org/docs/faq](https://openme.merlos.org/docs/faq/) |

---

## Development

```bash
# Run all tests
go test ./...

# Run with race detector
go test -race ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Vet
go vet ./...
```

---

## License

MIT — see [LICENSE](../LICENSE).
