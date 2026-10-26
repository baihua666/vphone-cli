#!/bin/zsh
set -euo pipefail
repo="${0:a:h:h:h}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
for mode in enabled disabled; do
    flags=()
    [[ "$mode" != enabled ]] || flags=(-D VPHONE_CUSTOM_LEGACY_GUEST_REPAIR)
    xcrun swiftc -swift-version 6 -parse-as-library "${flags[@]}" \
      "$repo/VPhoneDaemon/Daemon/GuestMobileGestaltCache.swift" \
      "$repo/VPhoneDaemon/Daemon/Customizations/LegacyGuestRepair/GuestLegacyGuestRepairHooks.swift" \
      "$repo/VPhoneDaemon/Tests/GuestMobileGestaltCacheTests.swift" -o "$temporary/tests"
    "$temporary/tests" "$repo/VPhoneExecutable/VPhoneCommand/FirmwarePatcher/Customizations/LegacyGuestRepair/FirmwareLegacyGuestRepair.swift"
done
