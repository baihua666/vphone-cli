#!/bin/zsh
set -euo pipefail

# Host development helper: reuse the project's native API client; nothing is installed in the guest.
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vphone-app-install.XXXXXXXX")"
trap 'rm -f "$BUILD_DIR/install-app"; rmdir "$BUILD_DIR"' EXIT
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library \
  "$REPO_ROOT/VPhoneKit/VPhoneExternalAccessKit/VPhoneAPIClient.swift" \
  "$SCRIPT_DIR/InstallApp.swift" -o "$BUILD_DIR/install-app"
"$BUILD_DIR/install-app" "$@"
