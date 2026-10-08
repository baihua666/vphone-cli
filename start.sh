#!/bin/zsh
# Launch the official baseline or the local customized VM without rebuilding.
set -euo pipefail

ROOT="${0:A:h}"
if (( $# > 1 )); then
  print -u2 -- '用法：./start.sh [official|custom|1|2]（默认 official）'
  exit 2
fi
case "${1:-official}" in
  official|1)
    CLI="$HOME/.vphone/runtimes/upstream-1.0.14/vphone-cli.app/Contents/MacOS/vphone-cli"
    LIBRARY="$HOME/.vphone/VMs"
    VM_NAME=stock-regular-guard-20261008
    VARIANT=regular
    ;;
  custom|2)
    CLI="$ROOT/.build/vphone-cli.app/Contents/MacOS/vphone-cli"
    LIBRARY="$ROOT"
    VM_NAME=vm-fresh
    VARIANT=exp
    ;;
  -h|--help)
    print -- '用法：./start.sh [official|custom|1|2]（默认 official）'
    print -- '1/official：官方 1.0.14 Regular + 官方 force-exc-guard'
    print -- '2/custom：本地构建 + 现有 vm-fresh EXP；不会自动重刷固件'
    exit 0
    ;;
  *) print -u2 -- '请选择 official/1 或 custom/2'; exit 2 ;;
esac

[[ -x "$CLI" ]] || { print -u2 -- "运行程序不存在：$CLI；official 请恢复已校验官方发布包，custom 请运行 ./scripts/build.sh"; exit 1; }
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

print -- "启动 ${1:-official}：$VM_NAME（$VARIANT）"
exec "$CLI" vm launch "$VM_NAME" --library-root "$LIBRARY" --variant "$VARIANT"
