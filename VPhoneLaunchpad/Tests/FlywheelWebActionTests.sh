#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
products="${1:-$launchpad/../.build/FlywheelLaunchpad/Build/Products/Debug}"
derived="${products:h:h:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-flywheel-web-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
# Build Launchpad first; link its actual package products, replacing only app/transport boundaries.
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -target arm64-apple-macos15.0 -I "$products" \
    -I "$derived/SourcePackages/checkouts/Yams/Sources/CYaml/include" \
    "$products/VPhoneFlywheel.o" "$products/VPhoneWSCore.o" "$products/Yams.o" "$products/CYaml.o" \
    "$launchpad/VPhoneLaunchpad/Flywheel/VPhoneLaunchpadFlywheelGuest.swift" \
    "$launchpad/VPhoneLaunchpad/Flywheel/VPhoneLaunchpadFlywheelNetwork.swift" \
    "$launchpad/VPhoneLaunchpad/Flywheel/VPhoneLaunchpadFlywheelWebAction.swift" \
    "$launchpad/Tests/FlywheelWebActionTests.swift" -o "$temporary/tests"
"$temporary/tests"
