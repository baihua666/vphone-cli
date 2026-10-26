#!/bin/zsh
# Upload only a prepared, validated directory. Default is an unpublished draft.
set -euo pipefail
repo="${0:a:h:h:h:h}"
(( $# == 2 )) || { print -u2 'Usage: publish-release.zsh /prepared/output FULL_COMMIT_SHA'; exit 2; }
output="${1:a}"
commit="$2"
[[ "$commit" =~ '^[a-f0-9]{40}$' ]] || { print -u2 'Use an exact source commit SHA'; exit 2; }
cd "$repo"
swift run --package-path Integrations/Distribution distribution-publisher --verify "$output"
manifest="$output/launchpad-catalog.json"
tag=$(plutil -extract tag raw -o - "$manifest")
notes="$output/release-notes.md"
[[ -f "$notes" ]] || { print -u2 'Add reviewed release-notes.md describing validation, known limits and image provenance'; exit 2; }
# Refuse replacement of an existing tag: revisions are immutable.
if gh release view "$tag" --repo baihua666/vphone-cli >/dev/null 2>&1; then
  print -u2 'Release already exists; use a new revision instead of replacing assets'; exit 1
fi
app_asset=$(plutil -extract app.asset.name raw -o - "$manifest")
core_asset=$(plutil -extract core.asset.name raw -o - "$manifest")
assets=("$manifest" "$output/$app_asset" "$output/$core_asset")
gh release create "$tag" --repo baihua666/vphone-cli --target "$commit" \
  --draft --title "VPhone Launchpad $tag" --notes-file "$notes" "${assets[@]}"
print -- 'Draft uploaded. Review actual artifacts and validation, then publish explicitly. Clients ignore drafts and prereleases.'
