#!/bin/zsh
set -euo pipefail
daemon="${0:a:h:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-screen-unlock-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
# Keep the real unlock code; replace only its guest-only transport imports.
sed '/^import IcliKit$/d; /^import VphonedNative$/d' \
    "$daemon/Daemon/GuestScreenUnlock.swift" > "$temporary/GuestScreenUnlock.swift"
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    "$temporary/GuestScreenUnlock.swift" "$daemon/Tests/ScreenUnlockTests.swift" \
    -o "$temporary/tests"
"$temporary/tests"
