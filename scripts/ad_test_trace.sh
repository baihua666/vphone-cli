#!/bin/zsh
# Convenience entry point for the existing test-device evidence collector.
set -euo pipefail
ROOT=${0:A:h:h}
usage() {
  cat <<'HELP'
用法：
  ./scripts/ad_test_trace.sh [rewarded|interstitial] [选项]

  无参数 / rewarded  测试一次激励广告（Orblino 983634549）
  interstitial       测试一次插屏广告（Orblino 983639115）

请先打开 Orblino 广告测试页，选择测试设备验证，让加载按钮可见。
默认 VM：项目 vm；设备：从该 VM 的 udid-prediction.txt 自动匹配。
默认报表时区 UTC，采集 45 秒，证据自动保存在 .build/validation/ad-tests/。

选项：
  --vm PATH           使用另一 VM 目录
  --udid ID           显式指定已连接设备（仍须与 VM 的预测 ID 一致）
  --placement-id ID   覆盖默认广告位（须与页面相符）
  --app-id ID         覆盖 App ID（默认 8895377）
  --timezone NAME    后台时区，例如 Asia/Shanghai
  --seconds N         采集时长，5–300 秒
  --capture-only      只记录人工操作，不自动请求
  --yes               已确认测试设备登记生效及当前页面设置，跳过交互确认
  --dry-run           只预览命令，不采集、不操作 VM
  -h, --help          显示帮助
HELP
}
fail() { print -u2 -- "$*"; exit 1; }
FORMAT=rewarded VM_DIR="$ROOT/vm" DEVICE_ID='' SLOT='' APP_ID=8895377
REPORT_TZ=UTC SECONDS_TO_CAPTURE=45 CAPTURE_ONLY=0 CONFIRMED=0 PREVIEW=0
if [[ ${1:-} == rewarded || ${1:-} == interstitial ]]; then FORMAT=$1; shift; fi
while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --capture-only) CAPTURE_ONLY=1; shift ;;
    --yes) CONFIRMED=1; shift ;;
    --dry-run) PREVIEW=1; shift ;;
    --vm|--udid|--placement-id|--app-id|--timezone|--seconds)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != -* ]] || fail "缺少参数值：$1"
      case "$1" in
        --vm) VM_DIR=${2:a} ;;
        --udid) DEVICE_ID=$2 ;;
        --placement-id) SLOT=$2 ;;
        --app-id) APP_ID=$2 ;;
        --timezone) REPORT_TZ=$2 ;;
        --seconds) SECONDS_TO_CAPTURE=$2 ;;
      esac
      shift 2 ;;
    *) fail "未知参数：$1；使用 --help 查看用法" ;;
  esac
done
[[ "$SECONDS_TO_CAPTURE" == <5-300> ]] || fail '--seconds 必须为 5–300 的整数'
[[ -S "$VM_DIR/vphone.sock" ]] || fail "VM 未运行或 socket 不存在：$VM_DIR/vphone.sock"
command -v python3 >/dev/null || fail '缺少 python3'
command -v idevice_id >/dev/null || fail '缺少 idevice_id，请先安装项目工具依赖'
PREDICTED_ID=''
if [[ -f "$VM_DIR/udid-prediction.txt" ]]; then
  PREDICTED_ID=$(python3 - "$VM_DIR/udid-prediction.txt" <<'PY'
from pathlib import Path
import sys
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.startswith('UDID='):
        print(line.partition('=')[2].strip())
        break
PY
)
fi
if [[ -n "$DEVICE_ID" && -n "$PREDICTED_ID" && "$DEVICE_ID" != "$PREDICTED_ID" ]]; then
  fail '指定 UDID 与 VM 预测 ID 不一致，未执行测试'
fi
DEVICE_ID=${DEVICE_ID:-$PREDICTED_ID}
[[ -n "$DEVICE_ID" ]] || fail 'VM 缺少预测 ID；核对设备后用 --udid 显式指定'
typeset -a CONNECTED
CONNECTED=("${(@f)$(idevice_id -l)}")
(( ${CONNECTED[(Ie)$DEVICE_ID]} )) || fail "目标 VM 未通过 USB 配对连接：$DEVICE_ID"
if [[ -z "$SLOT" ]]; then
  if [[ "$FORMAT" == rewarded ]]; then SLOT=983634549; else SLOT=983639115; fi
fi
# UUID avoids overwriting evidence even for concurrent invocations in one second.
RUN_ID=$(python3 -c 'from datetime import datetime; import uuid; print(datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])')
OUTPUT="$ROOT/.build/validation/ad-tests/$RUN_ID-$FORMAT"
typeset -a ARGS
ARGS=(python3 "$ROOT/scripts/ad_test_trace.py" --socket "$VM_DIR/vphone.sock"
  --udid "$DEVICE_ID" --output "$OUTPUT" --format "$FORMAT" --app-id "$APP_ID"
  --placement-id "$SLOT" --report-timezone "$REPORT_TZ" --seconds "$SECONDS_TO_CAPTURE")
if (( ! CAPTURE_ONLY )); then ARGS+=(--request --test-device-confirmed); fi
print -- "VM: $VM_DIR | $FORMAT | 广告位: $SLOT | 时区: $REPORT_TZ"
print -- "设备: $DEVICE_ID"
print -- "结果: $OUTPUT"
if (( PREVIEW )); then printf '%q ' "${ARGS[@]}"; printf '\n'; exit 0; fi
if (( ! CAPTURE_ONLY && ! CONFIRMED )); then
  [[ -t 0 ]] || fail '非交互运行需 --yes 明确确认测试设备，或使用 --capture-only'
  read -r 'ANSWER?已确认测试设备登记生效、页面为测试模式且加载按钮可见？[y/N] '
  [[ "$ANSWER" == y || "$ANSWER" == Y ]] || fail '已取消，未操作 VM'
fi
exec "${ARGS[@]}"
