#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-creation-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    "$launchpad/VPhoneLaunchpad/IPSWCache/VPhoneLaunchpadIPSW.swift" \
    "$launchpad/VPhoneLaunchpad/Machines/VPhoneLaunchpadTemplates.swift" \
    "$launchpad/VPhoneLaunchpad/Machines/VPhoneLaunchpadCreationPlan.swift" \
    "$launchpad/VPhoneLaunchpad/Machines/VPhoneLaunchpadCreationPipeline.swift" \
    "$launchpad/VPhoneLaunchpad/Business/DeviceInitialization/VPhoneLaunchpadDeviceInitializationAdapter.swift" \
    "$launchpad/Tests/CreationInitializationTests.swift" -o "$temporary/tests"
"$temporary/tests"
