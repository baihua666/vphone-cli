# 官方基线与业务分支

## 2026-10-16 新版镜像、应用恢复与 Mac 分流交付

两台旧 schema 镜像保留，用当前业务源码基线 `4a76ffb217a059fa056cb2f35740b4ace15e735d` 构建 `VPhone.bundle 2.8.0 (35)`，另含本轮宿主开机解锁超时重试修复。不是本日最新 upstream main；本轮没有再次合并主分支。最终默认入口为 [start.sh](../start.sh) 与 [workstation.command](../workstation.command)。两台新机均已通过实际应用首屏、Never、无输入空闲及管理器冷启动验收。

| 角色 | 新机目录（`~/.vphone/machines/`） | 固定宿主（`~/.vphone/runtimes/source-4a76ffb-20261016/`） | ECID | Safari 实测公网 IP |
| --- | --- | --- | --- | --- |
| official / 1 | `official-2x-20261016` | `official/VPhone.bundle` | `6935474979FED755` | `178.249.213.185` |
| custom / 2 | `custom-2x-20261016` | `custom/VPhone.bundle` | `A4A7A0E8CA1A497E` | `79.127.245.219` |

- 两台是独立恢复的 schema 2 镜像，4 CPU / 4096 MB / 64 GB 逻辑稀疏盘，均为 `standard` / JB，不把旧 EXP、旧 MobileGestalt 定制或相同私网地址解释成另一种身份保证。输入是 iPhone17,3 iOS 26.6.2 / 23G90 与 cloudOS 26.4 / 23E5207q，原始 IPSW 的 ZIP/manifest/SHA-256 已核对。两个 `fw patch` 均记录 169 条修改；DFU restore 和 CFW install 均成功退出 0。Guest receipt 均为 21 生效 ID、2 不适用 ID，见 [补丁比较](0_binary_patch_comparison.md)。
- 原生系统管理员认证已用于本次 CFW；`sudo -n` 失败不是必须转交 Terminal 的理由。显式传入原用户 `SUDO_UID=501/SUDO_GID=20`，完成后属主恢复。CFW 有可用空间大于 50 GiB 的检查；首轮不足时从 `cfw install` 续跑，不重复创建/抹盘。只按用户授权清理 uv 未使用项、Homebrew 与 pip 下载缓存；本轮已消费的恢复输入和新建中间产物另有精确清理记录，未把后续其它空间增长全部归因本轮缓存清理。d47ap 原树恢复与原 manifest SHA-384 一致。详细过程保留在 [调试日志](debug_journal.md) 和下面的原始证据。
- official 恢复 Subway Surf 3.69.2；custom 恢复 VPHONE Probe 1.0、wooshort / `com.Orblino-Weave` 1.0.3、Facebook 581.0.0、Subway Surf 3.69.2、Idle Miner 5.64.1。来源是已有本机 IPA；Facebook 无原包，从旧机导出 cryptid 0 应用并恢复 Mach-O 执行权限，打包于 `~/.vphone/app-migration-20261016/Facebook-581.0.0-exported.ipa`。未迁移登录状态。五个 custom App 均启动后连续 20 秒存在、前台匹配并人工查看真实截图：Probe 测量页、wooshort 首页、Facebook 欢迎页、Subway 年龄页、Idle Miner 年龄/条款页；没有提交年龄、条款、登录或游戏业务验收。首台 Subway 初次 Metal 编译曾触发 scene-create watchdog，重试与后续脚本安装/首屏成功，未据此改 watchdog 或内核。
- 两机 Settings 的 Auto-Lock → Never 实际勾选，退出 Settings 后 API 读回 `2147483647 / never=true`。official 无输入 134 秒、custom 141 秒均亮屏未锁。新宿主补上启动窗口内两类明确屏幕超时的重试，密码等其它错误仍结束；测试编译实际 `VPhoneGuestControlSystem.swift`，旧 HEAD 在超时恢复用例失败，新代码通过。完整 Xcode bundle 构建、deep strict 签名、host preflight 均通过。原运行产物在各自旁边 `VPhone-before-unlock-retry.bundle` 保留。
- 新构建仅 vphoned 的 guest 资源哈希变化，其余 guest 库不变。官方自动同步后，两机实际运行的 vphoned SHA-256 为 `4ed663aa9f305eddcb6a454d349b4e098e947c242c205bd74eae517359f58987`；此前 CFW 初装哈希为 `9a61e9e816e8c71b7f1e63000531d9c44a9720e6f55cf4ac49f61c3ed096474e`。最终通过 Workstation 启动后的 boot UUID 分别是 `ECC07021-FFFC-4AF8-B51A-055EB6926C66` / `4058A2ED-2842-4CDC-8B57-B0486BA0B7C4`，与前一轮不同，均自动到达桌面、无锁无熄屏、Never 持久、Setup 完成；不是手动解锁后冒充自动通过。
- custom 首启曾在 `SpringBoard.migrator` 挂起后 userspace panic。stackshot 链追至 iconservicesagent 的 cleanup 线程；standard 的 108 个启用项里没有 hv_vmm，不能套用历史 locationd/bluetoothd 原因。保留四文件 APFS 检查点后以 NAT 对照重启，系统自然完成迁移；未清理图标缓存、修改迁移标记或添加固件补丁，NAT 与缓存进度等因素未单独排除，未宣称确定根因。随后恢复 tunnel，并通过两轮实际冷启动与五 App 首屏验证。
- Mac 使用现有 Clash Verge 2.5.8 / Mihomo 1.19.32，rule + TUN。两 VM 使用原生 `tunnel`，TCP/UDP 从各自 `vphone-vm` 的 Mac socket 出口。两个独立完整 bundle 路径分别匹配日本 BGP、美国 BGP 1 节点；持久规则写到当前订阅的 rule prepend，merge 启用 strict，移除本轮早先两个 LAN listeners。经 Clash Verge UI“重新激活订阅”再生成后仍为 570 条规则，两条 ProcessPath 位于原有两条 DIRECT 例外之后（index 2/3）。其它原订阅规则保留。通过 Workstation 重新启动两台后，Safari `https://api.ipify.org` 实读上表两 IP，并当场抓到两条请求分别匹配 official/日本、custom/美国 ProcessPath；此前 custom 曾为 `79.127.245.214`，节点池 IP 会变化。Facebook 实际的 api/gateway/m/graph/b-graph 等域名连接也匹配 custom 路径和美国节点。未在 guest 装 VPN 或设置系统 HTTP 代理。IP 为当前实测，不作静态或独享承诺；分流依赖 Clash TUN 与该订阅规则继续生效。
- Workstation 只对已有 sidecar 将 `variant` 改为可选，省略时保留 pinned host、不传旧 `--variant`。已有用户修改保留；全部 64 测试和 release 构建通过。真实 UI 已验证两个新对象的 Start / Stop / Show screen，并核对实际进程参数为对应固定宿主与新机器库、没有 `--variant`。当前两机和新 Workstation 保持运行。**新建向导仍使用旧版创建参数，不属于本轮适配/验收；2.x 新建请用原生 CLI，不把现有镜像管理通过当作整个 Workstation 已兼容。**
- 用户要求的 [应用安装 SKILL](../skills/vphone-app-install/SKILL.md) 已交付，全局 `~/.codex/skills/vphone-app-install` 以符号链接发现。其宿主脚本用 Swift 6 临时编译并复用 `VPhoneAPIClient.swift`，HTTP 流式上传、WebSocket 等待原生安装（10 分钟上限），避免 HTTP RPC 130 秒超时后盲目重装；API 根路径规范为 `/`。实装和参数/解析 self-test 均通过，产品和 guest 不增加解释器/工具依赖。**Instagram IPA 仍缺，Instagram App 登录/分流验收未完成。**

