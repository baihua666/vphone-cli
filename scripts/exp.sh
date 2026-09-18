#!/bin/zsh
# Thin wrapper: source build → official EXP creation → official VM export.
set -euo pipefail
ROOT="${0:A:h:h}"
CLI="$ROOT/.build/vphone-cli.app/Contents/MacOS/vphone-cli"
usage() {
  cat <<'HELP'
Usage:
  scripts/exp.sh create NAME OUTPUT.tzst [vm create options]
  scripts/exp.sh export NAME OUTPUT.tzst

create: compile current source with build.sh, create a NEW EXP VM, export it.
export: export an existing stopped VM using the already-built official CLI.
Set VPHONE_LIBRARY_ROOT for a non-default VM library (default ~/.vphone/VMs).
Firmware selection uses official --iphone-source / --cloudos-source or prompts.
Creation may ask for sudo. Existing VMs are never replaced; stop before export.
The archive includes guest data. This exports a VM bundle, not a universal IPSW.
HELP
}
fail() { print -u2 -- "$*"; exit 1; }
if [[ ${1:-} == -h || ${1:-} == --help ]]; then usage; exit 0; fi
(( $# >= 3 )) || { usage; exit 2; }
ACTION=$1 VM_NAME=$2 ARCHIVE=${3:a}
shift 3
[[ "$ACTION" == create || "$ACTION" == export ]] || fail 'Expected create or export'
[[ -n "$VM_NAME" && "$VM_NAME" != .* && "$VM_NAME" != */* ]] || fail 'Invalid VM name'
[[ "$ARCHIVE" == *.tzst ]] || fail 'Output must end in .tzst'
[[ ! -e "$ARCHIVE" ]] || fail "Output already exists: $ARCHIVE"
LIBRARY="${VPHONE_LIBRARY_ROOT:-${VPHONE_ROOT:-$HOME/.vphone}/VMs}"
LIBRARY=${LIBRARY:a}
[[ "$ARCHIVE" != "$LIBRARY/$VM_NAME/"* ]] || fail 'Archive must be outside the VM directory'
# Keep the same library and variant for all stages.
for arg in "$@"; do
  case "$arg" in
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
