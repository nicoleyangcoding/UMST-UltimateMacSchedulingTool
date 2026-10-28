#!/bin/zsh
# Removes UMST, its login item, settings, data and Keychain items.
set -uo pipefail

pkill -x UMST 2>/dev/null
for app in "$HOME/Applications/UMST.app" "/Applications/UMST.app"; do
  [[ -x "$app/Contents/MacOS/UMST" ]] && "$app/Contents/MacOS/UMST" --unregister-login 2>/dev/null
done
rm -rf "$HOME/Applications/UMST.app" "/Applications/UMST.app"
rm -rf "$HOME/Library/Application Support/UMST"
defaults delete com.umst.app 2>/dev/null
defaults delete com.umst.app.demo 2>/dev/null
while security delete-generic-password -s com.umst.app.sources >/dev/null 2>&1; do :; done
echo "UMST has been removed."
