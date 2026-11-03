#!/bin/zsh
set -euo pipefail
launchpad="${0:a:h:h}"
repo="${launchpad:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-arm-login-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name VPhoneApplicationManagement \
    "$repo"/Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/*.swift \
    -emit-module-path "$temporary/VPhoneApplicationManagement.swiftmodule" \
    -o "$temporary/libVPhoneApplicationManagement.dylib"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -D VPHONE_CUSTOM_APPLICATION_MANAGEMENT \
    -I "$temporary" -L "$temporary" -lVPhoneApplicationManagement -Xlinker -rpath -Xlinker "$temporary" \
    "$launchpad/VPhoneLaunchpad/Applications/VPhoneARMStoreLogin.swift" \
    "$launchpad/Tests/ARMStoreLoginTests.swift" -o "$temporary/tests"
"$temporary/tests"

# Compile the optional private-account branch with inert test values only.
# TestStoreWebView intercepts all loads, so these cannot reach a website.
cat > "$temporary/PresetFixture.swift" <<'SWIFT'
enum VPhonePrivateARMStoreAccount {
    static let account = "fixture@example.invalid"
    static let password = "inert-test-fixture"
}
SWIFT
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -D VPHONE_CUSTOM_APPLICATION_MANAGEMENT -D VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT \
    -I "$temporary" -L "$temporary" -lVPhoneApplicationManagement -Xlinker -rpath -Xlinker "$temporary" \
    "$launchpad/VPhoneLaunchpad/Applications/VPhoneARMStoreLogin.swift" \
    "$temporary/PresetFixture.swift" "$launchpad/Tests/ARMStoreLoginTests.swift" -o "$temporary/preset-tests"
"$temporary/preset-tests"
