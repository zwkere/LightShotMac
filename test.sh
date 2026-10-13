#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x dist/轻截.app/Contents/MacOS/LightShot ]; then ./build.sh; fi
mkdir -p test-results
./dist/轻截.app/Contents/MacOS/LightShot --self-test | tee test-results/checks.log
