#!/bin/zsh
# Runs the test suite.
set -euo pipefail
cd "${0:a:h}/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

cp Tests/UMSTTests.swift "$OUT/main.swift"   # top-level test code must live in main.swift
swiftc -O "$OUT/main.swift" Sources/UMST/ICS.swift Sources/UMST/Security.swift -o "$OUT/tests"
"$OUT/tests"
