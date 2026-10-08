#!/bin/bash
set -euo pipefail
osascript -e 'tell application "行测刷题器" to quit' >/dev/null 2>&1 || true
killall XingceFloater >/dev/null 2>&1 || true
echo "已停止"
