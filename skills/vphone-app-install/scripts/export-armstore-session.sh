#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vphone-armstore-session.XXXXXXXX")"
trap 'rm -f "$BUILD_DIR/export-session"; rmdir "$BUILD_DIR"' EXIT
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library "$SCRIPT_DIR/ExportARMStoreSession.swift" -o "$BUILD_DIR/export-session"
"$BUILD_DIR/export-session" "$@"
