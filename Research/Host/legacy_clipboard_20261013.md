# 当前旧版 VM 的中文快捷键粘贴验收

## 范围与结果

2026-10-13，当前实例 `~/.vphone/VMs/stock-regular-guard-20261008` 已改用本地兼容宿主，实测 ⌘V 可把 Mac 文本粘贴进 iOS Safari。测试文本分别为 `中文快捷键粘贴验证123` 和 `第二次粘贴：你好，世界🌍`，第二次换内容后仍正常。通过的是文字粘贴；没有验证图片、富文本、文件或所有第三方 App。

原 guest 为 iOS 26.1.0、vphoned v1。没有替换 guest daemon、修改固件、重刷镜像或改变设备身份。`config.plist` 与升级前备份的 SHA-256 相同。

## 兼容性与实现

当前仓库的 2.x bundle 已完整构建并通过 host preflight，但 `vm list` 明确拒绝当前旧 schema 的实例。官方 [兼容性说明](https://github.com/Lakr233/vphone-cli/blob/main/Documents/Guides/compatibility.md) 要求重建旧 VM，不支持就地升级。未添加 `schemaVersion=2` 来绕过检查，未部署这次构建的 2.x daemon。

因此从官方 1.0.14 基线 `9c23c8a` 在隔离工作区补齐宿主功能，分支 `codex/legacy-clipboard-20261012`，最终源码提交 `9a88a406e5dfbc6e7daf66a0826a1a09daee8b15`。不把旧 SwiftPM 产品架构恢复到当前业务分支。

`VZVirtualMachineView.capturesSystemKeys` 的本地监视器会抢先吞掉按键。仅覆盖视图的 `performKeyEquivalent`，甚至只添加 Edit 菜单，都不足以接住快捷键。复用当前上游 `VPhoneApplication.sendEvent` 的入口，在 VM 是第一响应者且没有 sheet 时拦截纯 ⌘V，忽略对应松键；其它按键走原路径。粘贴动作读取 Mac 字符串，等待原有 `clipboardSet` 的 guest 确认，再发送 Command 按下、V、Command 松开。失败时提示而不粘贴旧内容。Edit → Paste 也走这一动作。

## 运行入口与回滚

- 已安装兼容宿主：`~/.vphone/runtimes/legacy-clipboard-20261012/vphone-cli.app`。
- `./start.sh official` / `./start.sh 1` / 无参数默认入口均使用该宿主。
- 原始官方包仍在 `~/.vphone/runtimes/upstream-1.0.14/`。
- `custom` / `2` 的运行映射没有变更。
- 升级前配置、启动脚本及从 guest 下载的旧 daemon 在 `~/.vphone/upgrade-backups/clipboard-20261012/`。
- 如需回滚宿主，正常退出当前 VM，把 `start.sh` 的 official CLI 路径改回原始官方包即可；无需替换磁盘或 guest daemon。

## 验证证据

- 兼容宿主 `swift build -c release --product vphone-cli -j 4` 成功；安装包 `codesign --verify --deep --strict` 通过。
- `swift test -j 4 --filter ClipboardShortcutTests`：1 项通过。测试启用 `capturesSystemKeys`，模拟真实 AppKit Command-V 按下和松开，验证应用层先执行一次粘贴动作。
- 升级前实测只出现字母 `v`；修复后用 Mac 原生剪贴板/⌘V 操作，Safari 两次显示完整中文字符串及 emoji。
- 截图：`.build/validation/clipboard-current-20261013/chinese-paste.png`；兼容宿主测试日志：`.build/clipboard-legacy-tests.log`；构建日志：`.build/clipboard-legacy-build.log`；运行日志：`.build/clipboard-legacy-runtime-verified.log`。
- `zsh -n start.sh` 和启动帮助通过；启动脚本保留磁盘占用检查。
- 初始 2.x 探查的 10 项 ClipboardTransferTests 也通过，但它们不作为本次已部署旧版宿主的功能验收。

SHA-256：

```text
host:   2ea0f2fe1d558ab7011dc8fb54008b7352995e648919f8cfd2e297babf24e641
config: 2ad9b3a01b99b6c5a9120e8a489dc58998e2bcb9fbe3327b09b17352c57a6226
guest:  0ac8c42db618929585dc3ccca91876447a904e94904a7f47e6b2a231725a8cf3
```