原始验证目录为 `.build/validation/image-upgrade-20261016/`，关键证据：`migration-plan.json`、`app-sources.json`、`firmware-sha256.txt`、`cfw-*.log`、`startup-unlock-red.log` / `startup-unlock-green.log`、`install-skill-self-test-swift6.log`、`custom-app-launch-verification.json`、`custom-facebook-connections.json`、`workstation-two-egress-final.json`、`workstation-ipify-active-connections.json`、`workstation-two-guests-final.json`，对应实际首屏、Never、桌面和公网 IP 截图同目录。API token 与包含 token 的日志为 0600，不提交这些产物或将 raw log 发到外部。

回滚资料：旧 official 在 `~/.vphone/VMs/stock-regular-guard-20261008`，旧 custom 在项目 `vm-fresh`，旧运行产物均保留；旧入口脚本在 `~/.vphone/migration-backups/image-upgrade-20261016/{start.sh,workstation.command}.legacy`。回滚时先正常停止对应新 VM/管理器，再把入口备份复制回项目原位置（不可直接在备份目录运行依赖相对路径的脚本）。旧 Workstation app 保留于相邻项目 `.build/vphone-ws-legacy-20261016.app`。Clash 原配置与规则变更前备份在 `~/.vphone/network-backups/proxy-20261016/`（含凭据，勿提交），custom 迁移 panic 的 APFS 检查点在 `~/.vphone/migration-backups/image-upgrade-20261016/custom-panic-checkpoint/`。

