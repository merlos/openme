# openme Debian package

This directory contains the Debian packaging metadata for the `openme` binary.

---

## What the package installs

| Path | Description |
|------|-------------|
| `/usr/bin/openme` | The openme binary (server + client) |
| `/lib/systemd/system/openme.service` | systemd service unit |
| `/usr/share/man/man1/openme.1.gz` | Man page |
| `/etc/openme/` | Config directory (created by `postinst`, mode `750`, owned `root:openme`) |
| `/etc/openme/config.yaml` | Server config with auto-generated keys (created by `postinst` on first install, mode `640`, owned `root:openme`) |
| `/run/openme/` | Runtime state directory for session tracking (created by systemd at service start, mode `750`, owned `openme:openme`) |

### Package files

| File | Purpose |
|------|---------|
| `control` | Package metadata (name, version, architecture, dependencies) |
| `conffiles` | List of config files dpkg should not overwrite on upgrade |
| `postinst` | Post-install script: creates the `openme` system user, sets file ownership/permissions, runs `openme init` on first install, enables the systemd service |
| `prerm` | Pre-remove script: stops and disables the service on removal; deletes the system user on purge |

### Service account

The service runs as a dedicated `openme` system user (no login shell, no home
directory). It is granted `CAP_NET_ADMIN` via `AmbientCapabilities` in the
systemd unit so it can apply nftables/iptables rules without being root.

---

## How to build the package

### Prerequisites

```sh
apt-get install dpkg-dev gzip
```

### Steps

```sh
VERSION=1.0.0
ARCH=amd64          # or arm64
BINARY=openme       # pre-built binary for the target architecture

PKGDIR="openme_${VERSION}_${ARCH}"

# 1. Create the directory tree
mkdir -p "${PKGDIR}/DEBIAN"
mkdir -p "${PKGDIR}/usr/bin"
mkdir -p "${PKGDIR}/usr/share/man/man1"
mkdir -p "${PKGDIR}/lib/systemd/system"

# 2. Copy files
install -m 755 "${BINARY}" "${PKGDIR}/usr/bin/openme"
gzip -9 -c ../openme.1 > "${PKGDIR}/usr/share/man/man1/openme.1.gz"
cp ../../systemd/openme.service "${PKGDIR}/lib/systemd/system/"

# 3. Fill in metadata
sed "s/{{VERSION}}/${VERSION}/g; s/{{ARCH}}/${ARCH}/g" \
    control > "${PKGDIR}/DEBIAN/control"
install -m 755 postinst prerm "${PKGDIR}/DEBIAN/"
cp conffiles "${PKGDIR}/DEBIAN/"

# 4. Build
dpkg-deb --root-owner-group --build "${PKGDIR}"
# → produces openme_${VERSION}_${ARCH}.deb
```

The `--root-owner-group` flag ensures all files in the package are owned by
`root:root`, regardless of the build user — required for reproducible builds in
CI.

---

## How to install the package

### From a GitHub Release (recommended)

```sh
# Download the .deb for your architecture (amd64, arm64, armhf, i386, riscv64).
curl -LO https://github.com/merlos/openme/releases/latest/download/openme_VERSION_amd64.deb
sudo dpkg -i openme_VERSION_amd64.deb
```

### Manually built package

```sh
sudo dpkg -i openme_VERSION_ARCH.deb
```

### What happens on first install

1. The `openme` system user and group are created.
2. `/etc/openme/` is created with restricted permissions (`root:openme 750`).
3. `openme init` is run automatically using the machine's hostname as the server
   address. A fresh Curve25519/Ed25519 keypair is generated and written to
   `/etc/openme/config.yaml` (`root:openme 640`).
4. The `openme.service` systemd unit is enabled (but not started).

After installation, start the server:

```sh
sudo systemctl start openme

# Verify it is running
sudo systemctl status openme

# Register a client
sudo openme add mydevice

# Optionally review/edit the generated config before starting
sudo nano /etc/openme/config.yaml
sudo systemctl restart openme
```

### Uninstall

```sh
# Remove binaries and disable service (keep config)
sudo dpkg -r openme

# Full purge — also removes config, the openme user, and the openme group
sudo dpkg -P openme
```
