#!/bin/zsh
set -euo pipefail
repo="${0:a:h:h:h:h}"
fixture="${1:?existing legacy release directory}"
fixture="${fixture:a}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir "$temporary/bin"
cat > "$temporary/bin/gh" <<'GH'
#!/bin/zsh
print called > "$VPHONE_TEST_NETWORK_MARKER"
exit 99
GH
chmod 700 "$temporary/bin/gh"
export VPHONE_TEST_NETWORK_MARKER="$temporary/network-called"
if PATH="$temporary/bin:$PATH" zsh "$repo/Integrations/Distribution/scripts/publish-release.zsh" "$fixture" 1111111111111111111111111111111111111111 > "$temporary/output" 2>&1; then
    print -u2 'FAIL: legacy image release accepted'; exit 1
fi
[[ ! -e "$VPHONE_TEST_NETWORK_MARKER" ]]
rg -q '禁止发布镜像|禁止镜像' "$temporary/output"
print 'PASS: image publication rejected before any gh/network upload command'
