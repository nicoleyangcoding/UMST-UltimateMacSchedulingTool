#!/bin/zsh
# UMST installer: downloads the latest release, verifies its checksum and installs it to ~/Applications.
# It also installs Show Desktop by @stanczykwyatt (https://github.com/stanczykwyatt/show-desktop),
# which hides every window in one click so the calendar on your desktop is in view.
#
#   curl -fsSL https://raw.githubusercontent.com/nicoleyangcoding/UMST-UltimateMacSchedulingTool/main/install.sh | zsh
#
# To install UMST alone:
#   curl -fsSL https://raw.githubusercontent.com/nicoleyangcoding/UMST-UltimateMacSchedulingTool/main/install.sh | SHOW_DESKTOP=0 zsh
#
set -euo pipefail

REPO="nicoleyangcoding/UMST-UltimateMacSchedulingTool"
DEST="$HOME/Applications/UMST.app"
BASE="https://github.com/$REPO/releases/latest/download"
SD_BASE="https://github.com/stanczykwyatt/show-desktop/releases/latest/download"
SD_ID="com.stanczykwyatt.ShowDesktop"

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
echo "UMST is installed and running. Look for the calendar on your desktop and the calendar icon in your menu bar."

# Show Desktop is its own app, downloaded from its author's GitHub releases. A problem here never undoes UMST.
install_show_desktop() {
  local app="Show Desktop.app" dest="$HOME/Applications/Show Desktop.app"
  if [[ -d "/Applications/$app" ]]; then
    echo "Show Desktop is already in /Applications."
    return 0
  fi
  echo "Downloading Show Desktop by @stanczykwyatt…"
  curl -fsSL --proto '=https' --tlsv1.2 "$SD_BASE/Show-Desktop.zip" -o "$TMP/Show-Desktop.zip" || return 1
  # Checked when the release publishes a checksum
  if curl -fsSL --proto '=https' --tlsv1.2 "$SD_BASE/Show-Desktop.zip.sha256" -o "$TMP/Show-Desktop.zip.sha256" 2>/dev/null; then
    [[ "$(awk '{print $1}' "$TMP/Show-Desktop.zip.sha256")" == "$(shasum -a 256 "$TMP/Show-Desktop.zip" | awk '{print $1}')" ]] || return 1
  fi
  mkdir "$TMP/sd" && ditto -x -k "$TMP/Show-Desktop.zip" "$TMP/sd" || return 1
  codesign --verify --strict -R="identifier \"$SD_ID\"" "$TMP/sd/$app" 2>/dev/null || return 1

  pkill -x ShowDesktop 2>/dev/null || true
  rm -rf "$dest"
  mv "$TMP/sd/$app" "$dest" || return 1
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
  open "$dest"
  echo "Show Desktop is installed. Click its menu bar icon or press ⌃⇧D to hide every window and see your calendar."
}

if [[ "${SHOW_DESKTOP:-1}" != 0 ]]; then
  install_show_desktop || echo "Couldn't install Show Desktop. You can get it from https://github.com/stanczykwyatt/show-desktop" >&2
fi
