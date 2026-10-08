#!/bin/zsh
# Legacy entry point: the upstream Xcode pipeline no longer exposes EXP variants.
set -euo pipefail
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print -- '旧版 EXP 工作流已停用。当前源码使用 Xcode VPhone scheme 和官方 patch sets/presets。'
  print -- '请参见 Research/branch_workflow.md；旧实现位于 codex/pre-upstream-sync-20261008。'
  exit 0
fi
print -u2 -- '当前源码不支持旧版 EXP 工作流；未构建、恢复、导出或修改任何 VM。'
print -u2 -- '请参见 Research/branch_workflow.md；不要直接把 --variant exp 替换成新 preset。'
exit 2
