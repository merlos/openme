#!/usr/bin/env bash
# =============================================================================
# apple/scripts/release-macos.sh
#
# Local release script for openme-macos.
# Mirrors the GitHub Actions workflow: .github/workflows/release-app-macos.yml
#
# Performs in order:
#   1. Run unit tests (xcodebuild test, skip UITests)
#   2. Build & code-sign the .app with Developer ID Application + hardened runtime
#   3. Create a DMG with drag-to-Applications layout using create-dmg
#   4. Notarize the DMG with Apple's notarytool (App Store Connect API key)
#   5. Staple the notarization ticket to the DMG
#   6. Copy the final DMG to the output directory
#
# USAGE
#   ./apple/scripts/release-macos.sh <version> [options]
#
#   version   Semver string, e.g. 0.1.0  (required)
#
# OPTIONS
#   --skip-tests       Skip xcodebuild test step.
#   --skip-notarize    Build and package DMG but skip notarization and stapling.
#                      Useful for quick local smoke-testing.
#   --output-dir DIR   Directory where the final DMG is written.
#                      Default: dist/  (relative to the repo root)
#   --env-file FILE    Path to an env file to source instead of the default
#                      apple/scripts/.env. Useful when you have per-project or
#                      per-account configs stored elsewhere.
#                      Example: --env-file ~/secrets/openme-prod.env
#   --help             Show this help and exit.
#
# REQUIRED ENVIRONMENT VARIABLES
#   APPLE_TEAM_ID            Your 10-character Apple Team ID (e.g. ABC123XYZ1).
#   APPLE_API_KEY_ID         App Store Connect API key ID  (e.g. ABCD1234EF).
#   APPLE_API_KEY_ISSUER_ID  Issuer UUID from App Store Connect.
#   APPLE_API_KEY_PATH       Absolute path to your .p8 API key file.
#                            Not required when --skip-notarize is set.
#
# OPTIONAL ENVIRONMENT VARIABLES
#   DEVELOPER_ID_IDENTITY    codesign identity string.
#                            Default: "Developer ID Application"
#                            Use the full form for disambiguation:
#                            "Developer ID Application: Your Name (TEAMID)"
#
# .ENV FILE
#   The script automatically sources apple/scripts/.env when it exists.
#   Copy apple/scripts/.env.example to apple/scripts/.env and fill in values.
#   .env is listed in .gitignore — never commit it.
#
# CI DIFFERENCE
#   On CI the Developer ID certificate is imported from a base64 GitHub secret
#   into a temporary keychain.  Locally the certificate is expected to already
#   be present in your login keychain (installed via Xcode or Keychain Access).
#
# PREREQUISITES
#   - Xcode with command-line tools (xcodebuild, codesign, xcrun)
#   - create-dmg:  brew install create-dmg
#   - Developer ID Application certificate in your login keychain
#   - App Store Connect API key (.p8 file) for notarization
#
# SEE ALSO
#   https://openme.merlos.org/docs/developer/swift-openmekit.html
# =============================================================================

set -euo pipefail

# ── Resolve repo and script paths ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APPLE_DIR="$REPO_ROOT/apple"

# ── Defaults ──────────────────────────────────────────────────────────────────
SKIP_TESTS=false
SKIP_NOTARIZE=false
OUTPUT_DIR="$REPO_ROOT/dist"
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"
VERSION=""
ENV_FILE="$SCRIPT_DIR/.env"

# ── Parse arguments ───────────────────────────────────────────────────────────
usage() {
    awk '/^# USAGE/{p=1; next} /^# ===[=]/{if(p) exit} p{sub(/^# ?/,""); print}' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)        usage ;;
        --skip-tests)     SKIP_TESTS=true;        shift ;;
        --skip-notarize)  SKIP_NOTARIZE=true;     shift ;;
        --output-dir)     OUTPUT_DIR="$2";        shift 2 ;;
        --env-file)       ENV_FILE="$2";          shift 2 ;;
        -*)               echo "Unknown option: $1"; exit 1 ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                echo "Unexpected argument: $1"; exit 1
            fi
            shift ;;
    esac
done

# ── Source .env after arg parsing so --env-file takes effect ──────────────────
if [[ -n "$ENV_FILE" ]]; then
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$ENV_FILE"
    elif [[ "$ENV_FILE" != "$SCRIPT_DIR/.env" ]]; then
        # Only error if the user explicitly passed --env-file and it doesn't exist
        echo "error: env file not found: $ENV_FILE"
        exit 1
    fi
fi

# Re-apply DEVELOPER_ID_IDENTITY default after sourcing .env (env may have set it)
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"

if [[ -z "$VERSION" ]]; then
    echo "error: version argument is required."
    echo "Usage: $0 <version> [options]"
    exit 1
fi

# ── Validate required env vars ────────────────────────────────────────────────
check_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "error: environment variable $var is not set."
        echo "  Set it in your environment or in apple/scripts/.env"
        exit 1
    fi
}

