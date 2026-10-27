#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vphone-armstore.XXXXXXXX")"
trap 'rm -f "$BUILD_DIR/download"; rmdir "$BUILD_DIR"' EXIT
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library "$SCRIPT_DIR/DownloadARMStore.swift" "$SCRIPT_DIR/../../../Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/ARMStore.swift" "$SCRIPT_DIR/../../../Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/ARMStoreSession.swift" -o "$BUILD_DIR/download"
"$BUILD_DIR/download" "$@"
