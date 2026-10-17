#!/bin/zsh
# Each 2.x machine's sidecar pins its own host for proxy process-path routing.
set -euo pipefail
ROOT="${0:A:h}"
APP="$ROOT/VPhoneWorkstation/.build/vphone-ws.app"
CLI="$HOME/.vphone/runtimes/source-4a76ffb-20261016/VPhone.bundle/Contents/MacOS/vphone-cli"
LIBRARY="$HOME/.vphone/machines"
[[ -d "$APP" && -x "$CLI" && -d "$LIBRARY" ]] || {
  print -u2 -- 'Workstation、固定新版 CLI 或实例库缺失，请查看 Research/branch_workflow.md'
  exit 1
}
exec /usr/bin/open "$APP" --env "VPHONE_CLI_PATH=$CLI" --env "VPHONE_LIBRARY_ROOT=$LIBRARY"
