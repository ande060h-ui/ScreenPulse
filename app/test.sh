#!/bin/zsh
# Compiles and runs the unit tests for app/Sources/Core (no hardware or permissions needed).
set -e
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 app/Sources/Core/*.swift app/Tests/main.swift -o "$TMP/tests"
"$TMP/tests"
