#!/bin/zsh
# Build-only helpers: source this file; it never starts a camera or touches an installed app.

vphone_host_camera_prepare_bundle() {
    local info=$1 flag=$2
    /usr/bin/plutil -lint "$info" >/dev/null
    case "$flag" in
        '')
            /usr/bin/plutil -remove NSCameraUsageDescription "$info" 2>/dev/null || true
            /usr/bin/plutil -remove VPhoneHostCameraEnabled "$info" 2>/dev/null || true
            ;;
        VPHONE_EXPERIMENTAL_HOST_CAMERA)
            /usr/bin/plutil -replace VPhoneHostCameraEnabled -bool true "$info"
            /usr/bin/plutil -replace NSCameraUsageDescription -string \
                "Shares the selected Mac camera with the virtual iPhone only while camera streaming is on." "$info"
            ;;
        *) print -u2 'Invalid VPHONE_HOST_CAMERA; use an empty value or VPHONE_EXPERIMENTAL_HOST_CAMERA'; return 1 ;;
    esac
}

vphone_host_camera_enabled() {
    local value
    value=$(/usr/bin/plutil -extract VPhoneHostCameraEnabled raw -o - "$1" 2>/dev/null) || return 1
    [[ "$value" == true ]]
}

vphone_host_camera_entitlements() {
    local info=$1 base=$2 output=$3
    /bin/mkdir -p "${output:h}"
    /bin/cp "$base" "$output"
    if vphone_host_camera_enabled "$info"; then
        /usr/bin/plutil -replace 'com\.apple\.security\.device\.camera' -bool true "$output"
    else
        /usr/bin/plutil -remove 'com\.apple\.security\.device\.camera' "$output" 2>/dev/null || true
    fi
}

vphone_host_camera_validate() {
    local info=$1 executable=$2 signed usage
    signed=$(/usr/bin/codesign -d --entitlements - --xml "$executable" 2>/dev/null)
    if vphone_host_camera_enabled "$info"; then
        usage=$(/usr/bin/plutil -extract NSCameraUsageDescription raw -o - "$info")
        [[ -n "$usage" && "$signed" == *'<key>com.apple.security.device.camera</key><true/>'* ]] || {
            print -u2 'Enabled host camera build is missing camera usage description or entitlement'; return 1
        }
    else
        [[ "$signed" != *'<key>com.apple.security.device.camera</key>'* ]] || {
            print -u2 'Disabled host camera build still has a camera entitlement'; return 1
        }
    fi
}
