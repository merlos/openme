#!/usr/bin/env bash
# remote-server.sh
# Runs on the test box (linux/arm64).
#
# 1. Blocks ALL incoming traffic on all interfaces (iptables INPUT DROP).
# 2. Starts the openme server.
# 3. On Ctrl-C (SIGINT) or SIGTERM, removes the block rule and exits.
#
# Requires: iptables, sudo (or run as root)
# Usage:    sudo ./remote-server.sh [extra openme-serve flags]

set -euo pipefail

# Resolve the binary relative to the script so `sudo ./remote-server.sh` works
# regardless of whether sudo preserves $HOME or not.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OPENME="${SCRIPT_DIR}/openme"
IPTABLES_COMMENT="openme-test-block"
IPTABLES_BACKUP="/tmp/openme-iptables-backup.rules"
CHAIN_INPUT="INPUT"
CHAIN_FORWARD="FORWARD"

# ── Block all ports ───────────────────────────────────────────────────────────
block_all() {
    echo "==> Saving current iptables rules to ${IPTABLES_BACKUP} …"
    iptables-save > "${IPTABLES_BACKUP}"

    echo "==> Blocking all new incoming connections …"

    # Flush only the filter INPUT and FORWARD chains (leave OUTPUT alone).
    iptables -F "${CHAIN_INPUT}"
    iptables -F "${CHAIN_FORWARD}"

    # Set default policies to DROP so no new connections get in.
    iptables -P "${CHAIN_INPUT}"   DROP
    iptables -P "${CHAIN_FORWARD}" DROP

    # Always allow loopback.
    iptables -A "${CHAIN_INPUT}" -i lo -j ACCEPT

    # Allow packets belonging to already-established sessions so existing SSH
    # connections (and other active sessions) stay alive.
    iptables -A "${CHAIN_INPUT}" \
        -m conntrack --ctstate ESTABLISHED,RELATED \
        -j ACCEPT

    # Open the UDP knock port so clients can reach the openme server.
    iptables -A "${CHAIN_INPUT}" -p udp --dport 54154 -j ACCEPT

    echo "    Default policy → DROP; loopback + established + UDP 54154 → ACCEPT"
}

# ── Remove the block rules ────────────────────────────────────────────────────
unblock_all() {
    echo ""
    echo "==> Restoring iptables rules from ${IPTABLES_BACKUP} …"
    if [[ -f "${IPTABLES_BACKUP}" ]]; then
        iptables-restore < "${IPTABLES_BACKUP}"
        rm -f "${IPTABLES_BACKUP}"
        echo "    iptables rules restored."
    else
        # Fallback: reset to permissive defaults.
        echo "    Backup not found — resetting to ACCEPT policy."
        iptables -P "${CHAIN_INPUT}"   ACCEPT
        iptables -P "${CHAIN_FORWARD}" ACCEPT
        iptables -F "${CHAIN_INPUT}"
        iptables -F "${CHAIN_FORWARD}"
    fi
}

# ── Sanity checks ────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "error: this script must be run as root (sudo)." >&2
    exit 1
fi

if [[ ! -x "${OPENME}" ]]; then
    echo "error: ${OPENME} not found or not executable." >&2
    exit 1
fi

SERVER_CONFIG="${SCRIPT_DIR}/server.yaml"
CLIENT_CONFIG="${SCRIPT_DIR}/client.yaml"

# ── Bootstrap config if it doesn't exist ─────────────────────────────────────
if [[ ! -f "${SERVER_CONFIG}" ]]; then
    # Use the machine's primary non-loopback IP as the server address.
    SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    SERVER_IP="${SERVER_IP:-127.0.0.1}"

    echo "==> No server config found. Initialising ${SERVER_CONFIG} …"
    "${OPENME}" --config "${SERVER_CONFIG}" init --server "${SERVER_IP}" --firewall iptables --force

    echo "==> Adding client 'alice' …"
    "${OPENME}" --config "${SERVER_CONFIG}" add alice > "${CLIENT_CONFIG}"

    echo ""
    echo "──── alice's client config (${CLIENT_CONFIG}) ────"
    cat "${CLIENT_CONFIG}"
    echo "──────────────────────────────────────────────────"
    echo ""
else
    echo "==> Using existing server config: ${SERVER_CONFIG}"
fi

# ── Signal handler ──────────────────────────────────────────────────────────
cleanup() {
    unblock_all
    echo "==> Done."
    exit 0
}

trap cleanup INT TERM

# ── Main ──────────────────────────────────────────────────────────────────────
block_all

echo "==> Starting openme server (press Ctrl-C to stop and unblock) …"
"${OPENME}" --config "${SERVER_CONFIG}" --log-level debug serve "$@" &
OPENME_PID=$!

# Wait for the server process; forward signals to it.
wait "${OPENME_PID}" || true  # 'true' so trap still fires on SIGINT

# If openme exits on its own (not via signal), still clean up.
cleanup
