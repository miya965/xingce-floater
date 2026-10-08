#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/embed-schema.py
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="build/行测刷题器.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/images"
swiftc \
  -sdk "$SDK" \
  -target x86_64-apple-macos12.0 \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework CryptoKit \
  -lsqlite3 \
  -o "$APP/Contents/MacOS/XingceFloater" \
  Sources/XingceCore/*.swift \
  Sources/XingceApp/*.swift
cp Sources/XingceApp/Info.plist "$APP/Contents/Info.plist"
cp Fixtures/sample-bank.json "$APP/Contents/Resources/sample-bank.json"
cp Fixtures/images/dots.png Fixtures/images/bars.png "$APP/Contents/Resources/images/"
codesign --force --sign - "$APP"
echo "已生成 $APP"
