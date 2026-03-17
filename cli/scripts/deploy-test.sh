#!/usr/bin/env bash
# deploy-test.sh
# Builds openme for linux/arm64, then uploads both the binary and the
# remote test-server script to the test box at 192.168.4.111.
#
# Usage:
#   ./scripts/deploy-test.sh [user@host]
#
# Defaults:
#   host  : 192.168.4.111
#   user  : merlos
#   key   : ~/.ssh/openme

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-merlos@192.168.4.111}"
SSH_KEY="${HOME}/.ssh/openme"
REMOTE_HOME="/home/merlos"   # adjust if deploying as a non-root user

BINARY="openme-linux-arm64"
BINARY_MACOS="openme-darwin-arm64"
REMOTE_SCRIPT="remote-server.sh"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "==> Building openme for linux/arm64 …"
cd "${CLI_DIR}"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -ldflags="-s -w" -o "${BINARY}" ./cmd/openme
echo "    Built ${BINARY} ($(du -sh "${BINARY}" | cut -f1))"

echo "==> Building openme for darwin/arm64 (Apple M1) …"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
    go build -ldflags="-s -w" -o "${BINARY_MACOS}" ./cmd/openme
echo "    Built ${BINARY_MACOS} ($(du -sh "${BINARY_MACOS}" | cut -f1))"

# ── Upload ────────────────────────────────────────────────────────────────────
SCP_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

scp_or_die() {
    # shellcheck disable=SC2086
    if ! scp ${SCP_OPTS} "$@"; then
        echo "" >&2
        echo "error: scp failed. Check that:" >&2
        echo "  • the openme server is running on ${TARGET##*@} and you have knocked" >&2
        echo "      openme knock   (or: openme status --knock)" >&2
        echo "  • the host is reachable: ping ${TARGET##*@}" >&2
        echo "  • your SSH key is correct: ${SSH_KEY}" >&2
        echo "  • the user '${TARGET%%@*}' has access: ssh -i ${SSH_KEY} ${TARGET} whoami" >&2
        exit 1
    fi
}

echo "==> Uploading binary …"
scp_or_die "${BINARY}" "${TARGET}:${REMOTE_HOME}/openme"

echo "==> Uploading remote-server.sh …"
scp_or_die "${SCRIPT_DIR}/${REMOTE_SCRIPT}" "${TARGET}:${REMOTE_HOME}/${REMOTE_SCRIPT}"

echo "==> Making remote files executable …"
# shellcheck disable=SC2086
if ! ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${TARGET}" \
    "chmod +x ${REMOTE_HOME}/openme ${REMOTE_HOME}/${REMOTE_SCRIPT}"; then
    echo "" >&2
    echo "error: ssh command failed. Make sure the openme server is running on ${TARGET##*@} and you have knocked first." >&2
    exit 1
fi

echo ""
echo "Deploy complete. To start the test server, run:"
echo "  ssh -i ${SSH_KEY} ${TARGET}"
echo "  sudo ${REMOTE_HOME}/${REMOTE_SCRIPT}"
