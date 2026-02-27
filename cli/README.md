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

## Installation

### Debian / Ubuntu / Raspbian

Download the `.deb` for your architecture from the [Releases](https://github.com/merlos/openme/releases) page, then:

```bash
# amd64 (x86-64 servers/desktops)
sudo dpkg -i openme_<version>_amd64.deb

# arm64 (Raspberry Pi 5, 64-bit arm servers …)
sudo dpkg -i openme_<version>_arm64.deb
```

The package installs the binary at `/usr/bin/openme`, drops a systemd unit at
`/lib/systemd/system/openme.service`, and enables it automatically via the
`postinst` script.  Initialise the server before starting:

```bash
sudo openme init --server myserver.example.com
sudo openme add alice
sudo systemctl start openme
```

To build the `.deb` packages yourself (requires `dpkg-dev`):

```bash
cd cli
make package-deb          # builds both amd64 and arm64 into dist/
# or individually:
make package-deb-amd64
make package-deb-arm64
```

---

### Arch Linux

A `PKGBUILD` is provided in [`packaging/arch/`](packaging/arch/):

```bash
git clone https://github.com/merlos/openme
cd openme/cli/packaging/arch
makepkg -si
```

This builds from source (requires `go`), installs the binary and the
systemd unit, then enables the service.

---

### OpenWrt

openme is distributed as an OpenWrt feed package.  Place the contents of
[`packaging/openwrt/`](packaging/openwrt/) inside your OpenWrt feed directory:

```
<feed>/net/openme/Makefile
<feed>/net/openme/files/openme.init
```

Then build and install:

```bash
# From the OpenWrt build system root:
./scripts/feeds update <feed>
./scripts/feeds install openme
make package/openme/compile
# Install on the router:
scp bin/packages/*/openme*.ipk root@<router>:/tmp/
ssh root@<router> opkg install /tmp/openme_*.ipk
```

After installation, initialise the server config and start:

```bash
openme init --server <hostname-or-ip>
/etc/init.d/openme enable
/etc/init.d/openme start
```

The procd init script in `/etc/init.d/openme` manages restarts and
automatically reloads when `/etc/openme/config.yaml` changes.

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
