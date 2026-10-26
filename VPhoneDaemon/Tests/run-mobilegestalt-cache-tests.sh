#!/bin/zsh
set -euo pipefail
repo="${0:a:h:h:h}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  "$repo/VPhoneDaemon/Daemon/GuestMobileGestaltCache.swift" \
  "$repo/VPhoneDaemon/Tests/GuestMobileGestaltCacheTests.swift" -o "$temporary/tests"
"$temporary/tests" "$repo/VPhoneExecutable/VPhoneCommand/FirmwarePatcher/PatchSets/FirmwareGuestPatchResolution.swift"
