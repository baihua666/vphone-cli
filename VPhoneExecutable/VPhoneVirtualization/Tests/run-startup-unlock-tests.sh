#!/bin/zsh
set -euo pipefail
TEST_DIR="${0:A:h}"
SOURCE="${1:-$TEST_DIR/../UI/GuestCommunication/VPhoneGuestControlSystem.swift}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vphone-startup-unlock-tests.XXXXXXXX")"
trap 'rm -f "$BUILD_DIR/tests"; rmdir "$BUILD_DIR"' EXIT
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library \
  "$SOURCE" "$TEST_DIR/StartupUnlockTests.swift" -o "$BUILD_DIR/tests"
"$BUILD_DIR/tests"
