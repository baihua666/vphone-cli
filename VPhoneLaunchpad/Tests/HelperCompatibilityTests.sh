#!/bin/zsh
set -euo pipefail

launchpad="${0:a:h:h}"
temporary="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$temporary"' EXIT

# Real signed Mach-O fixtures exercise the production signature and plist reads.
fixture() {
    local name="$1" version="$2" result="$3"
    cat > "$temporary/info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vphone.test.helper</string>
<key>CFBundleVersion</key><string>$version</string>
</dict></plist>
PLIST
    print -r -- "int main(void) { return $result; }" > "$temporary/helper.c"
    /usr/bin/xcrun clang "$temporary/helper.c" \
        -Wl,-sectcreate,__TEXT,__info_plist,"$temporary/info.plist" -o "$temporary/$name"
    /usr/bin/codesign --force --sign - --identifier com.vphone.test.helper "$temporary/$name" 2>/dev/null
}
fixture legacy 15 0
fixture old 20 0
fixture current 21 0
fixture rebuilt 21 1
fixture newer 27 0
fixture malformed 21-local 0

/usr/bin/xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    -parse-as-library \
    "$launchpad/VPhoneLaunchpadShared/VPhoneLaunchpadHelperProtocol.swift" \
    "$launchpad/VPhoneLaunchpad/HostSetup/VPhoneLaunchpadHelperCompatibility.swift" \
    "$launchpad/VPhoneLaunchpad/HostSetup/VPhoneLaunchpadHelperClient.swift" \
    "$launchpad/VPhoneLaunchpad/HostSetup/VPhoneLaunchpadHelperInstallation.swift" \
    "$launchpad/Tests/HelperCompatibilityTests.swift" -o "$temporary/helper-tests"
"$temporary/helper-tests" "$temporary"

# Optional delivery check: passing source tests is not enough when the updater
# ships a different executable. Inspect compiled code, not translated resources.
if (( $# > 0 )); then
    app="$1"
    /usr/bin/codesign --verify --strict --deep "$app"
    if ! /usr/bin/strings "$app/Contents/MacOS/vphone-launchpad" \
        | /usr/bin/grep -F 'The installed helper is the same version or newer. It has not been replaced.' >/dev/null; then
        print -u2 -- 'FAIL: App executable does not contain the helper compatibility/downgrade guard'
        exit 1
    fi
    print -- 'App delivery check passed: signed executable contains the helper compatibility/downgrade guard'
fi
