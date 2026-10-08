#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x "build/行测刷题器.app/Contents/MacOS/XingceFloater" ]]; then
  scripts/build-app.sh
fi
exec "build/行测刷题器.app/Contents/MacOS/XingceFloater" --import "$@"
