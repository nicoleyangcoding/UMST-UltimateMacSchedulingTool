#!/bin/zsh
# Builds, tests and packages a release: dist/UMST.zip and dist/UMST.zip.sha256
set -euo pipefail
cd "${0:a:h}/.."

./scripts/test.sh
./scripts/build.sh

rm -rf dist && mkdir dist
ditto -c -k --keepParent build/UMST.app dist/UMST.zip
(cd dist && shasum -a 256 UMST.zip > UMST.zip.sha256)
cat dist/UMST.zip.sha256
