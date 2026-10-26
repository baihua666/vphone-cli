#!/bin/zsh
set -euo pipefail
repo="${0:a:h:h:h}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
sources=("$repo"/Integrations/Distribution/Sources/VPhoneDistribution/*.swift)
xcrun swiftc -swift-version 6 -parse-as-library -emit-library -emit-module \
  -module-name VPhoneDistribution "${sources[@]}" -emit-module-path "$temporary/VPhoneDistribution.swiftmodule" \
  -o "$temporary/libVPhoneDistribution.dylib"
for mode in manual automatic; do
  flags=()
  [[ "$mode" != automatic ]] || flags=(-D VPHONE_CUSTOM_APP_UPDATE)
  xcrun swiftc -swift-version 6 -parse-as-library -D VPHONE_CUSTOM_DISTRIBUTION "${flags[@]}" \
    -I "$temporary" -L "$temporary" -lVPhoneDistribution -Xlinker -rpath -Xlinker "$temporary" \
    "$repo/VPhoneLaunchpad/VPhoneLaunchpad/Distribution/AppUpdate/VPhoneLaunchpadAppUpdateModel.swift" \
    "$repo/VPhoneLaunchpad/Tests/AppUpdateModelTests.swift" -o "$temporary/tests"
  "$temporary/tests" "${1:?release catalog fixture}"
done
