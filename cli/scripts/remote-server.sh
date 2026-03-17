#!/usr/bin/env bash
# remote-server.sh
# Runs on the test box (linux/arm64).
#
# 1. Blocks ALL incoming traffic (iptables INPUT DROP).
# 2. Starts the openme server.
# 3. On Ctrl-C (SIGINT) or SIGTERM, removes the block rules and exits.
#
# Usage:    sudo ./remote-server.sh [-i] [-h] [extra openme-serve flags]
#
# Options:
#   -i   Use iptables firewall backend (default: nft)
#   -h   Show this help and exit

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
FIREWALL_BACKEND="nft"

usage() {
    grep '^#' "$0" | grep -v '!/usr/bin' | sed 's/^# \{0,1\}//'
    exit 0
}

# Parse our own flags; collect anything else as extra args for openme serve.
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i) FIREWALL_BACKEND="iptables"; shift ;;
        -h) usage ;;
        *)  EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# Resolve the binary relative to the script so `sudo ./remote-server.sh` works
# regardless of whether sudo preserves $HOME or not.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OPENME="${SCRIPT_DIR}/openme"
IPTABLES_BACKUP="/tmp/openme-iptables-backup.rules"
CHAIN_INPUT="INPUT"
CHAIN_FORWARD="FORWARD"

# ── Block all ports (iptables) ────────────────────────────────────────────────
block_all_iptables() {
    echo "==> Saving current iptables rules to ${IPTABLES_BACKUP} …"
    iptables-save > "${IPTABLES_BACKUP}"

    echo "==> Blocking all new incoming connections (iptables) …"
    iptables -F "${CHAIN_INPUT}"
    iptables -F "${CHAIN_FORWARD}"
    iptables -P "${CHAIN_INPUT}"   DROP
    iptables -P "${CHAIN_FORWARD}" DROP
    iptables -A "${CHAIN_INPUT}" -i lo -j ACCEPT
    iptables -A "${CHAIN_INPUT}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A "${CHAIN_INPUT}" -p udp --dport 54154 -j ACCEPT
    echo "    Default policy → DROP; loopback + established + UDP 54154 → ACCEPT"
}

# ── Block all ports (nft) ─────────────────────────────────────────────────────
block_all_nft() {
    echo "==> Blocking all new incoming connections (nft) …"
    nft flush ruleset
    nft add table inet filter
    nft add chain inet filter input   '{ type filter hook input   priority 0; policy drop; }'
    nft add chain inet filter forward '{ type filter hook forward priority 0; policy drop; }'
    nft add chain inet filter output  '{ type filter hook output  priority 0; policy accept; }'
    nft add rule  inet filter input ct state established,related accept
    nft add rule  inet filter input iifname lo accept
    nft add rule  inet filter input udp dport 54154 accept
    # openme manages rules inside this chain
    nft add chain inet filter openme
    nft add rule  inet filter input jump openme
    echo "    Default policy → drop; loopback + established + UDP 54154 → accept"
}

block_all() {
    if [[ "${FIREWALL_BACKEND}" == "iptables" ]]; then
        block_all_iptables
    else
        block_all_nft
    fi
}

# ── Unblock (iptables) ────────────────────────────────────────────────────────
unblock_all_iptables() {
    echo "==> Restoring iptables rules from ${IPTABLES_BACKUP} …"
    if [[ -f "${IPTABLES_BACKUP}" ]]; then
        iptables-restore < "${IPTABLES_BACKUP}"
        rm -f "${IPTABLES_BACKUP}"
        echo "    iptables rules restored."
    else
        echo "    Backup not found — resetting to ACCEPT policy."
        iptables -P "${CHAIN_INPUT}"   ACCEPT
        iptables -P "${CHAIN_FORWARD}" ACCEPT
        iptables -F "${CHAIN_INPUT}"
        iptables -F "${CHAIN_FORWARD}"
    fi
}

# ── Unblock (nft) ─────────────────────────────────────────────────────────────
unblock_all_nft() {
    echo "==> Flushing nft ruleset …"
    nft flush ruleset
    echo "    nft ruleset cleared."
}

unblock_all() {
    echo ""
    if [[ "${FIREWALL_BACKEND}" == "iptables" ]]; then
        unblock_all_iptables
    else
        unblock_all_nft
    fi
}

# ── Sanity checks ─────────────────────────────────────────────────────────────
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

echo "==> Firewall backend: ${FIREWALL_BACKEND}"

# ── Bootstrap config if it doesn't exist ─────────────────────────────────────
if [[ ! -f "${SERVER_CONFIG}" ]]; then
    SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    SERVER_IP="${SERVER_IP:-127.0.0.1}"

    echo "==> No server config found. Initialising ${SERVER_CONFIG} …"
    "${OPENME}" --config "${SERVER_CONFIG}" init \
        --server "${SERVER_IP}" --firewall "${FIREWALL_BACKEND}" --force

    echo "==> Adding client 'alice' …"
    "${OPENME}" --config "${SERVER_CONFIG}" add alice > "${CLIENT_CONFIG}"

    echo ""
    echo "──── alice's client config (${CLIENT_CONFIG}) ────"
    cat "${CLIENT_CONFIG}"
    echo "──────────────────────────────────────────────────"
    echo ""
else
    echo "==> Using existing server config: ${SERVER_CONFIG}"
    # Patch the firewall backend to match the selected option.
    if grep -q 'firewall:' "${SERVER_CONFIG}"; then
        sed -i "s/firewall:.*/firewall: ${FIREWALL_BACKEND}/" "${SERVER_CONFIG}"
        echo "    firewall backend set to ${FIREWALL_BACKEND}."
    fi
fi

# ── Signal handler ────────────────────────────────────────────────────────────
cleanup() {
    unblock_all
    echo "==> Done."
    exit 0
}

trap cleanup INT TERM

# ── Main ──────────────────────────────────────────────────────────────────────
block_all

echo "==> Starting openme server (press Ctrl-C to stop and unblock) …"
"${OPENME}" --config "${SERVER_CONFIG}" --log-level debug serve "${EXTRA_ARGS[@]}" &
OPENME_PID=$!

# Wait for the server process; forward signals to it.
wait "${OPENME_PID}" || true  # 'true' so trap still fires on SIGINT

# If openme exits on its own (not via signal), still clean up.
cleanup
