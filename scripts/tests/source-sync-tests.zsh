#!/bin/zsh
# Exercise source-sync boundaries without launching a GUI or VM.
set -euo pipefail
ROOT="${0:A:h:h:h}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vphone-source-sync.XXXXXXXX")"
WORK="${WORK:A}"
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home" CAPTURE="$WORK/args"
unset VPHONE_HOST_CONFIG VPHONE_CLI_PATH VPHONE_LIBRARY_ROOT
unset VPHONE_OFFICIAL_NAME VPHONE_CUSTOM_NAME VPHONE_OFFICIAL_CLI VPHONE_CUSTOM_CLI
mkdir -p "$HOME/.vphone" "$WORK/repo/VPhoneWorkstation/.build/vphone-ws.app" "$WORK/bin"
cp "$ROOT/start.sh" "$ROOT/workstation.command" "$ROOT/.gitignore" "$WORK/repo/"
export PATH="$WORK/bin:$PATH"
cat > "$WORK/bin/open" <<'MOCK'
#!/bin/zsh
print -rl -- "$@" > "$CAPTURE"
MOCK
cp "$WORK/bin/open" "$WORK/bin/cli with spaces"
chmod +x "$WORK/bin/"*
check() { [[ "$1" == "$2" ]] || { print -u2 -- "FAIL: $1 != $2"; exit 1; }; }
fails() {
  if "$@" > "$WORK/error" 2>&1; then
    print -u2 -- "unexpected success: $*"; exit 1
  fi
  [[ ! -e "$CAPTURE" ]] || { print -u2 -- 'unexpected launch'; exit 1; }
}
cd "$WORK/repo"
zsh -n start.sh workstation.command
zsh start.sh --help > /dev/null
fails zsh start.sh
fails zsh workstation.command
fails env VPHONE_HOST_CONFIG="$WORK/missing" zsh start.sh
fails env VPHONE_HOST_CONFIG="$WORK/missing" zsh workstation.command
fails zsh start.sh invalid
fails zsh start.sh official extra
cat > "$HOME/.vphone/host-config.zsh" <<'CONFIG'
: ${VPHONE_CLI_PATH:="$HOME/../bin/cli with spaces"}
: ${VPHONE_LIBRARY_ROOT:="$HOME/library with spaces"}
: ${VPHONE_OFFICIAL_NAME:=phone-a}
: ${VPHONE_CUSTOM_NAME:=phone-b}
CONFIG
LIBRARY="$HOME/library with spaces"
for name in phone-a phone-b; do
  mkdir -p "$LIBRARY/$name"
  touch "$LIBRARY/$name/"{config.plist,Disk.img,nvram.bin,SEPStorage}
done
for alias in official 1 custom 2; do
  zsh start.sh "$alias" > /dev/null
  args=("${(@f)$(cat "$CAPTURE")}")
  check "${args[1]} ${args[2]}" 'vm launch'
  case "$alias" in official|1) check "${args[3]}" phone-a ;; *) check "${args[3]}" phone-b ;; esac
  check "${args[4]}" --library-root
  check "${args[5]}" "$LIBRARY"
  rm "$CAPTURE"
done
zsh start.sh > /dev/null
check "$(sed -n '3p' "$CAPTURE")" phone-a
rm "$CAPTURE"
# Missing data and invalid per-alias hosts must fail before launching.
rm "$LIBRARY/phone-a/SEPStorage"
fails zsh start.sh official
touch "$LIBRARY/phone-a/SEPStorage"
fails env VPHONE_OFFICIAL_CLI="$WORK/missing" zsh start.sh official
# An explicit environment can override config defaults, including the alias host.
env VPHONE_OFFICIAL_NAME=phone-b VPHONE_OFFICIAL_CLI="$WORK/bin/open" zsh start.sh official > /dev/null
check "$(sed -n '3p' "$CAPTURE")" phone-b
rm "$CAPTURE"
zsh workstation.command
args=("${(@f)$(cat "$CAPTURE")}")
check "${args[1]}" "$WORK/repo/VPhoneWorkstation/.build/vphone-ws.app"
check "${args[3]}" "VPHONE_CLI_PATH=$HOME/../bin/cli with spaces"
check "${args[5]}" "VPHONE_LIBRARY_ROOT=$LIBRARY"
rm "$CAPTURE"
# Alternate local configuration works without relying on the default file.
cp "$HOME/.vphone/host-config.zsh" "$WORK/alternate.zsh"
rm "$HOME/.vphone/host-config.zsh"
env VPHONE_HOST_CONFIG="$WORK/alternate.zsh" zsh start.sh custom > /dev/null
check "$(sed -n '3p' "$CAPTURE")" phone-b
rm "$CAPTURE"
# Check shared rules in a fresh repository, without the real info/exclude.
git init -q
for file in .codegraph/index.db vm2/Disk.img arbitrary/Disk.img images/base.tzst \
  images/base.txz firmware/source.ipsw phone/nvram.bin phone/SEPStorage \
  phone/.vphone-ws.json host-config.zsh config.local.zsh .env.local .local/state \
  machines/phone/data runtimes/host/data .build/output; do
  git check-ignore -q -- "$file" || { print -u2 -- "not ignored: $file"; exit 1; }
done
for file in scripts/dev.sh Documents/Guides/guide.md config.plist tests/fixture.json \
  tests/fixture.db Package.resolved .env.example; do
  if git check-ignore -q -- "$file"; then
    print -u2 -- "source incorrectly ignored: $file"; exit 1
  fi
done
print -- 'PASS: aliases, config defaults/overrides, quoted argv, failure guards, GUI dispatch and shared ignore rules'
