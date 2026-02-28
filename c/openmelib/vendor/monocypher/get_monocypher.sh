#!/usr/bin/env sh
# get_monocypher.sh — fetch Monocypher sources into this directory.
#
# Usage:
#   ./get_monocypher.sh           # uses default version below
#   MONO_VER=4.0.2 ./get_monocypher.sh

set -e

MONO_VER="${MONO_VER:-4.0.2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${SCRIPT_DIR}"

echo "Fetching Monocypher ${MONO_VER} …"

TARBALL="monocypher-${MONO_VER}.tar.gz"
URL="https://monocypher.org/download/${TARBALL}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL -o "${TMP}/${TARBALL}" "${URL}"
tar -xzf "${TMP}/${TARBALL}" -C "${TMP}"

SRC="${TMP}/monocypher-${MONO_VER}/src"
cp "${SRC}/monocypher.h" "${DEST}/monocypher.h"
cp "${SRC}/monocypher.c" "${DEST}/monocypher.c"

echo "Copied monocypher.h and monocypher.c to ${DEST}"
