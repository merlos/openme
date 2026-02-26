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
REMOTE_SCRIPT="remote-server.sh"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "==> Building openme for linux/arm64 …"
cd "${CLI_DIR}"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
    go build -ldflags="-s -w" -o "${BINARY}" ./cmd/openme
echo "    Built ${BINARY} ($(du -sh "${BINARY}" | cut -f1))"

# ── Upload ────────────────────────────────────────────────────────────────────
SCP_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no"

echo "==> Uploading binary …"
# shellcheck disable=SC2086
scp ${SCP_OPTS} "${BINARY}" "${TARGET}:${REMOTE_HOME}/openme"

echo "==> Uploading remote-server.sh …"
# shellcheck disable=SC2086
scp ${SCP_OPTS} "${SCRIPT_DIR}/${REMOTE_SCRIPT}" \
    "${TARGET}:${REMOTE_HOME}/${REMOTE_SCRIPT}"

echo "==> Making remote files executable …"
# shellcheck disable=SC2086
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${TARGET}" \
    "chmod +x ${REMOTE_HOME}/openme ${REMOTE_HOME}/${REMOTE_SCRIPT}"

echo ""
echo "Deploy complete. To start the test server, run:"
echo "  ssh -i ${SSH_KEY} ${TARGET}"
echo "  sudo ${REMOTE_HOME}/${REMOTE_SCRIPT}"
