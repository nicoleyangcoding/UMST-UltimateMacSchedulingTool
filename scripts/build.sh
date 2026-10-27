#!/bin/zsh
# Builds build/UMST.app (hardened runtime, ad-hoc signed).
set -euo pipefail
cd "${0:a:h}/.."

APP=build/UMST.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/UMST/*.swift -o "$APP/Contents/MacOS/UMST"
swiftc -O Tools/make_icons.swift -o "$APP/Contents/Resources/make_icons"
cp Tools/make_folders.py "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/"

codesign --force --options runtime -s - "$APP/Contents/Resources/make_icons"
codesign --force --options runtime --entitlements Resources/UMST.entitlements -s - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
