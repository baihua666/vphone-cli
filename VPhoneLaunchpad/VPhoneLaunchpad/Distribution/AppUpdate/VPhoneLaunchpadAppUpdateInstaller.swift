#if VPHONE_CUSTOM_DISTRIBUTION && VPHONE_CUSTOM_APP_UPDATE
import Foundation

extension VPhoneLaunchpadAppUpdate {
    // Runs outside the App so replacement happens only after the old process exits.
    nonisolated static let installer = #"""
    #!/bin/zsh
    set -euo pipefail
    parent="$1"; incoming="$2"; destination="$3"; requirement="$4"; report="$5"
    directory="${0:a:h}"
    backup="$directory/previous.app"
    moved=0
    failed() {
        print -r -- "自动更新失败，已保留或恢复旧版本。日志：$directory/install.log" > "$report"
        if (( moved )); then
            [[ ! -e "$destination" ]] || /bin/mv "$destination" "$directory/failed.app"
            /bin/mv "$backup" "$destination"
        fi
        if ! /bin/kill -0 "$parent" 2>/dev/null; then
            /usr/bin/open -n "$destination" || true
        fi
    }
    trap failed ZERR
    /usr/bin/codesign --verify --strict --deep "-R=$requirement" "$incoming"
    [[ -d "$destination" && ! -L "$destination" && ! -e "$backup" ]]
    /usr/bin/touch "$directory/ready"
    for attempt in {1..300}; do
        /bin/kill -0 "$parent" 2>/dev/null || break
        /bin/sleep 0.1
    done
    if /bin/kill -0 "$parent" 2>/dev/null; then
        trap - ZERR
        print -r -- "旧版 Launchpad 未退出，自动更新已取消；当前版本未替换。" > "$report"
        exit 1
    fi
    /usr/bin/codesign --verify --strict --deep "-R=$requirement" "$incoming"
    /bin/mv "$destination" "$backup"
    moved=1
    /bin/mv "$incoming" "$destination"
    /usr/bin/codesign --verify --strict --deep "-R=$requirement" "$destination"
    /usr/bin/open -n "$destination"
    trap - ZERR
    """#
}
#endif
