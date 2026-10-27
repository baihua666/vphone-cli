#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library -D VPHONE_CUSTOM_DISTRIBUTION -D VPHONE_CUSTOM_APP_UPDATE \
  "$launchpad/VPhoneLaunchpad/Distribution/AppUpdate/VPhoneLaunchpadAppUpdate.swift" \
  "$launchpad/VPhoneLaunchpad/Distribution/AppUpdate/VPhoneLaunchpadAppUpdateInstaller.swift" \
  "$launchpad/Tests/AppUpdateTests.swift" -o "$temporary/tests"
"$temporary/tests" "${1:?signed DMG}" "${2:?installed App}" "${3:-6}"
