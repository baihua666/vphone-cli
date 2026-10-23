#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-device-policy-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    "$launchpad/VPhoneLaunchpad/Business/DeviceInitialization/VPhoneDeviceInitialization.swift" \
    "$launchpad/Tests/DeviceInitializationTests.swift" -o "$temporary/tests"
"$temporary/tests"
