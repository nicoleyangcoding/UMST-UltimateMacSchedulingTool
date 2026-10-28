#!/bin/zsh
# Builds build/UMST.app (hardened runtime, ad-hoc signed).
set -euo pipefail
cd "${0:a:h}/.."

APP=build/UMST.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary: Apple silicon + Intel
universal() {  # universal <output> <sources...>
  local out=$1; shift
  for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos14.0 "$@" -o "$out.$arch"
  done
  lipo -create "$out.arm64" "$out.x86_64" -output "$out"
  rm "$out.arm64" "$out.x86_64"
}

universal "$APP/Contents/MacOS/UMST" Sources/UMST/*.swift
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --options runtime --entitlements Resources/UMST.entitlements -s - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
