#!/bin/zsh
set -euo pipefail
owner="${0:a:h:h}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  "$owner/VPhoneCommand/Customizations/LegacyGuestRepair/VPhoneLegacyGuestRepairHooks.swift" \
  "$owner/Tests/LegacyGuestRepairHooksDisabledTests.swift" -o "$temporary/tests"
"$temporary/tests"
