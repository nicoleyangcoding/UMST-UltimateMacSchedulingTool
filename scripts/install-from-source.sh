#!/bin/zsh
# Builds UMST from source, installs it to ~/Applications and starts it.
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

open "$DEST"
echo "Installed to $DEST"
