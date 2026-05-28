#!/usr/bin/env bash
# =============================================================================
# android/scripts/release-android.sh
#
# Local release script for the openme Android app.
# Mirrors the GitHub Actions workflow: .github/workflows/release-android-app.yml
#
# Performs in order:
#   1. Run openmekit JVM unit tests  (skippable with --skip-tests)
#   2. Build a debug APK  (openme-<version>-debug.apk)
#   3. Build a signed release APK    (openme-<version>.apk)
#      Signing is skipped when ANDROID_KEYSTORE_FILE is not set / the file
#      does not exist (matches CI behaviour when the keystore secret is absent).
#   4. Build a signed release AAB    (openme-<version>.aab)
#      Required for Google Play submission. Skipped without signing keys.
#      Use --skip-bundle to suppress AAB generation.
#   5. Copy all produced artefacts to the output directory.
#
# USAGE
#   ./android/scripts/release-android.sh <version> [options]
#
#   version   Semver string, e.g. 0.1.0  (required)
#
# OPTIONS
#   --skip-tests       Skip the Gradle unit-test step.
#   --skip-sign        Skip signing even if keystore env vars are present.
#   --skip-bundle      Skip the AAB (App Bundle) build step.
#   --output-dir DIR   Directory where the final artefacts are written.
#                      Default: dist/  (relative to the repo root)
#   --env-file FILE    Path to an env file to source instead of the default
#                      android/scripts/.env
#                      Example: --env-file ~/secrets/openme-android.env
#   --help             Show this help and exit.
#
# REQUIRED ENVIRONMENT VARIABLES  (for signed release APK)
#   ANDROID_KEYSTORE_FILE      Absolute path to your .jks / .keystore file.
#   ANDROID_KEYSTORE_PASSWORD  Password for the keystore.
#   ANDROID_KEY_ALIAS          Alias of the signing key inside the keystore.
#   ANDROID_KEY_PASSWORD       Password for that key.
#
# .ENV FILE
#   The script automatically sources android/scripts/.env when it exists.
#   Copy android/scripts/.env.example to android/scripts/.env and fill in values.
#   .env is listed in .gitignore — never commit it.
#
# CREATING A KEYSTORE (first time)
#   keytool -genkeypair -v \
#     -keystore release.keystore \
#     -alias openme \
#     -keyalg RSA -keysize 4096 \
#     -validity 10000
#
# CI DIFFERENCE
#   On CI the keystore is decoded from ANDROID_KEYSTORE_BASE64 to a temp file.
#   Locally ANDROID_KEYSTORE_FILE points directly to the file on disk.
#
# PREREQUISITES
#   - Java 17+ (java / javac must be on PATH or JAVA_HOME set)
#   - The android/gradlew wrapper (committed in the repo)
#
# SEE ALSO
#   https://openme.merlos.org/docs/developer/android.html
# =============================================================================

set -euo pipefail

# ── Resolve repo and script paths ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANDROID_DIR="$REPO_ROOT/android"

# ── Defaults ──────────────────────────────────────────────────────────────────
SKIP_TESTS=false
SKIP_SIGN=false
SKIP_BUNDLE=false
OUTPUT_DIR="$REPO_ROOT/dist"
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
        --skip-tests)     SKIP_TESTS=true;    shift ;;
        --skip-sign)      SKIP_SIGN=true;     shift ;;
        --skip-bundle)    SKIP_BUNDLE=true;   shift ;;
        --output-dir)     OUTPUT_DIR="$2";    shift 2 ;;
        --env-file)       ENV_FILE="$2";      shift 2 ;;
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
        echo "error: env file not found: $ENV_FILE"
        exit 1
    fi
fi

# Re-export JAVA_HOME if set (sourced from .env or caller's environment) so
# Gradle and any child processes can locate the JVM.
if [[ -n "${JAVA_HOME:-}" ]]; then
    export JAVA_HOME
    export PATH="$JAVA_HOME/bin:$PATH"
fi

if [[ -z "$VERSION" ]]; then
    echo "error: version argument is required."
    echo "Usage: $0 <version> [options]"
    exit 1
fi

# ── Detect signing availability ───────────────────────────────────────────────
KEYSTORE_FILE="${ANDROID_KEYSTORE_FILE:-}"
KEYSTORE_PASSWORD="${ANDROID_KEYSTORE_PASSWORD:-}"
KEY_ALIAS="${ANDROID_KEY_ALIAS:-}"
KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-}"

if [[ "$SKIP_SIGN" == false ]] && \
   [[ -n "$KEYSTORE_FILE" ]] && \
   [[ -f "$KEYSTORE_FILE" ]] && \
   [[ -n "$KEYSTORE_PASSWORD" ]] && \
   [[ -n "$KEY_ALIAS" ]] && \
   [[ -n "$KEY_PASSWORD" ]]; then
    DO_SIGN=true
