#!/bin/zsh
# UMST installer: downloads the latest release, verifies its checksum and installs it to ~/Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/nicoleyangcoding/UMST-UltimateMacSchedulingTool/main/install.sh | zsh
#
set -euo pipefail

REPO="nicoleyangcoding/UMST-UltimateMacSchedulingTool"
DEST="$HOME/Applications/UMST.app"
BASE="https://github.com/$REPO/releases/latest/download"

autoload -U is-at-least
if ! is-at-least 14 "$(sw_vers -productVersion)"; then
  echo "UMST needs macOS 14 Sonoma or later." >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading UMST…"
curl -fsSL --proto '=https' --tlsv1.2 "$BASE/UMST.zip" -o "$TMP/UMST.zip"
curl -fsSL --proto '=https' --tlsv1.2 "$BASE/UMST.zip.sha256" -o "$TMP/UMST.zip.sha256"

expected=$(awk '{print $1}' "$TMP/UMST.zip.sha256")
actual=$(shasum -a 256 "$TMP/UMST.zip" | awk '{print $1}')
if [[ "$expected" != "$actual" ]]; then
  echo "Checksum mismatch. Aborting." >&2
  exit 1
fi

ditto -x -k "$TMP/UMST.zip" "$TMP"
codesign --verify --strict "$TMP/UMST.app"

pkill -x UMST 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
mv "$TMP/UMST.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

open "$DEST"
echo "UMST is installed and running. Look for the calendar on your desktop and the icons in your menu bar."
