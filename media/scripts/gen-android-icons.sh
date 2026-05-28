#!/usr/bin/env bash
# USAGE
# Generate Android launcher icons from media/logo/icon.svg.
#
# Usage:
#   ./media/scripts/gen-android-icons.sh [--copy] [--help]
#
# Options:
#   --copy   Copy the generated PNGs into android/app/src/main/res/mipmap-*/
#   --help   Show this help text
#
# Requirements:
#   rsvg-convert  (librsvg)   — brew install librsvg   / apt install librsvg2-bin
#   OR
#   inkscape                  — brew install inkscape   / apt install inkscape
#
# Output (without --copy):
#   media/icons/android/mipmap-mdpi/ic_launcher.png        48×48
#   media/icons/android/mipmap-mdpi/ic_launcher_round.png  48×48
#   media/icons/android/mipmap-hdpi/…                      72×72
#   media/icons/android/mipmap-xhdpi/…                     96×96
#   media/icons/android/mipmap-xxhdpi/…                    144×144
#   media/icons/android/mipmap-xxxhdpi/…                   192×192
# END_USAGE

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SVG="$REPO_ROOT/media/logo/icon.svg"
OUT_DIR="$REPO_ROOT/media/icons/android"
ANDROID_RES="$REPO_ROOT/android/app/src/main/res"

# ── Options ──────────────────────────────────────────────────────────────────
COPY=false

for arg in "$@"; do
  case "$arg" in
    --copy)  COPY=true ;;
    --help|-h)
      awk '/^# USAGE/,/^# END_USAGE/' "${BASH_SOURCE[0]}" \
        | grep -v '^# USAGE\|^# END_USAGE' \
        | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Detect converter ─────────────────────────────────────────────────────────
if command -v rsvg-convert &>/dev/null; then
  CONVERTER=rsvg
elif command -v inkscape &>/dev/null; then
  CONVERTER=inkscape
else
  echo "Error: neither rsvg-convert nor inkscape found." >&2
  echo "Install one of:" >&2
  echo "  brew install librsvg    (macOS)" >&2
  echo "  apt install librsvg2-bin  (Debian/Ubuntu)" >&2
  echo "  brew install inkscape   (macOS)" >&2
  exit 1
fi

# ── Render function ───────────────────────────────────────────────────────────
# render <size> <output_path>
render() {
  local size="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  if [[ "$CONVERTER" == rsvg ]]; then
    rsvg-convert -w "$size" -h "$size" -o "$out" "$SVG"
  else
    inkscape --export-type=png \
             --export-width="$size" \
             --export-height="$size" \
             --export-filename="$out" \
             "$SVG" 2>/dev/null
  fi
}

# ── Density table ─────────────────────────────────────────────────────────────
# Format: "density size"
DENSITIES=(
  "mdpi     48"
  "hdpi     72"
  "xhdpi    96"
  "xxhdpi   144"
  "xxxhdpi  192"
)

# ── Generate ─────────────────────────────────────────────────────────────────
echo "Source SVG : $SVG"
echo "Output dir : $OUT_DIR"
echo "Converter  : $CONVERTER"
echo ""

for entry in "${DENSITIES[@]}"; do
  density=$(echo "$entry" | awk '{print $1}')
  size=$(echo "$entry"    | awk '{print $2}')
  dir="$OUT_DIR/mipmap-$density"

  render "$size" "$dir/ic_launcher.png"
  render "$size" "$dir/ic_launcher_round.png"

  echo "  mipmap-$density  ${size}×${size}px  ✓"
done

echo ""
echo "Done. Icons written to: $OUT_DIR"

# ── Copy ─────────────────────────────────────────────────────────────────────
if [[ "$COPY" == true ]]; then
  echo ""
  echo "Copying to Android project..."
  for entry in "${DENSITIES[@]}"; do
    density=$(echo "$entry" | awk '{print $1}')
    src="$OUT_DIR/mipmap-$density"
    dst="$ANDROID_RES/mipmap-$density"
    mkdir -p "$dst"
    cp "$src/ic_launcher.png"       "$dst/ic_launcher.png"
    cp "$src/ic_launcher_round.png" "$dst/ic_launcher_round.png"
    echo "  → $dst"
  done
  echo "Done."
fi
