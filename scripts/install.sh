#!/bin/zsh
# Builds UMST, installs it to ~/Applications, adds it as a login item and starts it.
set -euo pipefail
cd "${0:a:h}/.."

./scripts/build.sh

DATA="$HOME/Library/Application Support/UMST"
DEST="$HOME/Applications/UMST.app"

mkdir -p "$DATA" && chmod 700 "$DATA"
if [[ ! -f "$DATA/links.json" ]]; then
  cp config/links.example.json "$DATA/links.json"
  chmod 600 "$DATA/links.json"
fi

pkill -x UMST 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/UMST.app "$DEST"

osascript >/dev/null <<EOF
tell application "System Events"
  if not (exists login item "UMST") then make login item at end with properties {path:"$DEST", hidden:false}
end tell
EOF

open "$DEST"
echo "Installed to $DEST"
