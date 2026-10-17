#!/bin/zsh
# Each 2.x machine's sidecar pins its own host for proxy process-path routing.
set -euo pipefail
ROOT="${0:A:h}"
APP="$ROOT/VPhoneWorkstation/.build/vphone-ws.app"
CONFIG="${VPHONE_HOST_CONFIG:-$HOME/.vphone/host-config.zsh}"
if [[ -f "$CONFIG" ]]; then
  source "$CONFIG"
elif [[ -n "${VPHONE_HOST_CONFIG:-}" ]]; then
  print -u2 -- "本机配置不存在：$CONFIG"; exit 1
fi
CLI="${VPHONE_CLI_PATH:-}"
LIBRARY="${VPHONE_LIBRARY_ROOT:-$HOME/.vphone/machines}"
[[ -d "$APP" && -x "$CLI" && -d "$LIBRARY" ]] || {
  print -u2 -- 'Workstation、CLI 或实例库缺失；请先构建 GUI，再按 Documents/Guides/monorepo-development.md 配置本机。'
  exit 1
}
exec open "$APP" --env "VPHONE_CLI_PATH=$CLI" --env "VPHONE_LIBRARY_ROOT=$LIBRARY"
