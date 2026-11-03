#!/bin/zsh
set -euo pipefail
module_dir=${0:a:h}
if (( $# < 1 )); then
  print -u2 '用法: threads.zsh RUN_DIRECTORY [--fresh-login] [--password-stdin]'
  print -u2 '同目录续跑不会重复发布；新目录代表新测试帖。'
  exit 1
fi
run_dir=${1:a}
shift
socket_path="$HOME/.vphone/machines/1-20261023/vphone.sock"
[[ -S "$socket_path" ]] || { print -u2 '请先在 Launchpad 启动 1-20261023'; exit 1; }
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 VPHONE_CUSTOM_THREADS_AUTOMATION=1 swift build --package-path "$module_dir"
exec "$module_dir/.build/debug/instagram-test" threads-e2e "$socket_path" "$run_dir" "$@"
