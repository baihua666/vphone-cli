#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
repo="${launchpad:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-install-memory-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name VPhoneApplicationManagement \
    "$repo"/Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/*.swift \
    -emit-module-path "$temporary/VPhoneApplicationManagement.swiftmodule" \
    -o "$temporary/libVPhoneApplicationManagement.dylib"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -D VPHONE_CUSTOM_APPLICATION_MANAGEMENT -D VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY \
    -I "$temporary" -L "$temporary" -lVPhoneApplicationManagement -Xlinker -rpath -Xlinker "$temporary" \
    "$launchpad/VPhoneLaunchpad/Applications/VPhoneLaunchpadInstallMemory.swift" \
    "$launchpad/Tests/InstallMemoryRecoveryTests.swift" -o "$temporary/tests"
"$temporary/tests"
