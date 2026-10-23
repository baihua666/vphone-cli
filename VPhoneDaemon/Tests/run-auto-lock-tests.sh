#!/bin/zsh
set -euo pipefail
daemon="${0:a:h:h}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.managedconfiguration.feature-setting.maxInactivity' "$daemon/Configuration/VPhoneDaemon.entitlements")" == true ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.private.xpc.service-configure' "$daemon/Configuration/VPhoneDaemon.entitlements")" == true ]]
temporary="$(mktemp -d "${TMPDIR:-/tmp}/vphone-auto-lock-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
xcrun --sdk macosx clang -fobjc-arc -framework Foundation \
    -Ddlopen=vp_test_dlopen -Ddlsym=vp_test_dlsym \
    "$daemon/Native/vphoned_auto_lock.m" "$daemon/Tests/AutoLockTests.m" \
    -o "$temporary/tests"
"$temporary/tests"
