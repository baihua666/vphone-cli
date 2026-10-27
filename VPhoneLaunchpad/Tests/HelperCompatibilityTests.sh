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
fixture old 14 0
fixture current 15 0
fixture rebuilt 15 1
fixture newer 21 0
fixture malformed 15-local 0

/usr/bin/xcrun swiftc -swift-version 6 -strict-concurrency=complete \
    -parse-as-library \
    "$launchpad/VPhoneLaunchpadShared/VPhoneLaunchpadHelperProtocol.swift" \
    "$launchpad/VPhoneLaunchpad/HostSetup/VPhoneLaunchpadHelperCompatibility.swift" \
    "$launchpad/VPhoneLaunchpad/HostSetup/VPhoneLaunchpadHelperClient.swift" \
    "$launchpad/VPhoneLaunchpad/HostSetup/VPhoneLaunchpadHelperInstallation.swift" \
    "$launchpad/Tests/HelperCompatibilityTests.swift" -o "$temporary/helper-tests"
"$temporary/helper-tests" "$temporary"
