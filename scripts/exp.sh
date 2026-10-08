#!/bin/zsh
# Thin wrapper: source build → official EXP creation → official VM export.
set -euo pipefail
ROOT="${0:A:h:h}"
CLI="$ROOT/.build/vphone-cli.app/Contents/MacOS/vphone-cli"
usage() {
  cat <<'HELP'
Usage:
  scripts/exp.sh prepare NAME [--force-exc-guard] [--dry-run] [fw prepare options]
  scripts/exp.sh create NAME OUTPUT.tzst [vm create options]
  scripts/exp.sh export NAME OUTPUT.tzst

prepare: build source, create a NEW empty VM, prepare pristine firmware, patch EXP.
         Stops BEFORE DFU restore. --force-exc-guard enables the official patch.
         --dry-run prints commands without building or changing a VM.
create: compile current source with build.sh, create a NEW EXP VM, export it.
        Official 1.0.14 create does not support --force-exc-guard; use prepare.
export: export an existing stopped VM using the already-built official CLI.
Set VPHONE_LIBRARY_ROOT for a non-default VM library (default ~/.vphone/VMs).
Firmware selection uses official --iphone-source / --cloudos-source or prompts.
Creation may ask for sudo. Existing VMs are never replaced; stop before export.
The archive includes guest data. This exports a VM bundle, not a universal IPSW.
HELP
}
fail() { print -u2 -- "$*"; exit 1; }
if [[ ${1:-} == -h || ${1:-} == --help ]]; then usage; exit 0; fi
LIBRARY="${VPHONE_LIBRARY_ROOT:-${VPHONE_ROOT:-$HOME/.vphone}/VMs}"
LIBRARY=${LIBRARY:a}
# Keep manual firmware preparation separate from restore (which replaces guest data).
if [[ ${1:-} == prepare ]]; then
  (( $# >= 2 )) || { usage; exit 2; }
  VM_NAME=$2
  shift 2
  [[ -n "$VM_NAME" && "$VM_NAME" != .* && "$VM_NAME" != */* && "$VM_NAME" != -* ]] || fail 'Invalid VM name'
  [[ ! -e "$LIBRARY/$VM_NAME" ]] || fail "VM already exists: $LIBRARY/$VM_NAME"
  typeset -a prepare_args patch_args
  prepare_args=() patch_args=()
  dry_run=0
  while (( $# )); do
    case "$1" in
      --force-exc-guard) patch_args=(--force-exc-guard); shift ;;
      --dry-run) dry_run=1; shift ;;
      --iphone-source|--cloudos-source|--iphone-version|--iphone-build)
        (( $# >= 2 )) && [[ -n "$2" && "$2" != -* ]] || fail "Missing value for $1"
        prepare_args+=("$1" "$2"); shift 2 ;;
      *) fail "Unsupported prepare option: $1 (see --help)" ;;
    esac
  done
  run() {
    if (( dry_run )); then
      printf '%q ' "$@"; printf '\n'
    else
      "$@"
    fi
  }
  run "$ROOT/scripts/build.sh"
  run "$CLI" vm new "$VM_NAME" --library-root "$LIBRARY"
  run "$CLI" fw prepare "$VM_NAME" --library-root "$LIBRARY" "${prepare_args[@]}"
  run "$CLI" fw patch "$VM_NAME" --library-root "$LIBRARY" --variant exp "${patch_args[@]}"
  print -- 'Firmware preparation only: no restore, CFW install, boot or export performed.'
  print -- "Next: follow $ROOT/skills/vphone-development/references/exp-image-workflow.md"
  exit 0
fi
(( $# >= 3 )) || { usage; exit 2; }
ACTION=$1 VM_NAME=$2 ARCHIVE=${3:a}
shift 3
[[ "$ACTION" == create || "$ACTION" == export ]] || fail 'Expected create or export'
[[ -n "$VM_NAME" && "$VM_NAME" != .* && "$VM_NAME" != */* && "$VM_NAME" != -* ]] || fail 'Invalid VM name'
[[ "$ARCHIVE" == *.tzst ]] || fail 'Output must end in .tzst'
[[ ! -e "$ARCHIVE" ]] || fail "Output already exists: $ARCHIVE"
[[ "$ARCHIVE" != "$LIBRARY/$VM_NAME/"* ]] || fail 'Archive must be outside the VM directory'
# Keep the same library and variant for all stages.
for arg in "$@"; do
  case "$arg" in
    --force-exc-guard*) fail 'Official vm create does not expose this flag; use exp.sh prepare NAME --force-exc-guard' ;;
    --variant*|-V*|--library-root*|-l*) fail 'EXP is fixed; set VPHONE_LIBRARY_ROOT to choose the library' ;;
  esac
done
if [[ "$ACTION" == create ]]; then
  [[ ! -e "$LIBRARY/$VM_NAME" ]] || fail "VM already exists: $LIBRARY/$VM_NAME"
  "$ROOT/scripts/build.sh"
  "$CLI" vm create "$VM_NAME" --library-root "$LIBRARY" --variant exp "$@"
else
  (( $# == 0 )) || fail 'export accepts only NAME and OUTPUT.tzst'
  [[ -x "$CLI" ]] || fail 'Run ./scripts/build.sh first'
fi
"$CLI" vm info "$VM_NAME" --library-root "$LIBRARY" --json >/dev/null
DISK=$(python3 - "$LIBRARY/$VM_NAME" <<'PY'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
with (root / 'config.plist').open('rb') as stream:
    config = plistlib.load(stream)
print(root / config['diskImage'])
PY
)
if /usr/sbin/lsof -t -- "$DISK" >/dev/null 2>&1; then
  fail "VM is running or disk is open; stop $VM_NAME before exporting"
fi
mkdir -p "${ARCHIVE:h}"
"$CLI" vm export "$VM_NAME" --library-root "$LIBRARY" --out "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
print -- "Archive: $ARCHIVE"
print -- "Checksum: $ARCHIVE.sha256"
