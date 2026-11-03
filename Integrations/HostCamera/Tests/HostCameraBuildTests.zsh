#!/bin/zsh
set -euo pipefail
module="${0:a:h:h}"
repo="${module:h:h}"
source "$module/Build/HostCameraBuild.zsh"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/vphone-host-camera-build-tests.XXXXXXXX")
trap 'rm -rf "$scratch"' EXIT
info="$scratch/Info.plist"
entitlements="$scratch/generated.entitlements"
base="$repo/VPhoneLaunchpad/Resources/VPhoneLaunchpad.entitlements"
cp /usr/bin/true "$scratch/probe"
for variant in enabled disabled; do
    flag=''
    [[ "$variant" == disabled ]] || flag=VPHONE_EXPERIMENTAL_HOST_CAMERA
    if [[ "$variant" == enabled ]]; then
        cp "$repo/VPhoneExecutable/VPhoneVirtualization/Resources/Info.plist" "$info"
    fi
    # Reuse the enabled output in the disabled pass: a rebuild must remove stale permission resources.
    vphone_host_camera_prepare_bundle "$info" "$flag"
    vphone_host_camera_entitlements "$info" "$base" "$entitlements"
    codesign --force --sign - --entitlements "$entitlements" "$scratch/probe" 2>/dev/null
    vphone_host_camera_validate "$info" "$scratch/probe"
    [[ "$(plutil -extract 'com\.apple\.security\.device\.audio-input' raw -o - "$entitlements")" == true ]]
    [[ "$(plutil -extract 'com\.apple\.security\.personal-information\.location' raw -o - "$entitlements")" == true ]]
    if [[ "$variant" == enabled ]]; then
        [[ "$(plutil -extract 'com\.apple\.security\.device\.camera' raw -o - "$entitlements")" == true ]]
    else
        if plutil -extract NSCameraUsageDescription raw -o - "$info" >/dev/null 2>&1; then
            print -u2 'Disabled build kept its camera usage description'; exit 1
        fi
        if plutil -extract 'com\.apple\.security\.device\.camera' raw -o - "$entitlements" >/dev/null 2>&1; then
            print -u2 'Disabled build kept its camera entitlement'; exit 1
        fi
    fi
done
if vphone_host_camera_prepare_bundle "$info" 0 2>/dev/null; then
    print -u2 'An invalid macro value was accepted'; exit 1
fi
for variant in disabled enabled; do
    definitions=()
    [[ "$variant" == disabled ]] || definitions=(-D VPHONE_EXPERIMENTAL_HOST_CAMERA)
    xcrun clang -E -P -traditional-cpp -Wno-invalid-pp-token -Werror -x c "${definitions[@]}" \
        "$repo/VPhoneLaunchpad/Resources/VPhoneLaunchpad.Info.plist" > "$scratch/launchpad-$variant.plist"
    plutil -lint "$scratch/launchpad-$variant.plist" >/dev/null
    expected=false
    vphone_host_camera_enabled "$scratch/launchpad-$variant.plist" && expected=true
    [[ "$expected" == "$([[ "$variant" == enabled ]] && print true || print false)" ]]
done
print 'PASS: enabled/disabled signed entitlements, stale permission removal, baseline permission preservation and Launchpad metadata'
