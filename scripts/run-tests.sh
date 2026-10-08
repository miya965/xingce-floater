#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/embed-schema.py
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p build
swiftc \
  -sdk "$SDK" \
  -target x86_64-apple-macos12.0 \
  -framework CryptoKit \
  -lsqlite3 \
  -o build/xingce-tests \
  Sources/XingceCore/*.swift \
  Tests/main.swift
./build/xingce-tests "$(pwd)"
