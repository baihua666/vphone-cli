#!/bin/zsh
# Explicit maintenance after publishing; keep Git tags for source provenance.
set -euo pipefail
repo="${0:a:h:h:h:h}"
(( $# == 1 )) || { print -u2 'Usage: prune-releases.zsh VERIFIED_LATEST_TAG'; exit 2; }
tag="$1"
[[ "$tag" == launchpad-* && "$tag" != *[^A-Za-z0-9._-]* ]] || { print -u2 'Invalid release tag'; exit 2; }
cd "$repo"
work=$(mktemp -d "${TMPDIR:-/tmp}/vphone-release-check.XXXXXX")
trap '/bin/rm -r -- "$work"' EXIT
gh release download "$tag" --repo baihua666/vphone-cli --pattern launchpad-catalog.json --dir "$work"
manifest="$work/launchpad-catalog.json"
[[ "$(plutil -extract tag raw -o - "$manifest")" == "$tag" ]] || { print -u2 'Catalog tag mismatch'; exit 1; }
manifest_history=$(plutil -extract previousTags json -o - "$manifest")
[[ "${manifest_history//[[:space:]]/}" == '[]' ]] || { print -u2 'Latest catalog must not reference releases that will be deleted'; exit 1; }
latest=$(gh api repos/baihua666/vphone-cli/releases/latest --jq .tag_name)
[[ "$latest" == "$tag" ]] || { print -u2 'Requested release is not latest'; exit 1; }
args=()
images=$(plutil -extract images json -o - "$manifest")
[[ "${images//[[:space:]]/}" == '[]' ]] || args+=(--include-images)
# Real anonymous downloads, signatures, individual and assembled SHA-256 checks.
swift run --package-path Integrations/Distribution distribution-publisher \
  --check-download "$work/downloads" "${args[@]}"
latest=$(gh api repos/baihua666/vphone-cli/releases/latest --jq .tag_name)
[[ "$latest" == "$tag" ]] || { print -u2 'Latest changed during verification; nothing deleted'; exit 1; }
release_tags=$(gh api --paginate repos/baihua666/vphone-cli/releases --jq '.[] | select(.draft == false) | .tag_name')
tags=("${(@f)release_tags}")
for old in "${tags[@]}"; do
  [[ "$old" == "$tag" || "$old" != launchpad-* ]] && continue
  gh release delete "$old" --repo baihua666/vphone-cli --yes
done
print -- "Retained latest release: $tag. Source tags and installed instances remain intact."
