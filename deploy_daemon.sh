#!/usr/bin/env bash
# deploy_daemon.sh - Deploy the openme daemon to a remote Debian machine
#
# Usage:
#   ./deploy_daemon.sh [OPTIONS] <user@host>
#
# Options:
#   -p, --port <port>       SSH port (default: 22)
#   -i, --identity <file>   SSH identity file (private key)
#   -f, --dest <path>       Remote destination folder (default: /opt/openme)
#   -c, --config <file>     Config file to deploy (default: daemon/config.yaml)
#   -d, --deploy-file <f>   Deploy environment file (default: deploy.env)
#   -t, --test              Run the daemon in test/debug mode after deployment
#   -h, --help              Show this help message
#
# Deploy environment file (deploy.env):
#   A deploy environment file is loaded automatically before command-line
#   arguments are parsed. By default deploy.env in the same directory as
#   this script is used; override with -d/--deploy-file.
#   This lets you persist deployment settings without repeating them on every
#   invocation. Command-line arguments always override values set in the file.
#
#   Supported variables:
#     REMOTE_HOST   - Remote host  (e.g. deploy@192.168.1.100)
#     SSH_PORT      - SSH port     (e.g. 2222)
#     SSH_IDENTITY  - Path to SSH private key
#     REMOTE_DEST   - Remote destination folder
#     CONFIG_FILE   - Config file to deploy
#     TEST_MODE     - true/false
#
#   A template is provided in deploy.env alongside this script.
#
# Examples:
#   # Basic deploy using defaults (loads deploy.env if present)
#   ./deploy_daemon.sh deploy@192.168.1.100
#
#   # Custom SSH port and identity key
#   ./deploy_daemon.sh -p 2222 -i ~/.ssh/id_ed25519 deploy@192.168.1.100
#
#   # Deploy to a custom remote folder
#   ./deploy_daemon.sh -f /srv/openme deploy@192.168.1.100
#
#   # Deploy a specific config file
#   ./deploy_daemon.sh -c ./daemon/config.prod.yaml deploy@192.168.1.100
#
#   # Use a custom deploy environment file
#   ./deploy_daemon.sh -d ./envs/prod.env deploy@192.168.1.100
#
#   # Deploy and run in test/debug mode (foreground, no iptables changes)
#   ./deploy_daemon.sh --test deploy@192.168.1.100
#
#   # Full example: custom env file, identity key, and test mode
#   ./deploy_daemon.sh -d prod.env -i ~/.ssh/id_ed25519 --test deploy@192.168.1.100

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SSH_PORT=22
SSH_IDENTITY=""
REMOTE_DEST="/opt/openme"
CONFIG_FILE=""
TEST_MODE=false
REMOTE_HOST=""
DEPLOY_ENV_FILE="$(dirname "$0")/deploy.env"

DAEMON_DIR="$(cd "$(dirname "$0")/daemon" && pwd)"
CERTS_DIR="$(cd "$(dirname "$0")/certs" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
    sed -n '2,54p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
err()   { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

# ── Pre-scan for -d/--deploy-file before loading the env file ─────────────────
for (( i=1; i<=$#; i++ )); do
    arg="${!i}"
    if [[ "$arg" == "-d" || "$arg" == "--deploy-file" ]]; then
        next=$(( i + 1 ))
        DEPLOY_ENV_FILE="${!next}"
        break
    fi
done

# ── Load deploy env file ──────────────────────────────────────────────────────
if [[ -f "$DEPLOY_ENV_FILE" ]]; then
    info "Loading deployment settings from $DEPLOY_ENV_FILE"
    # shellcheck source=deploy.env
    set -o allexport
    source "$DEPLOY_ENV_FILE"
    set +o allexport
elif [[ "$DEPLOY_ENV_FILE" != "$(dirname "$0")/deploy.env" ]]; then
    err "Deploy file not found: $DEPLOY_ENV_FILE"
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)          SSH_PORT="$2";        shift 2 ;;
        -i|--identity)      SSH_IDENTITY="$2";    shift 2 ;;
        -f|--dest)          REMOTE_DEST="$2";     shift 2 ;;
        -c|--config)        CONFIG_FILE="$2";     shift 2 ;;
        -d|--deploy-file)   DEPLOY_ENV_FILE="$2"; shift 2 ;;
        -t|--test)          TEST_MODE=true;        shift   ;;
        -h|--help)          usage ;;
        -*)                 err "Unknown option: $1" ;;
        *)                  REMOTE_HOST="$1";      shift   ;;
    esac
done

[[ -z "$REMOTE_HOST" ]] && err "No remote host specified. Usage: $0 [OPTIONS] <user@host>"

# Default config file if not specified
[[ -z "$CONFIG_FILE" ]] && CONFIG_FILE="$DAEMON_DIR/config.yaml"
[[ -f "$CONFIG_FILE" ]] || err "Config file not found: $CONFIG_FILE"

# ── Build SSH/SCP options ─────────────────────────────────────────────────────
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_IDENTITY" ]]; then
    SSH_OPTS+=(-i "$SSH_IDENTITY")
    SCP_OPTS+=(-i "$SSH_IDENTITY")
