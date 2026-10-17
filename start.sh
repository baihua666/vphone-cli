#!/bin/zsh
# Launch through this Mac's explicitly configured runtime.
set -euo pipefail

if (( $# > 1 )); then
  print -u2 -- '用法：./start.sh [official|custom|1|2]（默认 official）'
  exit 2
fi
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  print -- '用法：./start.sh [official|custom|1|2]（默认 official）'
  print -- '请在 ~/.vphone/host-config.zsh 配置本机宿主和实例别名。'
  exit 0
fi
CONFIG="${VPHONE_HOST_CONFIG:-$HOME/.vphone/host-config.zsh}"
if [[ -f "$CONFIG" ]]; then
  source "$CONFIG"
elif [[ -n "${VPHONE_HOST_CONFIG:-}" ]]; then
  print -u2 -- "本机配置不存在：$CONFIG"; exit 1
fi
LIBRARY="${VPHONE_LIBRARY_ROOT:-$HOME/.vphone/machines}"
case "${1:-official}" in
  official|1)
    CLI="${VPHONE_OFFICIAL_CLI:-${VPHONE_CLI_PATH:-}}"
    VM_NAME="${VPHONE_OFFICIAL_NAME:-official}"
    ;;
  custom|2)
    CLI="${VPHONE_CUSTOM_CLI:-${VPHONE_CLI_PATH:-}}"
    VM_NAME="${VPHONE_CUSTOM_NAME:-custom}"
    ;;
  *) print -u2 -- '请选择 official/1 或 custom/2'; exit 2 ;;
esac

[[ -n "$CLI" && -x "$CLI" ]] || { print -u2 -- '请在本机配置中设置可执行的 VPHONE_CLI_PATH 或对应别名的 CLI 路径。'; exit 1; }
[[ -f "$LIBRARY/$VM_NAME/config.plist" ]] || { print -u2 -- "实例不存在：$VM_NAME"; exit 1; }
for file in Disk.img nvram.bin SEPStorage; do
  if [[ ! -r "$LIBRARY/$VM_NAME/$file" || ! -w "$LIBRARY/$VM_NAME/$file" ]]; then
    print -u2 -- "当前用户无法读写：$LIBRARY/$VM_NAME/$file"
    print -u2 -- '请检查该文件的属主和权限；不要用 sudo 启动整个虚拟机。'
    exit 1
  fi
done
if /usr/sbin/lsof -t -- "$LIBRARY/$VM_NAME/Disk.img" >/dev/null 2>&1; then
  print -u2 -- "$VM_NAME 的磁盘正在被使用，请先关闭对应实例再启动。"
  exit 1
fi

print -- "启动 ${1:-official}：$VM_NAME（新版固定宿主）"
exec "$CLI" vm launch "$VM_NAME" --library-root "$LIBRARY"
