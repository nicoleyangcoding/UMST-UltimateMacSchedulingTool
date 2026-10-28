#!/bin/zsh
# Builds UMST from source, installs it to ~/Applications and starts it.
set -euo pipefail
cd "${0:a:h}/.."

./scripts/build.sh

DEST="$HOME/Applications/UMST.app"

pkill -x UMST 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R build/UMST.app "$DEST"

open "$DEST"
echo "Installed to $DEST"