check_env APPLE_TEAM_ID
if [[ "$SKIP_NOTARIZE" == false ]]; then
    check_env APPLE_API_KEY_ID
    check_env APPLE_API_KEY_ISSUER_ID
    check_env APPLE_API_KEY_PATH
    if [[ ! -f "$APPLE_API_KEY_PATH" ]]; then
        echo "error: APPLE_API_KEY_PATH does not exist: $APPLE_API_KEY_PATH"
        exit 1
    fi
fi

# ── Check prerequisites ───────────────────────────────────────────────────────
if ! command -v create-dmg &>/dev/null; then
    echo "error: create-dmg is not installed. Run: brew install create-dmg"
    exit 1
fi

# ── Setup temp and output dirs ────────────────────────────────────────────────
WORK_DIR="$(mktemp -d)"
DMG_PATH="$WORK_DIR/openme-macos-${VERSION}.dmg"
mkdir -p "$OUTPUT_DIR"

# Ensure work dir is cleaned up on exit (normal or error)
cleanup() {
    echo ""
    echo "── Cleaning up temp directory ──"
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "══════════════════════════════════════════════════"
echo "  openme-macos local release"
echo "  version : $VERSION"
echo "  output  : $OUTPUT_DIR"
echo "══════════════════════════════════════════════════"

# ── Step 1: Tests ─────────────────────────────────────────────────────────────
if [[ "$SKIP_TESTS" == true ]]; then
    echo ""
    echo "── Skipping tests (--skip-tests) ──"
else
    echo ""
    echo "── Running tests ──"
    cd "$APPLE_DIR"
    xcodebuild -workspace openme.xcworkspace \
        -scheme openme-macos \
        -resolvePackageDependencies \
        -quiet

    xcodebuild test \
        -workspace openme.xcworkspace \
        -scheme openme-macos \
        -destination 'platform=macOS,arch=arm64' \
        -skip-testing:openme-macosUITests \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
fi

# ── Step 2: Build & sign ──────────────────────────────────────────────────────
echo ""
echo "── Building & signing ──"
DERIVED_DATA="$WORK_DIR/DerivedData"

cd "$APPLE_DIR"
xcodebuild -workspace openme.xcworkspace \
    -scheme openme-macos \
    -resolvePackageDependencies \
    -quiet

xcodebuild build \
    -workspace openme.xcworkspace \
    -scheme openme-macos \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

APP_PATH=$(find "$DERIVED_DATA" -name "openme-macos.app" -type d | head -1)
if [[ -z "$APP_PATH" ]]; then
    echo "error: could not locate openme-macos.app in DerivedData"
    exit 1
fi
echo "  .app: $APP_PATH"

# ── Step 3: Create DMG ────────────────────────────────────────────────────────
echo ""
echo "── Creating DMG ──"

create-dmg \
    --volname "openme ${VERSION}" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "openme-macos.app" 180 185 \
    --hide-extension "openme-macos.app" \
    --app-drop-link 480 185 \
    --codesign "$DEVELOPER_ID_IDENTITY" \
    "$DMG_PATH" \
    "$APP_PATH"

echo "  DMG: $DMG_PATH"

# ── Step 4: Notarize ──────────────────────────────────────────────────────────
if [[ "$SKIP_NOTARIZE" == true ]]; then
    echo ""
    echo "── Skipping notarization (--skip-notarize) ──"
else
    echo ""
    echo "── Notarizing DMG ──"
    SUBMISSION=$(xcrun notarytool submit "$DMG_PATH" \
        --key "$APPLE_API_KEY_PATH" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_KEY_ISSUER_ID" \
        --wait \
        --output-format json)

    echo "$SUBMISSION"

    SUBMISSION_ID=$(echo "$SUBMISSION" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    STATUS=$(echo "$SUBMISSION" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")

    if [[ "$STATUS" != "Accepted" ]]; then
        echo ""
        echo "error: notarization failed with status: $STATUS (id: $SUBMISSION_ID)"
        echo "── Fetching rejection log ──"
        xcrun notarytool log "$SUBMISSION_ID" \
            --key "$APPLE_API_KEY_PATH" \
            --key-id "$APPLE_API_KEY_ID" \
            --issuer "$APPLE_API_KEY_ISSUER_ID"
        exit 1
    fi

    echo "  Notarization accepted (id: $SUBMISSION_ID)"

    # ── Step 5: Staple ────────────────────────────────────────────────────────
    echo ""
    echo "── Stapling notarization ticket ──"
    xcrun stapler staple "$DMG_PATH"
fi

# ── Step 6: Copy to output dir ────────────────────────────────────────────────
FINAL_DMG="$OUTPUT_DIR/openme-macos-${VERSION}.dmg"
cp "$DMG_PATH" "$FINAL_DMG"

echo ""
echo "══════════════════════════════════════════════════"
echo "  Done."
echo "  DMG: $FINAL_DMG"
echo "══════════════════════════════════════════════════"