else
    DO_SIGN=false
    if [[ "$SKIP_SIGN" == false ]] && [[ -n "$KEYSTORE_FILE" ]] && [[ ! -f "$KEYSTORE_FILE" ]]; then
        echo "warning: ANDROID_KEYSTORE_FILE is set but does not exist: $KEYSTORE_FILE"
        echo "         Proceeding with debug APK only."
    fi
fi

# ── Compute versionCode from semver (MAJOR*10000 + MINOR*100 + PATCH) ───────
# e.g. 0.1.0 → 100 · 0.2.0 → 200 · 1.0.0 → 10000 · 1.2.3 → 10203
IFS='.' read -r VER_MAJOR VER_MINOR VER_PATCH <<< "$VERSION"
VERSION_CODE=$(( ${VER_MAJOR:-0} * 10000 + ${VER_MINOR:-0} * 100 + ${VER_PATCH:-0} ))

# ── Setup output dir ──────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

echo "══════════════════════════════════════════════════"
echo "  openme-android local release"
echo "  version   : $VERSION"
echo "  versionCode: $VERSION_CODE"
echo "  output    : $OUTPUT_DIR"
echo "  sign APK  : $DO_SIGN"
echo "══════════════════════════════════════════════════"

cd "$ANDROID_DIR"

# ── Step 1: Unit tests ────────────────────────────────────────────────────────
if [[ "$SKIP_TESTS" == true ]]; then
    echo ""
    echo "── Skipping tests (--skip-tests) ──"
else
    echo ""
    echo "── Running openmekit unit tests ──"
    ./gradlew :openmekit:testDebugUnitTest
fi

# ── Step 2: Debug APK ─────────────────────────────────────────────────────────
echo ""
echo "── Building debug APK ──"
./gradlew :app:assembleDebug "-Pversion.code=$VERSION_CODE"

DEBUG_SRC="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"
DEBUG_OUT="$OUTPUT_DIR/openme-${VERSION}-debug.apk"
cp "$DEBUG_SRC" "$DEBUG_OUT"
echo "  debug APK: $DEBUG_OUT"

# ── Step 3: Signed release APK (optional) ────────────────────────────────────
if [[ "$DO_SIGN" == true ]]; then
    echo ""
    echo "── Building signed release APK ──"
    ./gradlew :app:assembleRelease \
        "-Pversion.code=$VERSION_CODE" \
        "-Pandroid.injected.signing.store.file=$KEYSTORE_FILE" \
        "-Pandroid.injected.signing.store.password=$KEYSTORE_PASSWORD" \
        "-Pandroid.injected.signing.key.alias=$KEY_ALIAS" \
        "-Pandroid.injected.signing.key.password=$KEY_PASSWORD"

    RELEASE_SRC="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
    RELEASE_OUT="$OUTPUT_DIR/openme-${VERSION}.apk"
    cp "$RELEASE_SRC" "$RELEASE_OUT"
    echo "  release APK: $RELEASE_OUT"
else
    echo ""
    echo "── Skipping signed release APK (keystore not configured) ──"
fi

# ── Step 4: Signed release AAB (Google Play) ─────────────────────────────────
if [[ "$SKIP_BUNDLE" == true ]]; then
    echo ""
    echo "── Skipping AAB (--skip-bundle) ──"
elif [[ "$DO_SIGN" == true ]]; then
    echo ""
    echo "── Building signed release AAB (Google Play) ──"
    ./gradlew :app:bundleRelease \
        "-Pversion.code=$VERSION_CODE" \
        "-Pandroid.injected.signing.store.file=$KEYSTORE_FILE" \
        "-Pandroid.injected.signing.store.password=$KEYSTORE_PASSWORD" \
        "-Pandroid.injected.signing.key.alias=$KEY_ALIAS" \
        "-Pandroid.injected.signing.key.password=$KEY_PASSWORD"

    AAB_SRC="$ANDROID_DIR/app/build/outputs/bundle/release/app-release.aab"
    AAB_OUT="$OUTPUT_DIR/openme-${VERSION}.aab"
    cp "$AAB_SRC" "$AAB_OUT"
    echo "  release AAB: $AAB_OUT"
else
    echo ""
    echo "── Skipping AAB (keystore not configured) ──"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo "  Done."
echo "  debug APK  : $OUTPUT_DIR/openme-${VERSION}-debug.apk"
if [[ "$DO_SIGN" == true ]]; then
    echo "  release APK: $OUTPUT_DIR/openme-${VERSION}.apk"
fi
if [[ "$DO_SIGN" == true ]] && [[ "$SKIP_BUNDLE" == false ]]; then
    echo "  release AAB: $OUTPUT_DIR/openme-${VERSION}.aab"
fi
echo "══════════════════════════════════════════════════"
