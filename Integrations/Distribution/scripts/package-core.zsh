#!/bin/zsh
# Archive an existing approved bundle without rebuilding, resigning or installing it.
set -euo pipefail
(( $# == 2 )) || { print -u2 'Usage: package-core.zsh /path/VPhone.bundle /new/output-directory'; exit 2; }
bundle="${1:a}"
output="${2:a}"
[[ "${bundle:t}" == VPhone.bundle && -d "$bundle" && ! -e "$output" ]] || { print -u2 'Expected VPhone.bundle and a new output directory'; exit 2; }
codesign --verify --strict --deep "$bundle"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$bundle/Contents/Info.plist")
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid baseline'; exit 1; }
seal="$bundle/Contents/_CodeSignature/CodeResources"
[[ -s "$seal" ]] || { print -u2 'An intact signature seal is required for a release bundle'; exit 1; }
hash=$(shasum -a 256 "$seal")
core_identity="$version-local.${hash[1,8]}"
mkdir -p "$output"
ditto -c -k --keepParent "$bundle" "$output/VPhone-$core_identity.zip"
print -- "Core identity: $core_identity"
print -- "Archive: $output/VPhone-$core_identity.zip"
