#!/bin/zsh
set -euo pipefail
module_dir=${0:a:h}
if (( $# < 1 )); then
  print -u2 '用法: run.zsh RUN_DIRECTORY [--password-login | --fresh-login] [--password-stdin]'
  print -u2 '同一任务重试必须使用相同目录；新目录会创建新测试帖子。'
  exit 1
fi
run_dir=${1:a}
shift
socket_path="$HOME/.vphone/machines/1-20261023/vphone.sock"
if [[ ! -S "$socket_path" ]]; then
  print -u2 '请先在 Launchpad 启动 1-20261023；本脚本不修改实例绑定或 Core。'
  exit 1
fi
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 swift build --package-path "$module_dir"
exec "$module_dir/.build/debug/instagram-test" e2e "$socket_path" "$run_dir" "$@"
