#!/bin/zsh
# Removes UMST, its settings, its data and its Keychain items.
set -uo pipefail

pkill -x UMST 2>/dev/null
rm -rf "$HOME/Applications/UMST.app" "/Applications/UMST.app"
rm -rf "$HOME/Library/Application Support/UMST"
defaults delete com.umst.app 2>/dev/null
while security delete-generic-password -s com.umst.app.sources >/dev/null 2>&1; do :; done
echo "UMST has been removed."
