#!/bin/zsh
set -euo pipefail
module="${0:a:h}"
repo="${module:h:h}"
output="$repo/.build/host-camera-tests"
mkdir -p "$output"
sources=("$module"/VPhoneHostCamera/*.swift)
tests=("$module"/Tests/*.swift)
flags=(-swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -target arm64-apple-macosx15.0)
xcrun swiftc "${flags[@]}" "${sources[@]}" "${tests[@]}" -o "$output/disabled"
"$output/disabled"
symbols=$(nm "$output/disabled")
if [[ "$symbols" == *VPhoneHostCamera* || "$symbols" == *AVCapture* ]]; then
    print -u2 'Disabled build contains host camera code'; exit 1
fi
xcrun swiftc "${flags[@]}" -D VPHONE_EXPERIMENTAL_HOST_CAMERA \
    "${sources[@]}" "${tests[@]}" -o "$output/enabled-tests"
"$output/enabled-tests"
owner="$repo/VPhoneExecutable/VPhoneVirtualization/UI"
integration_sources=("${sources[@]}" "$module"/VPhoneHostCamera/Adapters/*.swift
    "$owner/HostDevices/VPhoneFrameProducer.swift" "$owner/HostDevices/VPhoneCameraServer.swift"
    "$owner/UserInterface/Menu/VPhoneMenuCamera.swift" "$owner/UserInterface/VPhoneLocalization.swift"
    "$owner/UserInterface/VPhoneAlert.swift" "$module"/Tests/Integration/*.swift)
for variant in disabled enabled; do
    definitions=()
    [[ "$variant" == disabled ]] || definitions=(-D VPHONE_EXPERIMENTAL_HOST_CAMERA)
    xcrun swiftc "${flags[@]}" "${definitions[@]}" "${integration_sources[@]}" -o "$output/integration-$variant"
    "$output/integration-$variant"
done
zsh "$module/Tests/HostCameraBuildTests.zsh"
