#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
OUT="$ROOT/.build/validation/guest-probe"
APP="$OUT/Payload/TBGuestProbe.app"
mkdir -p "$APP"
xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 \
  -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
  "$ROOT/tests/guest_probe/main.m" -o "$APP/TBGuestProbe" \
  -framework Foundation -framework UIKit -framework CoreGraphics
python3 - "$APP" "$ROOT/tests/guest_probe/main.m" <<'PY'
import hashlib, pathlib, plistlib, sys
app, source = map(pathlib.Path, sys.argv[1:])
info = dict(CFBundleExecutable='TBGuestProbe', CFBundleIdentifier='com.tb.vphone.guestprobe',
            CFBundleName='TBGuestProbe', CFBundleDisplayName='VPHONE Probe',
            CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0',
            MinimumOSVersion='15.0', LSRequiresIPhoneOS=True, UIDeviceFamily=[1, 2],
            UILaunchScreen={}, UIFileSharingEnabled=True,
            TBProbeSourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest())
(app / 'Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$APP"
# Fresh archive avoids retaining removed files from an earlier build.
python3 - "$OUT" <<'PY'
import pathlib, sys, zipfile
out = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(out / 'TBGuestProbe.ipa', 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted((out / 'Payload').rglob('*')):
        if p.is_file(): z.write(p, p.relative_to(out))
print(out / 'TBGuestProbe.ipa')
PY
