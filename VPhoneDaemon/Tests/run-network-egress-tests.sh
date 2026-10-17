#!/bin/zsh
set -euo pipefail
daemon="${0:a:h:h}"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-egress-tests.XXXXXX")"
trap 'rm -f "$temporary/tests"; rmdir "$temporary"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
    "$daemon/Daemon/GuestNetworkEgress.swift" "$daemon/Tests/NetworkEgressTests.swift" \
    -o "$temporary/tests"
"$temporary/tests"
