#!/usr/bin/env bash
# =============================================================================
# docs/scripts/gen-variables.sh
#
# Generates docs/_variables.yml with the latest GitHub release version for
# each openme platform.  Used by both CI and local Quarto renders so the
# download page always shows the correct version numbers and download links.
#
# Mirrors the inline step in: .github/workflows/docs.yml
#   ("Generate _variables.yml (latest release versions)")
#
# Performs in order:
#   1. Parse arguments / flags
#   2. For each platform, query the GitHub Releases API (unless --offline)
#   3. Write docs/_variables.yml relative to the repository root
#   4. Print the generated file to stdout
#
# USAGE
#   ./docs/scripts/gen-variables.sh [options]
#
# OPTIONS
#   --offline    Skip GitHub API calls and write 0.0.1-dev for all versions.
#                Useful for quick local renders without a GitHub login or
#                network access.
#   --help       Show this help and exit.
#
# PREREQUISITES (online mode only)
#   - GitHub CLI (gh) installed and authenticated:  gh auth login
#     Alternatively, export GH_TOKEN before running (used automatically by CI).
#
# CI DIFFERENCE
#   On CI, GH_TOKEN is injected from secrets.GITHUB_TOKEN — no extra
#   configuration is needed.  Locally, gh uses the token from gh auth login.
#
# OUTPUT FILE
#   docs/_variables.yml  (relative to the repository root)
#
#   Example output:
#     macos_version:   "0.1.0"
#     android_version: "0.1.0"
#     windows_version: "0.1.0"
#     cli_version:     "0.1.0"
#     playstore_url:   "https://play.google.com/store/apps/details?id=org.merlos.openme"
#     appstore_url:    "https://apps.apple.com/app/openme"
#
# LOCAL WORKFLOW
#   # One-time: authenticate with GitHub
#   gh auth login
#
#   # Generate _variables.yml with real release versions, then render:
#   ./docs/scripts/gen-variables.sh
#   cd docs && quarto render
#
#   # Quick smoke-test — no network or GitHub auth required:
#   ./docs/scripts/gen-variables.sh --offline
#   cd docs && quarto render
#
#   # Preview with live reload:
#   ./docs/scripts/gen-variables.sh --offline
#   cd docs && quarto preview
#
# SEE ALSO
#   https://openme.merlos.org/docs/
# =============================================================================

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VARIABLES_FILE="$REPO_ROOT/docs/_variables.yml"

# ── Tag prefix configuration ──────────────────────────────────────────────────
# Change these when the tag naming convention changes.  They are written into
# _variables.yml so download.js can always stay in sync automatically.
TAG_PREFIX_MACOS="macos-app-v"
TAG_PREFIX_ANDROID="android-app-v"
TAG_PREFIX_WINDOWS="windows-app-v"
TAG_PREFIX_CLI="cli-v"

# ── Defaults ──────────────────────────────────────────────────────────────────
OFFLINE=false
DEV_FALLBACK="0.0.1-dev"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
    awk '/^# USAGE/{p=1; next} /^# ===[=]/{if(p) exit} p{sub(/^# ?/,""); print}' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)   usage ;;
        --offline)   OFFLINE=true; shift ;;
        *)           echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Version lookup ────────────────────────────────────────────────────────────
# Queries the GitHub Releases API for the most recent release whose tag name
# starts with PREFIX and returns the bare version string (prefix stripped).
# Outputs an empty string when no matching release exists yet.
get_version() {
    local prefix="$1"
    gh api 'repos/merlos/openme/releases?per_page=100' \
        --jq "[.[] | select(.tag_name | startswith(\"${prefix}\"))][0].tag_name // \"\"" \
        | sed "s/^${prefix}//"
}

# ── Fetch (or stub) versions ──────────────────────────────────────────────────
if [[ "$OFFLINE" == true ]]; then
    echo "── Offline mode: using ${DEV_FALLBACK} for all versions ──"
    MACOS="$DEV_FALLBACK"
    ANDROID="$DEV_FALLBACK"
    WINDOWS="$DEV_FALLBACK"
    CLI="$DEV_FALLBACK"
else
    echo "── Fetching latest release versions from GitHub ──"
    MACOS="$(get_version "$TAG_PREFIX_MACOS")"
    ANDROID="$(get_version "$TAG_PREFIX_ANDROID")"
    WINDOWS="$(get_version "$TAG_PREFIX_WINDOWS")"
    CLI="$(get_version "$TAG_PREFIX_CLI")"
fi

# ── Write docs/_variables.yml ─────────────────────────────────────────────────
cat > "$VARIABLES_FILE" <<EOF
macos_version:      "${MACOS:-$DEV_FALLBACK}"
android_version:    "${ANDROID:-$DEV_FALLBACK}"
windows_version:    "${WINDOWS:-$DEV_FALLBACK}"
cli_version:        "${CLI:-$DEV_FALLBACK}"
macos_tag_prefix:   "${TAG_PREFIX_MACOS}"
android_tag_prefix: "${TAG_PREFIX_ANDROID}"
windows_tag_prefix: "${TAG_PREFIX_WINDOWS}"
cli_tag_prefix:     "${TAG_PREFIX_CLI}"
playstore_url:      "https://play.google.com/store/apps/details?id=org.merlos.openme"
appstore_url:       "https://apps.apple.com/app/openme"
EOF

echo ""
echo "── Generated $VARIABLES_FILE ──"
cat "$VARIABLES_FILE"
