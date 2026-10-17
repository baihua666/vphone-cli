#!/bin/zsh
# Build/test both products without deploying a new host to existing machines.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

usage() {
  print -- '用法：./scripts/dev.sh build|test [gui|cli|all]'
  print -- '      ./scripts/dev.sh run      # 管理现有实例，沿用固定 CLI'
  print -- '      ./scripts/dev.sh run-dev  # GUI + 本仓库 CLI 构建，使用独立开发实例库'
}
build_gui() { "$ROOT/VPhoneWorkstation/scripts/bundle.sh"; }
build_cli() {
  xcodebuild -workspace VPhone.xcworkspace -scheme VPhone -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeBundle -jobs 4 build
}
test_gui() { swift test --package-path "$ROOT/VPhoneWorkstation"; }
test_cli() {
  xcodebuild -project VPhoneKit/VPhoneKit.xcodeproj -scheme VPhoneCoreKitTests \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/MonorepoTests -jobs 4 test
}
(( $# <= 2 )) || { usage; exit 2; }
case "${1:---help}" in
  build|test)
    action="$1"
    case "${2:-all}" in
      gui|cli) "${action}_${2}" ;;
      all) "${action}_gui"; "${action}_cli" ;;
      *) usage; exit 2 ;;
    esac
    ;;
  run)
    (( $# == 1 )) || { usage; exit 2; }
    exec "$ROOT/workstation.command"
    ;;
  run-dev)
    (( $# == 1 )) || { usage; exit 2; }
    app="$ROOT/VPhoneWorkstation/.build/vphone-ws.app"
    cli="$ROOT/.build/XcodeBundle/Build/Products/Debug/VPhone.bundle/Contents/MacOS/vphone-cli"
    library="${VPHONE_DEV_LIBRARY_ROOT:-$HOME/.vphone/development-machines}"
    [[ -d "$app" && -x "$cli" ]] || {
      print -u2 -- '请先运行 ./scripts/dev.sh build all'; exit 1
    }
    if /usr/bin/pgrep -x vphone-ws >/dev/null; then
      print -u2 -- '请先退出 Workstation，再切换开发环境；无需停止正在运行的 VM。'; exit 1
    fi
    mkdir -p "$library"
    exec /usr/bin/open "$app" --env "VPHONE_CLI_PATH=$cli" --env "VPHONE_LIBRARY_ROOT=$library"
    ;;
  -h|--help) usage ;;
  *) usage; exit 2 ;;
esac
