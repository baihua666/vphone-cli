#!/bin/zsh
# Developer workstation only; identities and team IDs must not be committed.
set -euo pipefail
repo="${0:a:h:h:h:h}"
mode=notarized
if [[ "${1:-}" == --internal ]]; then mode=internalDevelopment; shift; fi
if [[ "$mode" == internalDevelopment ]]; then
  (( $# == 2 )) || { print -u2 'Usage: package-app.zsh --internal REVISION "Apple Development: …"'; exit 2; }
else
  (( $# == 3 )) || { print -u2 'Usage: package-app.zsh REVISION "Developer ID Application: …" NOTARY_KEYCHAIN_PROFILE'; exit 2; }
fi
revision="$1"
identity="$2"
[[ "$revision" == <1-> ]] || { print -u2 'A positive revision is required'; exit 2; }
if [[ "$mode" == internalDevelopment ]]; then
  [[ "$identity" == 'Apple Development: '* ]] || { print -u2 'Internal mode requires Apple Development'; exit 2; }
else
  [[ "$identity" == 'Developer ID Application: '* ]] || { print -u2 'Public mode requires Developer ID Application'; exit 2; }
fi
cd "$repo"
output="$repo/.build/distribution-app-$mode-r$revision"
[[ ! -e "$output" ]] || { print -u2 "Output exists: $output"; exit 1; }
mkdir -p "$output"
# Optional environment override for machines without Developer.xcconfig.
team_args=()
[[ -z "${VPHONE_LAUNCHPAD_TEAM:-}" ]] || team_args+=("VPHONE_LAUNCHPAD_TEAM=$VPHONE_LAUNCHPAD_TEAM")
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj -scheme VPhoneLaunchpad \
  -configuration Release -derivedDataPath "$output/DerivedData" -jobs 4 \
  "VPHONE_DISTRIBUTION_REVISION=$revision" "VPHONE_DISTRIBUTION_SIGNING=$mode" "${team_args[@]}" build
app="$output/DerivedData/Build/Products/Release/vphone-launchpad.app"
if [[ -n "${VPHONE_DECODO_DEFAULTS_DIR:-}" ]]; then
  [[ "$mode" == internalDevelopment ]] || { print -u2 'Account defaults are private internal installers only'; exit 2; }
  # Keep only login/proxy credentials, never copy live tokens or API keys.
  (
    umask 077
    private_defaults="$app/Contents/Resources/DecodoPrivateDefaults"
    mkdir "$private_defaults"
    chmod 755 "$private_defaults"
    xcrun swift - "$VPHONE_DECODO_DEFAULTS_DIR" "$private_defaults" <<'SWIFT'
import Foundation
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
for (name, key) in [("decodo-account.json", "email"), ("decodo-isp.json", "username")] {
    let data = try Data(contentsOf: source.appendingPathComponent(name))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let user = object?[key] as? String, !user.isEmpty,
          let password = object?["password"] as? String, !password.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    let output = try JSONSerialization.data(withJSONObject: [key: user, "password": password])
    guard FileManager.default.createFile(atPath: destination.appendingPathComponent(name).path, contents: output,
                                         attributes: [.posixPermissions: 0o644]) else { throw CocoaError(.fileWriteUnknown) }
}
SWIFT
  )
  print -- 'Private account defaults included. Do not upload this installer to public releases.'
fi
zsh VPhoneLaunchpad/Build/SignLaunchpad.sh "$app" "$identity"
mkdir "$output/image"
ditto "$app" "$output/image/vphone-launchpad.app"
ln -s /Applications "$output/image/Applications"
dmg="$output/vphone-launchpad-$mode-r$revision.dmg"
hdiutil create -volname 'VPhone Launchpad' -srcfolder "$output/image" -format UDZO "$dmg"
codesign --sign "$identity" --timestamp "$dmg"
if [[ "$mode" == notarized ]]; then
  xcrun notarytool submit "$dmg" --keychain-profile "$3" --wait
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
else
  print -- 'Internal development build: not notarized. Gatekeeper may require Open Anyway. Helper authorization remains required.'
fi
print -- "Installer ($mode): $dmg"