## 2026-10-13 当前旧镜像的中文粘贴宿主

`start.sh official` 已切换到库外 `~/.vphone/runtimes/legacy-clipboard-20261012/vphone-cli.app`：在官方 1.0.14 基线上补齐中文 ⌘V 的本地兼容宿主。旧 guest、固件和配置保持原版本，未迁移到 2.x schema；`custom` 映射未变。实现、提交与实际验收见 [中文粘贴记录](Host/legacy_clipboard_20261013.md)。以下 2026-10-08 对 official 启动入口的描述是迁移前历史。

## 2026-10-08 源码同步

- `main`：官方 `Lakr233/vphone-cli` 的 `dfcfae9c608c432a9a63f846d5cda8272fde0b82`，跟踪 `upstream/main`；由 GitHub MCP 核实，与本次 fetch 一致。
- `codex/business-vm`：合并上述官方基线，保留独立取证工具、启动入口和研究历史。
- `codex/pre-upstream-sync-20261008`：同步前完整业务代码 `d23154b`，保留原 Python MobileGestalt 实验、EXP 流程和测试，供查证/后续移植。
- `tb_dev`：原历史指针 `0f76ba1`，不改写。
- `origin` 仍是个人 fork；本次未推送。官方基线较旧 `9c23c8a` 增加 636 个提交（包含合并提交）。

## 架构迁移与冲突处理

采用上游 Xcode workspace、原生 Swift/C 实现及 patch sets/presets，不恢复已删除的 Python 固件流水线。上游现在只公开 JB 模式，不能把旧 `--variant exp` 自动映射为某个 preset。

旧的 `cfw_patch_hv_vmm_dsc.py`、`custom_features.py`、特性头和对应测试不进入新版流水线。本地默认关闭的 MobileGestalt 实验尚未移植；完整可恢复版本在备份分支，不声称它在新版继续生效。历史验证补充保留在 `0_binary_patch_comparison.md`。

旧 `ResourcesTests` 的 signcert 路径和 ObjC 安装器签名测试依赖已经移除的实现，随上游旧代码删除；新版使用上游对应 Xcode 测试。`scripts/exp.sh` 对旧操作明确报错且不修改 VM，避免运行残留旧程序。Python 取证工具及其测试作为独立宿主研究工具保留，不作为产品运行依赖。

研究文档保留在 `Research/` 根目录，不采用 Git 将所有新文件推断到 `Research/Kernel/` 的位置。当前指南在 `AGENTS.md`；本地开发 skill 顶部列出新版边界，旧步骤仅供历史排障。

## 开发与验证

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeBundle -jobs 4 build

xcodebuild -project VPhoneKit/VPhoneKit.xcodeproj -scheme VPhoneCoreKitTests \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/upstream-sync-tests -jobs 4 test
```

完整构建输出为 `VPhone.bundle`，不是旧 `.build/vphone-cli.app`。运行部署按 `Documents/Guides/host-setup.md` 与 `Documents/Guides/launchpad-cli.md` 验收，不能以源码合并或测试成功代替 guest 版本确认。

## 现有 VM 与运行产物

本次同步不重刷、不迁移、不启动虚拟机，不替换已构建产物。`start.sh official` 仍使用库外官方 1.0.14，`start.sh custom` 仍使用同步前保留的旧版 app；启动脚本明确提示这不代表当前源码。旧运行产物缺失时需恢复对应版本，不能把新 bundle 伪装成旧 app。

当前实例是 `~/.vphone/VMs/stock-regular-guard-20261008` 和仓库内 `vm-fresh`。后续升级运行环境时单独核实宿主、guest daemon、固件兼容性，再决定部署。VM、IPSW、构建产物和 CodeGraph 索引不进入 Git。

## 自动化镜像基础验收（2026-10-10 用户要求）

官方对照和业务定制镜像均须设置 iOS「显示与亮度 → 自动锁定 → 永不」，保存设置页证据，并在无输入至少 2 分钟后确认屏幕仍亮且未锁定。新建、导入、恢复或更新镜像后同样验收。设置属于实例运行偏好，不修改官方源码或固件。重启后的首次解锁单独检查，不能用「永不」代替；不自动删除密码或更改认证。当前两实例的设置与共享验证见 [2026-10-10 报告](storage_sharing_20261010.md)。