fi

ssh_run()  { ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "$@"; }
ssh_sudo() { ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" sudo "$@"; }

# ── 1. Install system dependencies on the remote machine ─────────────────────
info "Installing system dependencies (python3, venv, iptables) on $REMOTE_HOST..."
ssh_sudo bash -s <<'REMOTE_DEPS'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip iptables
REMOTE_DEPS
ok "System dependencies installed"

# ── 2. Create remote directory structure ─────────────────────────────────────
info "Creating remote directory: $REMOTE_DEST ..."
ssh_sudo bash -s -- "$REMOTE_DEST" "$REMOTE_HOST" <<'REMOTE_MKDIRS'
set -euo pipefail
DEST="$1"
DEPLOY_USER="${2%%@*}"   # strip @host if user@host was passed; fallback below
# Prefer the actual SSH login user (available via $SUDO_USER or $USER on remote)
mkdir -p "$DEST/daemon" "$DEST/certs"
REMOTE_MKDIRS
ok "Remote directories created"

# ── 3. Copy daemon source files ───────────────────────────────────────────────
info "Copying daemon files to $REMOTE_HOST:$REMOTE_DEST/daemon/ ..."
scp "${SCP_OPTS[@]}" \
    "$DAEMON_DIR/openmed.py" \
    "$DAEMON_DIR/defaults.py" \
    "$DAEMON_DIR/validators.py" \
    "$DAEMON_DIR/requirements.txt" \
    "$CONFIG_FILE" \
    "$REMOTE_HOST:$REMOTE_DEST/daemon/"
ok "Daemon files copied"

# ── 4. Copy certificates ──────────────────────────────────────────────────────
if [[ -d "$CERTS_DIR" && -n "$(ls -A "$CERTS_DIR" 2>/dev/null)" ]]; then
    info "Copying certificates to $REMOTE_HOST:$REMOTE_DEST/certs/ ..."
    scp "${SCP_OPTS[@]}" "$CERTS_DIR"/*.crt "$CERTS_DIR"/*.key \
        "$REMOTE_HOST:$REMOTE_DEST/certs/" 2>/dev/null || true
    ok "Certificates copied"
else
    info "No certificates found locally in $CERTS_DIR — skipping."
fi

# ── 5. Create Python virtual environment and install dependencies ─────────────
info "Creating virtual environment and installing Python dependencies..."
ssh_sudo bash -s -- "$REMOTE_DEST" <<'REMOTE_VENV'
set -euo pipefail
DEST="$1"
VENV="$DEST/venv"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$DEST/daemon/requirements.txt"
echo "Virtual environment ready at $VENV"
REMOTE_VENV
ok "Virtual environment created at $REMOTE_DEST/venv"

# ── 6. Install systemd service unit ──────────────────────────────────────────
info "Installing systemd service unit openmed.service ..."
CONFIG_BASENAME="$(basename "$CONFIG_FILE")"
ssh_sudo bash -s -- "$REMOTE_DEST" "$CONFIG_BASENAME" <<'REMOTE_SERVICE'
set -euo pipefail
DEST="$1"
CONFIG_BASENAME="$2"
VENV="$DEST/venv"
cat > /etc/systemd/system/openmed.service <<EOF
[Unit]
Description=OpenMe Daemon (openmed)
After=network.target

[Service]
Type=simple
ExecStart=${VENV}/bin/python3 ${DEST}/daemon/openmed.py --config-file ${DEST}/daemon/${CONFIG_BASENAME}
WorkingDirectory=${DEST}/daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable openmed.service
REMOTE_SERVICE
ok "systemd service installed and enabled"

# ── 7. Run in test mode or start the service ──────────────────────────────────
if [[ "$TEST_MODE" == true ]]; then
    info "Test mode: running daemon in foreground (DEBUG=true). Press Ctrl+C to stop."
    ssh_run bash -s -- "$REMOTE_DEST" "$(basename "$CONFIG_FILE")" <<'REMOTE_TEST'
set -euo pipefail
DEST="$1"
CONFIG_BASENAME="$2"
VENV="$DEST/venv"
# Override DEBUG flag via env so the daemon logs to stdout instead of iptables
cd "$DEST/daemon"
LOGLEVEL=DEBUG "$VENV/bin/python3" openmed.py --config-file "$CONFIG_BASENAME"
REMOTE_TEST
else
    info "Starting openmed service..."
    ssh_sudo systemctl restart openmed.service
    ssh_sudo systemctl status openmed.service --no-pager
    ok "openmed service started"
fi

ok "Deployment to $REMOTE_HOST complete!"
echo ""
echo "  Remote path : $REMOTE_DEST"
echo "  Config file : $CONFIG_FILE  →  $REMOTE_DEST/daemon/$(basename "$CONFIG_FILE")"
echo "  Venv        : $REMOTE_DEST/venv"
echo "  Service     : sudo systemctl {start|stop|status|restart} openmed"
echo "  Test mode   : $0 --test $REMOTE_HOST"
