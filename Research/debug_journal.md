## J-2026-10-16 — 新版镜像迁移，纠正管理员认证入口判断


## 2026-10-23 本地应用版本状态读回与部署

原应用管理只保存 Bundle ID 集合且每行固定「安装」。改为读回 guest apps.list 的版本和构建号，
本地读取 CFBundleVersion，先比较数字版本再比较构建。相同显示「已是最新版本」（仅相对于本地包），
本地新显示升级、guest 新明确提示，未知不误报最新；右侧菜单保留确认重装/降级。
选目标、打开窗口、实例启动、安装完成及刷新时读取；目标路径/请求ID排除迟到响应，读取错误不视为空列表。
只改 Launchpad 与 ApplicationManagement，不改 Core。11 项测试及启用/禁用构建通过。
已部署到 /Applications/vphone-launchpad.app，原 helper 保留；1-20261023 原配置逐字节一致、4 GB 运行。
真实 UI 选择该实例后自动显示 TikTok 47.4.0 / build 474032「已是最新版本」，不再显示普通安装按钮；
未重装任何应用。证据 .build/validation/application-versions-20261023/。

## 2026-10-23 Launchpad 临时增配安装恢复集成并部署

应用管理在已提交安装失败/读回未确认且原内存低于 8 GB 时提供显式确认，固定失败时的
library/name 目标。确认后复用机器启停、原 pinned CLI 的 vm config 和现有安装 workflow；
无论安装结果如何都恢复实际原内存并启动。恢复记录在首次停机前落入 Launchpad support
目录，包含目录身份/原绑定/原内存；重开只恢复不重装，失败留记录与恢复按钮。
只在 Launchpad/独立 Integration 实现，Core、guest、helper 未修改。目标操作保留锁，
目录或 Core 变化拒绝操作；关闭应用管理窗口不取消流程。新增独立编译条件
VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY，停用前须先完成待恢复记录。
9 个 package 测试和实际 adapter 隔离测试通过；覆盖成功、每阶段失败、取消、恢复失败、
记录重开、同名不同库、绑定变化及同名目录替换。开启、单独关闭恢复、全部关闭应用管理
三种构建通过。已签名部署 /Applications/vphone-launchpad.app，保留原 helper 字节，ready (15)。
部署后 1-20261023 原配置逐字节一致、4 GB 运行，UI 已读回 TikTok 已安装，其它实例仍停止。
本轮未再次触发真实安装失败；新异常路径为隔离自动测试，真实增配安装为前轮验收，不能混称。
构建及部署证据：.build/validation/install-memory-integration-20261023/。
入口、回退与限制见 [应用管理指南](../Documents/Guides/launchpad-applications.md)。

## 2026-10-23 TikTok 临时增配安装验收通过

用户授权后仅对 1-20261023 临时调为 8 GB，在原 2.8.0-local.199abaf3 上使用 Launchpad
相同业务 workflow 完成 TikTok 47.4.0 真安装。随后正常停机恢复 4 GB，config.plist 和
launchpad.json 与原备份逐字节一致。重启后 TikTok 启动、六次 5 秒间隔采样与前台验证通过，
截图显示登录页；未验证账号登录、视频和长期稳定性。未升级或修改 Core/guest/Launchpad，
未触碰其它实例；当前保留 4 GB 运行。详见 [验收](Host/launchpad_tiktok_install_failure_20261023.md)。

## 2026-10-23 TikTok 安装内存调查（保持 4 GB）

用户暂停增配后，仅在宿主临时副本上用原 Core 签名器实测：TikTok 单个 arm64 framework
约 840 MiB，签名峰值 RSS 约 1.58 GiB。源码存在完整 slice 复制及完整输出缓冲；与此前
guest Jetsam 相符，但未采集客体分配栈，不把宿主数据冒充客体峰值。上传、解包已流式，
安装已串行；现有 apps.install 强制客体重签，宿主预签无法绕过。apps.register 不等同完整
容器安装，不能伪造标记绕行。当前第三方主进程总 footprint 仅约 3.5 MiB，清后台无明显收益证据。
未改 Core、内存、运行应用、未部署或重试；详见 [调查](Host/launchpad_tiktok_install_failure_20261023.md)。

## 2026-10-22 五台迁移到官方 2.8.0 基线的本地测试核心

用户明确授权重新构建最新本地核心、迁移五台、验证应用与数据后删除错误版本。
在实际合入的官方 `dfcfae9c608c432a9a63f846d5cda8272fde0b82` / 2.8.0
基线上构建当前 `b4f124b-dirty` 工作区，完整 VPhone 构建、bundle admission、
deep strict 签名、正常 install-local 和主机预检通过。新核心为
`2.8.0-local.199abaf3`；seal SHA-256 前八位确为 199abaf3，未人工改哈希。
vphoned SHA-256 为 `93863283706957ecf7e0dc1309548340b187a28be6fd5f89245b19716dd26501`。
本地和 CI 构建的 test 展示标签保持，用户授权迁移不等于确认发布。

开始时五台均已停止。各自原 pinned CLI 创建 APFS 停机快照
`before-core-280-20261022`；另备份配置及绑定。带 test 标签的 Launchpad
按已安装应用同一 Apple 开发签名重新构建、验签，在全部停机时整体替换，
旧应用保存在本轮验证目录的 installed-before。Helper 重新安装由系统管理员
认证完成，没有绕过签名检查；后续授权过期也通过原生认证继续。

逐台记录旧核心的应用、容器及数据，正常停机，set-bundle 更新，再启动验证。
native-https-test-a/b 缺少 restore-info.json，set-bundle 的客体更新被现有
条件跳过，因此显式调用既有 `cfw update-environment`，不伪造恢复元数据。
两次均退出 0；日志提示缺原始 DeviceTree.d47ap.im4p，iPhone product repair
跳过，Siri/Camera Control/Action Button/Model Name 不在本次硬件验收范围。
未执行 restore、vm create、内核更新或重建身份。

| 实例 | 应用条目（前后相同） | 第三方应用 | 对比文件摘要 |
| --- | --- | --- | --- |
| init-check-01 | 246 | 0 | 0 |
| official-2x-20261016 | 248 | 2 | 17 |
| custom-2x-20261016 | 252 | 6 | 77 |
| native-https-test-a | 250 | 4 | 0 |
| native-https-test-b | 250 | 4 | 0 |

94 个文件为 Documents、Library/Preferences、DCIM 和录音目录下可用文件，
86 个完整文件 SHA-256、8 个较大文件的前 64 KiB SHA-256，均相同；不是全盘
逐字节校验。两台测试克隆机对应 Documents/Preferences 原本为空，录音目录
原本不存在，未把这些情况冒充有用户内容的文件校验。五台应用版本、数据容器
和共享组容器关联保持；每个第三方应用启动后等待 15 秒，PID 和前台身份确认，
另检查真实截图。空闲观察每台超过 120 秒，均保持亮屏解锁，Never 两个有效值
均为 2147483647。未提交年龄、条款、注册、登录或游戏/业务操作。

五台 config.plist SHA-256 均与迁移前一致，各自 .vphoned.signed 完整摘要均与
新核心一致；所有主机和客体环境绑定均为新核心，启动链历史来源不伪改。补充的
12 MB daemon 全文件 RPC 读取未完成，仅中止该只读查询，未以它声称客体完整
哈希验证；最终以成功的客体部署和同一部署暂存文件摘要核对。该查询期间 custom
空闲采样出现间隔，实际总观察 202 秒，其余各台约 126–129 秒。

全部通过后将默认核心设为新核心，通过正常 bundle remove 删除
`2.9.0-local.f9f452dc`、`2.10.0-local.9740edc6`、`2.10.0-local.199abaf3`。
商店剩新核心及两份原有正确命名的 2.8 本地核心。真实 Core Bundle 界面确认
新核心有 test、默认和五台使用标签。五台最终均停止，与本轮开始状态一致；
五份快照和配置备份保留。原 Workstation 备用 sidecar/分流配置未改，仍为其
原独立入口；本轮统一的是 Launchpad 的实例绑定。

证据位于 `.build/validation/core-280-migration-20261022/`，包括
`migration-verification-summary.json`、逐台前后记录、截图、更新日志和
`cleanup-summary.json`；验证目录为 0700，数据记录为 0600。版本/绑定及 test
标签、Auto-Lock 原生 setter、迟到锁屏、宿主开机解锁回归均通过。

## 2026-10-22 清理错误版本号的未使用核心包

用户授权整理本地核心，不能原地改版本时删除错误命名；延续不更换现有实例
核心的约束。通过已安装 Launchpad 的 `bundle remove` 删除
`2.10.0-local.0f9d0a78` 与 `2.10.0-local.36ee25a1`，两次返回 removed，
复查目录均不存在。代码核对 bootChain 仅为历史来源记录，后者不再被运行核心
绑定使用；init-check-01 的历史字段保留，不伪造为新版本。

保留仍被绑定的错误版本 `2.9.0-local.f9f452dc`、`2.10.0-local.9740edc6`、
`2.10.0-local.199abaf3`，以及两份正确命名的 2.8 本地包，商店共剩五份。
五台 VM 的 launchpad.json/config.plist SHA-256 逐项保持不变，默认核心不变。
本轮未发送 VM 启停命令；前后只读列表中 init-check-01 从 running 变为
正在关机，原因未核实，不声称全部运行状态保持不变。删除核心包不涉及 VM 磁盘。

## 2026-10-22 本地核心测试构建展示标签

用户要求 AI 测试构建展示 `test`，保留官方基线版本和内容哈希，暂不更换现有
虚拟机核心。复用官方 `-local.<内容哈希>` / `-ci.<commit>` 解析，在 Launchpad
核心包列表、新建机器和更换核心包菜单增加展示标签；Picker 的 tag 继续使用
原始版本字符串。官方发行版不加标签；本地及 CI 构建默认按测试产物展示，
预检通过或设为默认不会被视为用户发布确认。当前没有发布确认持久化记录或
发布提升入口，未据此推断具体构建者，也未添加新的版本字符串格式。

BundleNamesTests 的 14 个原有版本用例、测试标签分类（local、CI、legacy、
官方发行与无效名称）、标签不作为存储身份及实例绑定往返测试通过。
完整 Launchpad Debug 构建通过，输出 `.build/LaunchpadTestLabels/`，
日志 `/tmp/vphone-launchpad-test-labels-build.log`。未部署、打开候选 app 或
操作 VM，未修改已安装包、receipt、实例绑定或 guest 环境；实际界面未运行验收。

## 2026-10-22 本地版本号恢复官方基线

用户明确要求版本号表示实际合入的官方基线，本地改动由 `local.<构建标识>` 区分。
当前 upstream 基线为 `dfcfae9c608c432a9a63f846d5cda8272fde0b82`，官方
Core Bundle 和 Launchpad 均为 2.8.0；同 SHA 的官方 Info.plist 已经 MCP 核对。
工作区此前为原生代理、设备初始化自行改为 2.9/2.10，混淆了代码来源，
不是同步了相应官方版本。现恢复 Core Bundle Info.plist 和 Launchpad
MARKETING_VERSION 为 2.8.0，并将约束写入 AGENTS.md。
原生代理已检查 CLI 选项和运行核心能力，初始化已检查 guest 写能力，
不依赖本地 2.9/2.10 数字放行。历史验收包名保持原样，仅作追溯。
本次不构建、部署、删除或重命名已安装包，不改 receipt、VM 绑定或客体环境。

## 2026-10-22 现有五台初始化检查与旧镜像清理

用户要求检查现有机器，补齐启动解锁和 Never，保留数据、不重建；另明确授权
删除旧 1.x 备份。Launchpad 清单为 custom/official-2x-20261016、
native-https-test-a/b、init-check-01。五台 `unlocksAtStartup` 均为 true，
guest 的 `never=true`、`auto_lock_seconds` 与 `lock_screen_minimum_seconds`
均为 2147483647。没有缺项需要写入，没有执行 restore、CFW 安装、重新绑定、
密码修改或输入保活；沿用每台 library/pinned bundle。

本次实际复现了配置齐全仍冷启锁定：五机并行期间，init-check-01 超过三分钟
仍 locked=true、screen_off=false、passcode_enabled=false。正常关机后日志为
`[unlock] could not unlock the guest at startup: the Lock Screen did not dismiss in time`。
当时宿主交换内存使用约 24 GiB。降低并发后该机 16 秒 vphoned 连通、自动进入
桌面，随后与 custom 一起无输入观察 125 秒通过；official 连通耗时 134 秒，
自动进入桌面且只读采样跨度约 138 秒未锁。压力是相关线索，未进行独立变量
对照，不据此宣称确定根因或底层超时已修复。所有四个绑定宿主二进制均含现有
启动超时重试逻辑，不把此次情况误判为缺少该代码。

首次验收与“查明虚拟机 IP 与 VPN 决策 (2)”聊天发生 A/B 启停重叠；发现后
停止争用，等待其完成并停机后重新独立验收。不能将重叠时段当作两台无输入
空闲验证。原始状态、采样、截图、配置/绑定哈希与删除记录保存在
`.build/validation/existing-vm-initialization-20261022/`。检查期间曾采到锁屏和
纯黑启动画面，均不作为桌面成功证据。

另一聊天完成后，A 独立冷启动 131 秒连通、自动解锁，无输入观察 121.8 秒；
B 独立冷启动 15 秒连通、自动解锁，无输入观察 121.6 秒；两台均最终读回
Never 和两个 Int32.max 值，A 实际截图为桌面，B 为桌面上的 Trust This Computer
提示；未点击信任或拒绝，也未改变配对。A/B 验后正常停止，以保留另一
聊天明确选择的释放内存状态；official 恢复原停止状态，custom 和 init-check-01
保持运行且最终只读复核 unlocked/lit。五份 config.plist 和五份 launchpad.json
SHA-256 与检查前均一致。init-check-01 重启前后 246 个已安装应用的标识、
版本与容器路径一致（不是完整业务数据校验）。最终结果是五台配置完整、
低并发冷启与至少 120 秒空闲复测通过；并发负载下的启动超时仍是已知限制，
不能写成所有启动场景均已修复。

旧镜像删除前用 lsof 确认两个 Disk.img 没有打开句柄，核对实际目录和两个管理
链接的真实目标后删除。范围仅 `~/.vphone/VMs/stock-regular-guard-20261008`、
项目 `vm-fresh` 及对应 workstation-library 链接；当前五台目录保留。
历史回滚说明已在 branch_workflow.md 顶部纠正。未增加固件补丁。

## 2026-10-22 初始化策略隔离（替代下条初版架构）

按新增业务隔离规范，将 Never、解锁顺序和 120 秒验收策略移出 CoreKit，
放入 Launchpad 的 Business/DeviceInitialization 独立目录；删除初版
vm initialize 入口和 CoreKit 业务测试。应用组装处默认注入异步闭包，
pipeline 只负责扩展步骤生命周期、展示和重试；无注入时以 firstBoot 完成。
薄适配器复用现有 guest socket 与绑定 CLI，成功验证后才开启已有启动解锁选项。
旧 guest 缺能力时只在初始化失败；全局 bundle 下限恢复为此前 2.9.0，
不自动改动实例绑定。通用 guest 设置能力保留，未增加固件补丁。

策略测试、真实 pipeline/适配器测试和版本绑定测试已通过；测试覆盖停用基础
路径、firstBoot ping、初始化失败后单独重试、2.9 上下文和响应格式错误。
native setter 测试、Launchpad 构建、完整 Core Bundle 构建均通过；原生 CLI
已移除业务 initialize 命令。构建日志为 `.build/initialization-isolation-*-build.log`。
2.10.0 bundle 的 deep strict 签名与准入检查通过，CLI help 确认不再暴露 initialize。
未部署到现有 app / pinned VM，未进行真实 guest 设置写入、空闲与冷启动验收。

## 2026-10-22 Launchpad 创建后初始化设备（初版，架构已被上条替代）

用户要求在首次启动后自动设置 Never、验证并支持单独重试。原 firstBoot
仅等待 vphoned ping；追加 initializeDevice 后，完成状态必须等该步骤通过。
复用实例绑定 CLI、screen.unlock、GuestLockScreenIdle 和失败步骤重试入口，
新增 vm initialize 执行系统设置写入、读回、respring、再次解锁和至少 120 秒
无输入屏幕状态观察；Launchpad 成功后启用既有 unlock-at-startup。
旧 guest 无写能力时在修改前拒绝，不重新恢复或安装固件。

8 项 CoreKit 测试、实际流水线单独重试测试、native setter 测试、版本/绑定
测试通过；Launchpad 与完整 Core Bundle 构建通过，2.10.0 bundle deep strict
签名检查通过。新增 CLI 契约按规则提升 minor 和最低 bundle 版本。构建日志
在 `.build/initialization-*.log`。未部署到已有 app / pinned VM，未验证实际
guest 的 profiled 接受写入、Settings 页面、真实空闲和冷启动持久性。
接口来源、步骤和验收边界见 [设备初始化](../Documents/Guides/launchpad-device-initialization.md)。

## J-2026-10-22 — Launchpad 基础操作被可选代理版本门槛拦截

用户创建/启动时收到“需要 VPhone.bundle 2.9.0 或更新版本”。本机默认仍为
`2.8.0-local.b0ffd6cc`；本地原生代理改动把全局最低版本从 2.8.0 提到
2.9.0，导致 `CoreBundle.prepare` 在基础操作前拒绝旧绑定。原生代理已有
CLI 选项和运行核心能力检查，因此恢复全局 2.8.0 下限，保留功能自己的检查。
不改 VM 绑定、默认 bundle、guest 或固件；初始化仍按 guest 写能力独立报错。

回归先在 `BundleNamesTests.sh` 复现 `isCompatibleBundleVersion("2.8.0")`
失败，修复后 14 个版本/绑定用例通过。创建流水线、初始化策略及原生代理
旧核心拒绝修改/可选能力解码测试通过；完整 Launchpad Xcode 构建和同身份签名、
deep strict 验证通过。产物为 `.build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app`。
安装前发现另一会话已启动管理器并在恢复原有 VM，因此本轮未覆盖已安装 app，
也未停止或启动任何 VM。需该会话结束后部署管理器，再验收原创建/启动路径。

## J-2026-10-22 — 初始化部署实测中的权限和迟到锁屏

本会话获授权部署并新建一台测试机，要求不影响旧机。证据位于忽略目录
`.build/validation/device-initialization-20261022/`。新测试机为
`~/.vphone/init-test-20261022/init-check-01`，独立库、NAT、2 CPU、3072 MB，
使用缓存 iOS 26.6.2 / cloudOS 26.4，未克隆用户现用镜像。

部署发生了中断事件：退出并替换管理器期间，原四台 VM 和 launcher 的 PID
全部退出。具体由退出还是替换触发未定位，不能声称“无影响”。已向用户说明，
按原绑定、原库和原启动参数恢复四台。此后两台 2.8 VM 又报告 VZErrorDomain 1
“内部虚拟化错误”并退出；未再次自动启动。两台 2.9 仍运行。检查时原四台
launchpad.json/config.plist 哈希未变化。原已停止的 test_11 后来目录消失，
本会话未执行删除，原因未核实；没有擅自重建。管理器不再退出或替换，Skill
已纠正“只更新管理器不会影响 VM”的未经验证假设。

测试机恢复首轮 iBSS 重连超时；一次重试期间误停止仍在进行恢复的测试 DFU
进程，导致中断。取消该测试任务并确认其进程退出后，从 bootDFU 干净重试，
恢复 586 秒、CFW 771 秒、firstBoot 67 秒通过；prepare 118 秒、patch 75 秒
未重跑。没有为恢复重试修改旧机。默认 bundle 保持 2.9.0-local.f9f452dc，
新增核心均并列安装，仅修改测试机绑定；中间测试版本不是正式发行标签。

真实 guest 暴露了仅靠 mock 测试未发现的问题：

- profiled 日志明确要求 `com.apple.managedconfiguration.feature-setting.maxInactivity`。
  缺该权限时 setter/flush 不抛错，有效值仍为 60；写后读回使初始化正确失败。
  补充 daemon 权限后，读回 Never 和锁屏空闲值均为 2147483647。
- 现有 IcliKit respring 的 FrontBoard 路径没有完成，launchd stop 回退报 144。
  固定依赖 icli 0.7.17 的 Docs/entitlements.md 指定服务修改需
  `com.apple.private.xpc.service-configure`；补充后 respring 成功。
  两项均校验源码声明及最终 guest 签名，原生测试增加声明断言。
- 新 SpringBoard PID 出现后，旧 unlocked 通知可能短暂保留；单次解锁过早
  返回后又出现锁屏，120 秒观察正确失败。`system.respring` 成功后标记下一次
  `GuestScreenUnlock` 在原超时内等待新锁屏，再调用原按键解锁路径；不在观察期
  保活或重新解锁。实际解锁源码的立即/延迟锁屏回归、原宿主 startup-unlock
  回归通过。业务目录及已运行管理器不需要为此改动。

为桌面和冷启动测试，仅对该测试机调用现有 setup.skip；三个 setup 偏好已写入，
其 respring 当时权限不足，正常停止/启动后 setup.status.pending=false。业务
初始化没有加入跳过设置。首次黑屏截图不算桌面通过；后续已实际截到 Home Screen。
独立重试报告比较证明，先前九个创建阶段的状态和耗时完全一致。
最终使用 `2.10.0-local.199abaf3`，运行中 daemon 哈希与 bundle 内文件一致
（`93863283706957ecf7e0dc1309548340b187a28be6fd5f89245b19716dd26501`）。
初始化约 151 秒通过，Launchpad 十个步骤全绿；120 秒只读空闲观察未锁屏或
熄屏，Settings 的 Auto-Lock 列表截图明确勾选 Never。多次真实失败后仅重试
initializeDevice，前九阶段状态及耗时不变；成功后配置自动启用 unlocksAtStartup。

随后只停止/启动测试机，未发送手动 unlock、Home 或 Power；约 48 秒 vphoned
回应，宿主日志出现 `[unlock] dismissed the Lock Screen at startup`，实际截图
为 Home Screen。每 5 秒只读记录 180 秒，连接就绪后的连续约 156 秒均为
locked=false/screen_off=false，Never 两项值重启后仍为 2147483647。
证据：test-cold-screen-timeline.json、test-cold-desktop.jpg、test-never-checkmark.jpg。
测试完成后正常停止并保留新测试机，释放资源，再按原 bundle 和原参数恢复
两台异常退出的 2.8 旧机；四台旧机均重新显示 running。本次验收通过不抹去
部署中断事件，不能报告为“完全不影响已有运行态”。
最终四台旧机的 device.screen 均可读取，locked=false/screen_off=false；
launchpad.json/config.plist 再次逐文件比较均与部署前一致。全局默认仍为
2.9.0-local.f9f452dc，测试机正常停止，卷剩余约 93 GiB。最终核心 deep strict
验签通过；初始化策略、流水线独立重试、原生 setter、延迟锁屏和宿主开机解锁
测试通过。完整结果索引为 validation-results.json；未提交或混入其他会话改动。

## J-2026-10-22 — 部署 Launchpad 2.8 基础兼容修复

等待初始化验收会话完成后，从当前源码重新构建 Launchpad，保留其后续业务修改；
未使用此前冻结的候选覆盖新代码。版本门槛维持 2.8.0，原生代理和设备初始化
仍分别检查实际功能能力。版本/绑定、创建流水线、初始化策略和原生代理旧核心
拒绝修改测试通过，完整 Xcode 构建及同身份 Apple Development 签名验证通过。

部署前确认没有创建/恢复任务；四台旧机的 launcher 均独立运行，标准输出写入
日志文件。仅向管理器主 PID 发送 SIGTERM，未用应用级 Quit；移动并保留旧 app
全部文件后部署新 app（包含 debug dylib），不就地覆盖运行中的 launcher 文件。
部署前后四台 VM 和四个 launcher 的八个 PID 全部一致；五台机器的 config.plist、
launchpad.json 摘要均未改变，全局默认保持 2.9.0-local.f9f452dc。

新版 Launchpad 对两份 2.8.0-local bundle 执行 verify 均为 passed，不再报告
“需要 VPhone.bundle 2.9.0”。Helper 因二进制变化需重新安装，用户在系统弹窗
完成管理员认证后显示 ready，主机检查通过。未启停任何 VM；test_11 已由用户
确认删除，因此取消其启动验收，不重建、不改用其他实例。旧 app 备份及部署、
检查证据位于 `.build/validation/launchpad-version-compat-20261022/`，旧 app
为该目录下 `installed-before/vphone-launchpad.app`。本轮不修改固件补丁。
## 2026-10-16 冷启动自动解锁超时重试

第二台完成 NAT 首启迁移、Never 设置和 141 秒空闲后，切回 tunnel 冷启；boot UUID 改变，Never 保留，但 77 秒仍锁定。正常停止后 stdout 明确为 `[unlock] could not unlock the guest at startup: the Lock Screen did not dismiss in time`。现有宿主 90 秒观察窗口包住单次 60 秒 RPC，但第一次此类超时会直接退出整个流程。最小改动仅在窗口内重试两种明确的屏幕启动超时；密码/其它失败仍结束。新增测试编译实际 `VPhoneGuestControlSystem.swift`，只替换测试传输，旧 HEAD 在 timeout→success 序列失败，新代码通过，完整 bundle 构建、签名与 preflight 通过，两台均实测自动解锁；随后 Workstation 再次冷启动两台，UUID 改变、桌面/未锁/亮屏/Never/新哈希均 pass。未增加固件补丁或改变用户密码。


## 2026-10-16 第二台首启迁移 panic（已恢复，单一原因未证实）

第二台 CFW 成功、health/签名哈希正确，Setup 完成，四个用户 IPA 安装读回成功，仍不能证明桌面可用。`boot-custom-setup-complete.log` 最终记录 `datamigrator plugin SpringBoard.migrator hang` userspace panic，Boot UUID A3D1B973-9E8E-4569-9294-39AA833C8A06。早前据进度变化判断继续观察，最终判为首启失败；尚无证据归因代理、应用包或 hypervisor concealment（此项 standard 关闭）。已停机留 APFS 检查点并暂用 NAT 启动取证，这是故障当时状态。后续 NAT 对照重启自然完成迁移，恢复 Idle Miner 后五 App 首屏通过，再切回 tunnel 冷启动通过；未清理图标缓存或修改内核，单一原因仍未证明。最终默认入口已切两新机，旧机与入口备份保留。

## 2026-10-16 应用安装脚本与 SKILL

- 用户要求把已有软件安装流程复用为脚本/技能。原应用来源是本机已有 IPA，Facebook 是从旧机导出的解密应用包，不是通过 App Store 批量下载；Instagram 仍无 IPA。
- 新增 `skills/vphone-app-install`，全局 `~/.codex/skills/vphone-app-install` 符号链接发现；zsh 包装临时编译现有 `VPhoneAPIClient.swift` 与 167 行宿主助手，产品和 guest 不增加依赖。
- 实测发现大包安装可超过共享 HTTP RPC 130 秒等待，超时后客体仍在执行。改用现有 WebSocket API 等待原生 `apps.install`，设 10 分钟上限，非零失败不自动重试。共享客户端用 NSString 追加 WebSocket 路径，空根 URL 会无法生成 URL；调用方把根路径规范为 `/`，不修改产品源码。错误输出保留 `VPhoneAPIError.description`，避免只显示泛化 NSError。
- 参数、非法选项、loopback 边界、空根路径、带空格路径和结果解析 self-test 通过；实际 Subway Surf 3.69.2 完整安装、读回、启动并持续 20 秒，脚本退出 0。前台截图年龄页正确，未提交年龄或接受条款。证据在 `.build/validation/image-upgrade-20261016/install-skill-subway-websocket.log` 与 `install-skill-subway-front.png`。URI 错误残留的两个本轮上传文件已精确删除；不删除旧应用数据。

用户授权从当前新版源码重建两台镜像，保留应用，登录状态无需迁移。按官方 schema 2 边界保留旧镜像并准备独立新机，未修改旧配置冒充升级。当前源码完整构建为 `VPhone.bundle 2.8.0 (35)`，固定 runtime、固件版本/校验、应用来源及剩余验收见 [分支与运行边界](branch_workflow.md)。构建/签名/bundle admission/host preflight 均通过，两份官方 IPSW 完整性通过。

旧 official 的 Subway Surf 与旧 custom 的五个应用均已找到可重装包；其中 Facebook 581.0.0 从旧 guest 导出应用目录，确认 cryptid 0，只恢复 Mach-O 执行权限后打包，IPA SHA-256 为 `7c7e4e771b5469f9260ff2f6d01b551a98db7c8b734c0980b93fe41cc0cff83f`，ZIP 校验通过。应用尚未在新版安装或启动，不能称为迁移成功。

首次尝试固定 runtime 的完整 `sudo -n ... vm create official-2x-20261016` 命令退出 1：`sudo: a password is required`，当时目标目录不存在。现场无 Launchpad 已安装特权 helper 或 bundle store。**后续纠正：不能由此断言必须由用户去终端执行，也没有证据证明“旧认证过期”就是过去成功而现在失败的原因。**

用户质疑后，复核 J-2026-09-22-16 与旧官方 `1.0.14` 创建器（GitHub MCP 同版本源码佐证）：旧流程使用 `cfw install --root-popup`，实现是 `osascript` 的 `do shell script ... with administrator privileges`。它使用系统认证弹窗，不是自动操作 Terminal。新版 CLI 移除此内置提权入口但支持以 root 运行。已通过同类原生认证调用新版固定 CLI，显式传入当前用户 `SUDO_USER=tubao/SUDO_UID=501/SUDO_GID=20`；现场确认 root 的 `vm create` PID 75298 和新目录已出现，创建实际开始。没有读取或输入密码，没有操作被 CUA 禁止的 Terminal。错误在于此前只验证 sudo、未复核旧系统认证入口便向用户报告终端是唯一方法。

两台旧宿主已按精确命令行发送 SIGINT 正常停机，旧盘无持有进程；不直接终止 Virtualization XPC。第一台为 `official-2x-20261016` / `standard`，串行创建并监控空间；恢复日志 `.build/validation/image-upgrade-20261016/create-official.log`。此时仅创建进行中，未证明恢复/CFW/首启成功。旧启动入口和 Workstation 映射仍保留，未宣称已切换。

首台日志确认 `fw patch` 应用 169 条 CFW 补丁，已进入混合固件恢复并完成系统文件传输。主机交换空间同期增长到约 29 GiB，卷空闲降至约 11 GiB；只清理本轮新下载、已完整解包的 iPhone IPSW 缓存（11,254,382,122 字节），回到约 23 GiB，未删除旧镜像、应用包或当前恢复树。第二台创建前需重新下载并校验同一官方源。

混合固件恢复随后成功（`Status: Restore Finished / DONE`），版本已落盘；CFW 安装因新版要求卷可用容量大于 50 GiB 而停止，整体退出 64，未首启、无 `PatchReceipt.plist`。先前只按稀疏盘估计空间，没有提前核对安装器这一固定要求，是本轮准备不足。停止后卷空闲回升至约 36 GiB，全部 VM 进程已退出。应腾出空间后续跑同一新机的 `cfw install`，保留已经成功的恢复结果。

用户确认清理列明缓存并继续。已用官方 `uv cache prune`（不强制、不直接删除 uv 缓存文件）清理未使用项，报告 326,229 文件 / 11.0 GiB；清空获准的 Homebrew/pip 下载缓存内容。受 APFS 共享影响，真实可用容量仍不足 50 GiB。继续定向核对 CFW 消费路径，清理本轮已成功 DFU 恢复使用的独立 `OS` 大镜像（7.625 GiB，保留 CFW 使用的两个 Cryptex 文件）、已消费的 cloudOS 压缩包与导出 Facebook 的重复 Payload（保留校验通过的最终 IPA）。未删除旧镜像或其它工具缓存。Foundation 的安装器同款容量指标达到约 51.25 GiB 后，系统认证续跑 `cfw install`，已通过空间检查并开始挂载；日志 `cfw-official.log`，此时安装仍未完成。

随后 `cfw install` 成功退出 0，快照切换、guest receipt 与恢复树清理完成。普通用户启动和一次冷启动均连接 vphoned，哈希匹配签名副本。`setup.skip` 的 respring 返回缺少 entitlement，写入的 setup 偏好经正常冷启动实际生效；未扩大权限或改源码。Never 页面勾选、退出 Settings 后 API 读回与 134 秒无输入亮屏/未锁定均通过，最后的冷启动持久性另测。

原 Subway 3.69.2 IPA 已装入新容器。首次启动在 Metal 编译等待上触发 FrontBoard 11.70 秒 scene-create watchdog（`0x8BADF00D`，不是 EXC_GUARD）；同次开机再启动 PID 658 持续运行并显示年龄输入页。未代填年龄或接受条款，未宣称全新开机首次启动或跑酷已通过。原始两份 crash、安装响应、前台进程与截图保存在本轮验证目录。

CFW 同时提示因缓存 IPSW 已清理，缺少 iPhone product repair 的 d47ap 原树。已从本轮解包树的原件验证 SHA-384 与 iPhone 原 BuildManifest 的 Digest 完全一致（63,949 字节），按安装器提示保存到 `FirmwareOriginals` 下，结果在 `board-tree-recovery.json`；未伪造或修改设备树，也未将修复准备当作 guest 安装成功。只读盘点发现其它用户缓存可腾出空间，清理范围需单独确认，不能删除旧镜像替代。

## J-2026-10-16 — 两台旧 VM 的 Mac 代理入口（仅宿主完成）

用户要求复用 Mac 代理，让 official/custom 内的 Instagram 使用不同出口，尽量不在 guest 安装软件；地区不限。现场客户端是 Clash Verge 2.5.8 / Mihomo v1.19.32，当前 Bitz+Net 订阅、rule 模式和 TUN 已启用。两台仍是 1.0.14 旧宿主和 NAT，未迁移到 2.x。

- 当前订阅的扩展覆写 `~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/mV3VtfToOedl.yaml` 增加两个 mixed listeners，仅绑定 Mac 虚拟网络地址 `192.168.64.1`：`17891/vphone-official` 固定选择“🇯🇵 日本-广东专线 BGP”，`17892/vphone-custom` 固定选择“🇺🇸 美国-广东专线 BGP 1”。用现有内核 `-t` 校验成功，再经 Clash Verge“重新激活订阅”确认生成配置仍包含两个入口。未改变原 7890 端口、568 条规则、主策略组选择或 `allow-lan: false`。
- **验证仅在 Mac 发起**：分别显式经过两个代理入口访问 ipify，观察到 `178.249.213.185` 与 `79.127.245.214`，重新激活后为 `178.249.213.185` 与 `79.127.245.215`。节点出口会变化，不能称为静态独享 IP，也不能据此声称 guest 或 Instagram 已走代理。
- **guest 未配置、Instagram 未验收**：官方实例用户应用只有 Subway Surf；定制实例为 VPHONE Probe、Facebook、Subway Surf、wooshort、Idle Miner，两台均无 Instagram。Downloads 未找到 Instagram IPA。官方实例停留锁屏，自动手势及键盘未能进入桌面；已请用户手动解锁并提供既有 IPA 本机路径。未修改 guest 代理、网络配置、认证、身份或固件。
- 验证期间另一个 vphone-ws 生命周期任务曾重启两台；原测试日志明确记录 SIGINT，不能归因于 VM 崩溃。用户随后确认已暂停其它操作；保留当前运行实例，未再关闭它们。
- 原始配置与候选完整配置备份在 `~/.vphone/network-backups/proxy-20261016/`（目录 0700、文件 0600，含订阅凭据，不提交）。宿主结果在 `.build/validation/vm-proxy-20261016/result.json`。回退：恢复目录中的 `mV3VtfToOedl.yaml.original` 到同名订阅扩展文件，再点“重新激活订阅”。监听地址依赖 VM 创建的 bridge100；Mac 重启后应先启动 VM，再重新激活订阅，未验证无 VM 时的自动恢复。
- 下一步：在真实以太网设置中核对能否分别指定 HTTP 代理 `192.168.64.1:17891/17892`；检查 guest 公网 IP 和 Mihomo 的入站/节点记录；安装并启动同一 Instagram 原始 IPA 后观察其真实连接。HTTP 代理不能证明接管绕过系统代理的 TCP 或 UDP 流量；未通过 App 验收前不能交付为两台全流量隔离完成。

官方依据：[Mihomo listeners](https://wiki.metacubex.one/config/inbound/listeners/)、[API](https://wiki.metacubex.one/api/)、[Apple HTTP 代理范围](https://support.apple.com/id-id/guide/deployment/dep1129ff8d2/web)；项目 NAT/TUN 边界见 `Documents/Guides/networking.md`，不可把当前源码的 `tunnel` 能力直接套给旧镜像宿主。

## J-2026-10-13-43 — 当前旧 VM 的中文 ⌘V 粘贴

## J-2026-10-16 — vphone-ws 生命周期验证

采用相邻仓库 vphone-ws + 两台现有完整旧宿主。实例发现、GUI 同时启动、双向独立停机、窗口切换均实测；新增 variant/宿主路径透传、宿主 SIGINT 停机、链接导出路径解析。63 项测试通过。完整归档因本卷仅剩约 17 GiB 暂未执行，没有生成大文件。入口 `workstation.command`；完整边界与证据见 [验证报告](workstation_validation_20261016.md)。未改原 start.sh、guest 固件或 IPA 安装流程。

当前 `stock-regular-guard-20261008` 用官方 1.0.14 基线的本地兼容宿主补齐文本粘贴：在 `NSApplication.sendEvent` 中先于 `capturesSystemKeys` 拦截 ⌘V，通过已有 vphoned v1 剪贴板接口确认文本后发送 HID 粘贴键。视图覆写和普通菜单单独无法拦截，是两次真实失败验证后的定位结果。最终 Safari 完整显示两组中文，第二组含中文标点与 emoji；捕获系统按键的 AppKit 回归测试通过。`start.sh official` 已切换，原官方包保留；未更新 guest daemon、固件或配置，未重刷或改变身份。2.x 完整构建虽成功，但官方明确不支持旧 schema 就地升级，未绕过版本检查。提交、哈希、证据和回滚见 [验收记录](Host/legacy_clipboard_20261013.md)。

## J-2026-10-10-42 — 清理、官方 APFS 重排与自动化镜像不锁屏基线

按用户授权清理旧整机备份、固件中间文件与可重建缓存，卷净回收约 43.21 GiB。复用官方 2.9.2 rebase 离线算法，在临时 schema 2 包装内重排旧版定制盘；两盘全量 SHA-256 与 10 个身份/启动文件在启动前均不变，新增共享约 12.31 GB，临时包装及硬链接全部移除。两份盘去重物理占用约 30.08 GiB，仓库与 ~/.vphone 最终约 34.79 GiB。

两台原 1.0.14 VM 并发启动、独立 ECID 与 vphoned 连接正常，Settings 可操作。用户新增基础要求：所有镜像自动锁定设为 Never。现有官方/定制两份已设置并经超过 2 分钟无输入的真实窗口检查，均保持亮屏未锁定；开发 skill 和 branch_workflow 已加入新建/导入/恢复后的同等验收要求。未改变密码；未再次重启验证偏好，也未实现开机自动解锁。Subway 既有花屏仍未通过。完整证据与限制见 [报告](storage_sharing_20261010.md)。

## J-2026-10-08：同步官方主线至 dfcfae9c（仅源码）

- 来源：GitHub MCP 核实 `Lakr233/vphone-cli/main` 为 `dfcfae9c608c432a9a63f846d5cda8272fde0b82`；fetch 与其一致。旧官方基线为 `9c23c8a`，相差 636 个提交。原业务 HEAD `d23154b` 已保存为 `codex/pre-upstream-sync-20261008`。
- 处理：本地 main 跟踪 upstream/main，业务分支合并官方；采用上游 Xcode workspace、原生实现与 patch sets/presets。研究历史移至 Research 根目录。旧 Python MobileGestalt 实验及依赖已移除的测试仅保留在备份分支，未移植、未启用；旧 EXP wrapper 现在明确拒绝操作。独立取证工具保留，start.sh 仍明确使用旧版运行产物。
- 验证：Xcode 27.0 下 VPhoneCoreKitTests 409 项/50 suites 通过；本地工具 13 项通过；guest 的 loader-links、vcam-dataplane（124 checks）、vcam-prewarm（19 checks）、installcoordination-persona 均通过；三个本地 shell 入口语法通过。日志在 `.build/upstream-sync-*.log`，核心测试 xcresult 在 `.build/upstream-sync-tests/Logs/Test/`。
- 限制：同步前可用磁盘约 7.7 GiB，测试后约 6.3 GiB，未执行完整 VPhone.bundle 构建；未验证新版宿主/daemon 与现有固件组合。没有启动、停止、重刷或迁移 VM，没有推送。源码同步不等于新版自动化已经部署。
- 后续：按 Research/branch_workflow.md 的当前构建入口，在空间充足时完成 bundle 构建与独立运行验收；需要旧 MobileGestalt 实验时先按新 patch-set 机制单独迁移和验证，不恢复旧流水线。

# vphone 开发与排障记录

## J-2026-10-08-41 — 按用户授权收敛为官方/定制两个工作镜像

删除旧 vm、临时 cow-test-a/b 和默认 Regular；保留官方 Regular+官方兼容选项及 vm-fresh 定制版。停机物理 extent 全量检查两份剩余盘共享 0 字节。start.sh 新映射 official/1 与 custom/2，默认官方，官方 app 独立于本地构建并固定 1.0.14。历史备份和取证仍保留；默认 Regular 整机已删除，以本条覆盖 J-40 及更早的全量保留状态。官方安装过程写入包内 root Python 缓存导致 seal 检查失败，重新从已校验 ZIP 解出正式 app 后签名通过；旧带缓存 app 未用于正式入口。详情及清单见[专项报告](subway_stock_comparison_20261008.md)。

删除共享对照源后，重新启动经 118 文件验证的官方发布程序；主菜单及实际跑酷（计分 33）仍严重花屏，证据 consolidation/official-unshared-menu.png 与 official-unshared-play.png。两份当前工作盘共享为 0，因此它们之间的实时块共享不是症状必要条件；不能从删除源推导已排除所有历史克隆/快照因素。最终官方 VM 留在主屏，定制 VM 停止。

## J-2026-10-08-40 — Subway 排除 CoW 的独立物理副本受剩余空间限制

目标卷仅约 3.65 GiB 可用，当前 Regular 分配约 17.07 GiB，无法在保留全部现有实例的前提下制作普通副本。未删除 VM、未新增克隆，已请求至少 25 GiB 空闲位置或明确清理范围。确认宿主为 macOS 27.0.1/M4；上游 #624 分块串流死锁及 #493 新 cloudOS 黑屏修复均未证实适用于本例，未擅自升级。官方兼容 VM 宿主收到 SIGINT 后退出，磁盘无打开句柄，所有证据保留。详见[专项记录](subway_stock_comparison_20261008.md)。

## J-2026-10-08-39 — 官方 Regular 兼容配置也复现 Subway 严重 3D 花屏

用户完成游戏引导后报告“也花屏”。现场核实官方 1.0.14 发布 app、stock-regular-guard-20261008、Regular + 官方 force-exc-guard；主菜单大量拉伸几何及重复贴图，实际跑酷计分 35 时仍严重损坏，2D HUD 清晰。截图 guard-user-corruption.png / guard-play-corruption.png 已保留。图形验收失败，证明本 fork 定制和 EXP 不是必要条件；尚不能锁定 GPU、同一 IPA、宿主或官方兼容补丁，也未排除 APFS 克隆因素。独立默认 Regular 保留不变；详见[对照报告](subway_stock_comparison_20261008.md)。下方 J-38 的等待游戏引导状态已被本条更新。

## J-2026-10-08-38 — Subway 非定制对照：默认 Regular EXC_GUARD；官方兼容配置已进入游戏年龄页

官方 1.0.14 原始发布包在新独立磁盘恢复 26.1/23B85 Regular，CFW 退出 0；用户完成系统设置及配对，同一 Subway 3.69.2 IPA 安装成功。默认 Regular 在 Crashlytics 初始化 `task_swap_exception_ports` 出现 EXC_GUARD，与上游 #291 相符；不能当作花屏证据。

从原始输入用官方 app 分别生成默认及 force-exc-guard 内核；默认与实际部署 payload 一致，兼容配置精确相差 4 字节。保留默认独立镜像停止不变，在另一个 APFS 克隆部署官方 delta，核验容器和回读哈希；已实际加载到游戏年龄确认页，等待用户处理个人年龄及首次提示。3D 花屏仍未完成对照，不能归因。此兼容副本不是默认无选项配置，且仍有 APFS 克隆变量。证据、边界与下一步见[专项记录](subway_stock_comparison_20261008.md)。旧 VM、备份、固件均保留；无生产代码修改。

## J-2026-10-08-37 — APFS 真实 iOS 克隆：并发、文件隔离、重启与 App 验收

保留独立 vm，对已停止 vm-fresh 使用 Apple clonefile 创建库外 A/B 两实例。MCP 核实官方 3823a553 的 10 月 6 日新身份克隆研究，按其语义只重建 ECID/MAC，保留同刻 Disk/NVRAM/SEP；未使用本地会删除 NVRAM 的旧 clone 入口，未升级运行产物或改固件。当前版本 Core 132 项/16 suites 通过；IPA 签名 1 pass/1 expected failure。

A/B 同时进入 iOS 26.1、ECID 不同且重启保持。分别上传 1 MiB 文件，互不可见；重启后分别下载，SHA-256 完全一致。A Probe 重装后可启动，并在菜单退出再冷启动后继续运行；wooshort 在独立 vm 与 A 均完成关卡连线；B Subway 可启动、计分和暂停，但 3D 严重花屏，缺少相同 App 对照，不能判定克隆方案导致或全部 App 通过。

测试中临时截图客户端截断响应后宿主退出，SIGPIPE 为假设；另一次错误向磁盘持有者 Virtualization XPC 发 SIGINT 导致 VZError 1，属于测试操作引入，不能计为自发崩溃或正常停机通过。改用完整响应 helper 与 vphone Quit，最后 launcher exit 0。未确认的新电脑信任未执行；通过现有 vsock UI 完成读写验收。

停机后全 Disk.img 物理 extent 并集：源 24.28 GiB，A 新增 0.778 GiB，B 新增 0.725 GiB，源+A+B 共 25.78 GiB；两个克隆合计增量 1.50 GiB。独立 vm 与源、A、B 的物理区间均无交集。源最终全量哈希未变。四个镜像全部保留并停止；详见 [完整报告](apfs_clone_validation_20261008.md)，本地原始证据 `.build/validation/apfs-vm-20261008/`。此结果不证明 IDFA/SEP 密钥独立、所有 App 兼容或长期压力稳定。

## J-2026-10-05-36 — APFS 写时复制与现有 vphone clone 空间隔离实测

在宿主 APFS 上创建临时 2 GiB APFS sparsebundle，以独立卷空间统计排除宿主其它写入。写入 256 MiB 随机数据作为测试 Disk.img（不是可启动 iOS），使用现有已签名 `.build/vphone-cli.app/Contents/MacOS/vphone-cli vm clone --library-root <测试卷> source cloneN` 克隆三份，再直接调用 Apple `clonefile(sourceDir, targetDir, 0)` 克隆一份。未执行普通复制回退的直接 API 调用返回成功。

源数据使测试卷增加 268447744 字节；三份 vphone 克隆合计仅增加 20480 字节，各命令耗时 13–18 ms；额外直接 clonefile 克隆增加 12288 字节。向 clone1 覆盖写入 16 MiB 后，卷占用增加 16769024 字节；再向源文件另一位置覆盖 8 MiB，增加 8388608 字节。SHA-256 验证所有初始副本与源一致、修改副本不影响源及其他副本、修改源不影响副本、删除源后副本内容保持完整，全部通过。各文件 st_blocks 仍分别报告 256 MiB，证实不能用各文件 du 简单相加判断共享后的独占空间。

验证范围是 Apple APFS 存储机制及当前 vphone clone 命令的实际文件复制行为；未启动客体，未验证克隆 iOS 的冷启动、并发运行或独立身份。当前本地 clone 会清理部分身份文件，不能据存储隔离推导 IDFA 独立。现用 vm/vm-fresh 未修改。临时测试卷已正常卸载，sparsebundle 已删除；仅保留 `.build/validation/apfs-cow-check-20261005/result.json` 测量数据。

官方对照：https://github.com/Lakr233/vphone-cli/blob/main/Documents/Guides/create-and-run.md （MCP 本轮读取，最新上游注明 APFS CoW 并保留完整机器身份，区别于本地旧实现）。

## J-2026-10-05-35 — Trima / ONE Pangle同源对照候选获取未完成

用户授权继续用其它接入Pangle的APP做VM2对照。MCP读取Pangle官方Trima案例28165（2025-09上线AppOpenAds，后台返回前台）及ONE案例28133（明确iOS插屏与视频，包含激励变现）；官方接入记录不代表当前IPA或VM展示成功。

Chrome既有登录ARM Store，日本区Trima1502193377 / jp.co.incrementp.MileMobile版本10.4.4，ONE1373644984 / jp.onefinancial.one版本7.50.0。实际下载点击多次被广告新标签截获，逐一关闭本轮广告标签后两个最新包均曾显示Decrypting/Waiting in queue、预计2秒，未出现Download IPA。刷新后恢复Decrypt this App，未取得包；不声称后台任务仍运行。ONE历史6.2.1虽标likely already available，实际请求返回Free users can only access previously decrypted versions / Upgrade to VIP，state idle，不能下载。Trima历史列表出现6.5.0/6.1.1/6.1.0候选，但尚未成功提交并取得任何历史包。没有购买订阅、绕过会员或提取登录凭据。匿名官方前端info接口返回401，未改用其它身份调用。

当前Downloads无新IPA，只有此前Subway/Idle Miner。VM2仍connected ECID2AF5A35422349AA0/IP192.168.64.46，未安装或启动候选，未启动日志采集器、未改网络/设备/SDK。获取阶段阻塞不能当作Pangle VM填充失败证据。证据与页面快照位于.build/validation/trima-comparison-20261005/，两个浏览器入口保留待续。后续需先获得有效IPA，再静态验证SDK、安装、触发实际广告并记录Pangle来源。

来源：https://www.pangleglobal.com/resource/28165 、https://www.pangleglobal.com/resource/28133 、https://armconverter.com/store/jp/1502193377 、https://armconverter.com/store/jp/1373644984 。

## J-2026-10-05-34 — Idle Miner黑屏广告层可关闭，130→260奖励领取闭环补验通过

用户报告打开游戏黑屏，现场VM2仍connected，客体黑屏右上白色×可见。点击×立即出现Idle Cash Gain明确130→260翻倍奖励，点击Collect后恢复矿场正常生产。没有重启VM、重装IPA、修改SDK或身份。将J-33的关闭/奖励未验收更新为通过；本次仍为AppLovin广告，不能推导Pangle填充或归因成功。黑屏具体渲染原因未定位，恢复不等于SDK内部故障已修复。截图与新增采集日志、更新报告在.build/validation/idle-miner-20261005/；collector已停止，VM保留正常矿场。

## J-2026-10-05-33 — Idle Miner VM2真实激励广告展示，来源AppLovin，关闭/奖励未验收

复用start.sh 2重启vm-fresh，ECID2AF5A35422349AA0/IP192.168.64.46。游戏首次条款未再出现；ATT选择不追踪。通过真实采矿完成矿井1十级、三经理自动化、开启矿井2。Boosts显示Disconnected且2x Use不可用；冷启动游戏后Idle Cash Gain出现离线1m28s收益130，点击x2 Free实际进入视频及Top Lords可玩广告。

信息菜单About AppLovin Ads与日志ALAppLovinMediationAdapter13.6.3一致，SKAdNetwork ludvb6z3bs对应AppLovin，本次不能算Pangle成功。appstored拒绝归因登记（ASDError1216/source adam ID不匹配），产品查询512，AppLovin报告REWARDED storekit_error及unexpected_state。可玩倒计时消失后未见关闭控件，未回到游戏、未确认130→260奖励；普通矿场现金增长不计为奖励。TLS-1200 URL被private遮蔽，不强行归因Pangle或整机断网。完整证据及下一步边界见.build/validation/idle-miner-20261005/report.md。本次日志采集已停止，VM保留；未修改测试登记、网络、固件或广告平台参数。

## J-2026-10-04-32 — Idle Miner候选安装启动成功，首次年龄/条款待用户操作

用户确认安装运行ARM Store候选后，检查发现VM2已停止；复用start.sh 2启动vm-fresh，ECID不变、IP变为192.168.64.45，host PID15834。vphoned连接恢复后，Apps→Install IPA/TIPA选择前条目同一下载包，内置安装器明确显示Installed via built-in installer as User: IdleMiner.app (com.fluffyfairygames.idleminertycoon)。devicectl启动成功，客体PID532，游戏出现Legal Terms and Privacy首次引导，要求年龄滑条，Confirm明确表示接受Terms and Conditions。未猜填年龄、未接受条款，按电脑操作工具的当时确认要求交由用户完成；没有触发广告，不能宣称填充成功或失败。

证据.build/validation/idle-miner-20261004/first-launch-terms.png与system.log。本轮syslog采集器已CtrlC停止，保留VM2及游戏引导页，未登记测试设备、未改网络/固件或SDK。用户完成引导后继续游戏正常进度、寻找Boost/激励入口并核对实际Pangle来源。

## J-2026-10-04-31 — 用户提供ARM Store入口后成功取得Idle Miner Pangle候选包

用户提供https://armconverter.com/store/us/1116645064页面，纠正此前候选获取受阻的结论；先前decrypt.day安全拒绝仅适用于该站，不推广为所有下载入口。Chrome连接ID已变为3，现场读取用户现有页面，下载控件初次读取后变为Decrypt this App；按可见控件请求该版本，页面Decrypting app→Download IPA，通过控件downloadMedia下载完成，未绕过此前受阻站点、未猜API或输出下载凭据。无需反复点击广告遮挡。

文件：/Users/tubao/Downloads/com.fluffyfairygames.idleminertycoon-5.64.1-Decrypted.ipa；bundle com.fluffyfairygames.idleminertycoon，版本5.64.1/build97855；SHA256 23ed60a760335d2f4274bf89c5a198eb8a0b6e9d420a9cabd5a19107a3a7202b。ZIP testzip通过，主程序IdleMiner和UnityFramework的cryptid=0；UnityFramework内PAGRewardedAd/PAGConfig/Pangle符号存在，PAGAdSDK.bundle/AdsGlobalSDK.bundle版本8.1.1。这是当前包包含Pangle的静态证据，不证明VM2实际填充成功，也不能由解密状态证明第三方包绝无其它修改。

现场截图.build/validation/pangle-ipa-candidates-20261004/armstore-ready.jpg。尚未安装或运行；下一步VM2实际加载/展示/来源确认前，按电脑操作工具要求对第三方软件安装进行当时确认。保留原Subway和Orblino，不修改VM身份、网络或广告测试登记。

## J-2026-10-04-30 — Pangle第三方IPA候选与官方商店获取受阻

用户要求寻找其它接入Pangle且能实际加载广告的IPA。MCP查得官方变现案例：Idle Miner Tycoon（App Store1116645064，激励/Boost与离线收益翻倍），Steppy Pants旧版（1094138419，官方明确iOS接入），Trima（1502193377，2025-09开始AppOpenAds，后台返回前台展示）。这些为历史或近期发布商证据，均未完成当前IPA静态检查及VM2动态Pangle填充验证。Steppy Pants Halfbrick+商店说明无广告，排除；公开检索的Idle Miner下载页面多标MOD/去广告，未下载。

本机Downloads仅Facebook、Subway原有IPA；连接的真机未安装上述候选（devicectl定向查询无结果），本机无ipatool。decrypt.day被浏览器站点安全策略阻止，未绕过、未改用其它通道访问该站。改查官方获取路径：VM2（ECID2AF5A35422349AA0、IP192.168.64.44）实际安装有App Store，devicectl启动成功，UI进入What's New介绍页后点Continue，停在Personalised Ads页；两个选择按钮灰色，点击关闭、滑动、一次terminate-existing冷启动后仍停留，未见下载页面。无法确认关闭选择已生效，也没有开启个性化；没有输入Apple账户、购买或新增软件。本轮没有日志取证定位商店阻塞根因，不据此声称App Store服务或VM整体不可用。

证据截图：.build/validation/pangle-ipa-candidates-20261004/appstore-blocked.png。未获得新IPA，未新增Pangle成功样本。后续需要可用原版解密IPA或可正常下载/导出的官方设备路径，再验证实际展示来源；普通商店下载不等于解密可重签包。未修改SDK、固件或网络，保留VM2，无新增采集器。

官方来源：https://www.pangleglobal.com/zh/resource/5e95889b678921000f41e6f4 、https://www.pangleglobal.com/resource/27819 、https://www.pangleglobal.com/resource/28165 、https://github.com/majd/ipatool 。

## J-2026-10-04-29 — Subway激励成功场景还原与相邻Orblino正式位对照

同VM2现有网络，冷启动Subway(PID963)、开始游戏→暂停退出→结算金币Ad入口，Township视频再次播放，信息页Mintegral，金币11500→12000。本次奖励500，底部Watch Video为3钥匙，保留与10-03原1500位差异；未清缓存，19:14已有匹配元数据，19:15:33展示不能称首次加载。系统ATT Allowed，SDK个性化值未知；可玩页卡Loading、归因1216拒绝仍出现。

紧邻Orblino独立冷启动PID1020，19:19:38.718066→19:19:40.528093，正式模式8895377/983634549、必要数据开/个性化关，仍rewarded_load20001。当前VM未登记Pangle测试设备，未更改平台/网络/固件/SDK。成功源Mintegral与失败源Pangle不同，跨源样本证明当前VM能够播放及业务奖励，不证明Pangle供给成功。详细报告与新截图、双应用日志.build/validation/subway-comparison-20261004/report.md；本轮两采集器均停止，VM保留。



## J-2026-10-04-28 — Pangle 后台报表与当前 VM2 测试身份核对

登录后只读核验本应用8895377/包名com.Orblino-Weave、普通激励983634549均运行中、自动定价，合规中心无可见停填/限填问题。UTC+8报表2026-09-27～10-03按应用/正式激励位过滤并按日期/国家分组：10-03日本，非美国请求2、返回0、展示0。日本在应用变现支持列表；不能归因中国大陆出口，不能将汇总记录逐笔关联客户端调用。

平台vphone-exp-orblino为测试中、真机登记暂停。现场没有运行VM进程，使用既有start.sh 2启动vm-fresh / ECID2AF5A35422349AA0（IP192.168.64.44）；devicectl启动已安装Orblino成功。原有广告页本地测试模式读取非零IDFA，与后台两条登记均不匹配，只记录布尔false。后台测试中设备不是当前VM2；缺少登记只影响测试验收前提，不能唯一解释正式20001。未提交新标识或更改后台设置，已请求用户明确授权登记；个性化仍关闭，本轮没有再次加载广告。

详细事实与边界见外部Orblino data/pangle-vphone-20261003.md新增10-04段。没有源码或固件修改，无需重复编译打包。真实视频/关闭/奖励闭环仍未通过；保留已启动VM2。


用户随后明确只验收非测试设备正式广告，取消登记方向；Pangle表单已取消，当前VM2仍未登记。独立冷启动PID638、正式模式8895377/983634549、必要数据开启个性化关闭，18:26:28.732291→18:26:30.928862实际按钮请求仍rewarded_load/com.PangleAdSDK/20001/no_fill。state0→1、runtimeAppID=nil→8895377，仍未展示发奖。新增证据.build/validation/orblino-ad-20261004/formal-system.log、formal-no-fill.png；采集器停止。此前“等待设备登记授权”由用户最新需求取代，不再把补登记当任务修复。


## J-2026-10-03-27 — Orblino 与 Mintegral 成功样本对照、Demo 配置修复

已修复外部 Orblino 项目 Demo App/广告位混用，更新当前官方 waterfall Demo IDs，并将原生测试页现有激励加载按钮固定到底部。恢复锁定 8.3.0.6 SDK 缓存缺失的 arm64 二进制，checksum 与 SwiftPM 相符；Debug 构建成功，Orblino-Weave-Flow.ipa 已通过内置安装器更新安装 VM2，并实际冷启动操作。

14:34:33–35，独立 Demo 进程（8025677/980088192，PID4307）返回 rewarded_load/com.PangleAdSDK/20001/no_fill；14:41:21–22，独立正式进程（8895377/983634549，PID4399）同样返回20001。两次页面操作 canRun=true、attached=true，必要数据开启，个性化保持关闭。正式运行时 state 0→1、runtimeAppID=nil→8895377。当前卡在加载阶段，未验证展示、关闭或奖励业务闭环；不能认定虚拟机封禁。Demo 平台测试状态尚未核实，真机历史个性化对照不是本轮成功证据。

Subway 已成功的来源为 Mintegral，不能跨网络证明 Pangle 供给。未改 vphone 固件、身份、网络或生产运营开关。详细报告：外部项目 data/pangle-vphone-20261003.md；日志、截图、源文件备份和调试 IPA：.build/validation/orblino-ad-20261003/。已向用户询问个性化对照授权与本应用 Mintegral 配置，未收到答复前不实施依赖步骤。

继续验证：增加既有官方最小调用的底部“对照”入口，Debug 重编译、更新安装、独立冷启动 PID9807。21:59:46.629 PAGSdk 初始化成功（state=1），21:59:47.902 官方 PAGRewardedAd.load 直接返回 reference_rewarded_load/com.PangleAdSDK/20001；App8895377/slot983634549，PAConsent=0，adString/extraInfo=nil。公共封装不是本次失败的必要条件，仍未展示或发奖。新 IPA SHA-256 3f3af9fd89722d7bab8fa3e010b8a185f721427d65ea6e2dde8dbee1889e7cd9。devicectl/ios-deploy 的 bundle 容器查询不可用，按系统日志容器路径用现有 File Browser 下载 Library/Caches/logger 本轮日志成功；证据 run3/2026-10-03-21-58-37.log 与 reference-no-fill.png。Pangle publisher 重定向到登录页，等待用户登录后只读排查；个性化授权未改变。


## J-2026-10-03-26 — Subway Surfers 实际激励广告源与归因异常

虚拟机 2（vm-fresh / ECID 2AF5A35422349AA0），12:04 点击结算页 Watch Video / 1500 一次，Township 视频实际播放，完成后金币 10,000 → 11,500。视频关闭后的可玩广告页左上 i 展示 Report Ads 与 Mintegral Privacy Policy；统一日志 12:04:08.586529 的 Township 目标 App Store ID 638689075、源 512939461、adNetworkId=kbd757ywx3.skadnetwork，与 Unity 官方 Mintegral 映射一致。确定本次素材展示与归因声明为 Mintegral；同时出现的 AppLovin 播放资源/adapter 不能证明竞价赢家或完整转售链路。12:04:12 另一个目标 ID 1606549505 的 lookup 不归入本次 Township 展示。可玩页停在 Loading Playable Ads；系统 12:04:08.897043 因 bundle ID 与源 adam ID 不匹配（ASDErrorDomain 1216）拒绝登记 impression，不能由奖励到账推断归因正常。证据与截图保存在 `.build/validation/subway-ad-source-20261003/`，使用完整实时 syslog 与最近600秒统一日志 archive 交叉验证；只停止本次采集器，保留 VM。官方映射：https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/skadnetwork-id-manager 。


## J-2026-10-03-25 — Subway Surfers 3.69.2 广告 SDK 静态取证

用户提供 `com.kiloo.subwaysurfers-3.69.2-Decrypted.ipa`（build 96072）。未安装或执行原包，直接读取 ZIP、plist 及 UnityFramework 的 Mach-O 类名节。找到 IronSource 与 11 个 IS 广告源 Adapter，IronSourcePrivacyInfo 声明 9.5.0；独立 framework 含 Meta Audience Network 6.21.1、AppLovin 13.6.2、InMobi 11.4.0、Moloco 4.8.1、SuperAwesome 9.4.0。其它静态链接 SDK 的类标记及资源 bundle 确认 Google Mobile Ads、Unity Ads、Liftoff/Vungle、DT/Fyber、BidMachine、Pangle、Mintegral。不能仅凭 Frameworks 目录列出全部 SDK，不能将 FBSDKLoginKit 当成 Audience Network。静态包含不等于运行时初始化、启用或单次广告填充；用户看到真实广告不能证明 Meta/Pangle 赢得该次填充。取证、SHA-256 与版本口径保存在 `.build/validation/subway-surfers-3.69.2-sdk/evidence.json` 及 `report.md`。官方历史依据：https://unity.com/resources/sybo-subway-surfers 。

## J-2026-10-03-23 — Facebook 581.0.0 在虚拟机 2 安装与登录页验收

- 实例：`start.sh 2` 对应 `vm-fresh`，客体 iOS 26.1；安装前没有相关 VM 进程或磁盘占用。使用现有完整 `.app`，未重建源码、更新固件或改动设备身份。
- 用户提供 `com.facebook.Facebook-581.0.0-Decrypted.ipa`；bundle ID `com.facebook.Facebook`，版本 581.0.0 / 1080178719，最低 iOS 15.1。IPA SHA-256 为 `85c8f9e2a6680356924e52d6f09225a68be2eabad20a5a7a7ac69866df84930d`。19 个识别到的 thin arm64 Mach-O 未发现非零 cryptid；此检查不证明包的官方来源或未被修改。
- 通过现有 `boot --config vm-fresh/config.plist --variant exp --vphoned-bin vm-fresh/.vphoned.signed --install-ipa <用户包>` 自动安装；App Browser 确认 User 注册和版本。`idevicedebug --detach run` 因没有开发者镜像失败，没有额外挂载镜像。随后使用现有 Open URL 的 `fb://` 入口与桌面图标启动。
- 10:16:21（北京时间）SpringBoard 记录主进程 PID 579 `Bootstrap success`；欢迎页显示“加入 Facebook”，点击“我已有个人主页”后手机号/邮箱、密码和登录按钮完整加载。10:18:24 后应用列表复查 PID 579 仍存在，未观察到启动闪退。
- 证据保留于 `.build/validation/facebook-vm2-20261003/`：`host.log`、`guest.log`、`macho-check.json`、`login.png`。日志采集器已停止，VM 保持运行并停留在登录页。
- 验收范围：安装、注册、启动、页面交互和约两分钟持续运行通过。未输入账号密码，未验证登录、信息流、Meta Audience Network 填充、展示或广告归因；不能由登录页正常推断这些功能通过。

## J-2026-09-23-22 — 独立客体应用只读基线探针

- 新增 `tests/guest_probe/` 独立测试应用与构建入口，不链接进 vphone/vphoned、不修改生产宏或固件。读取 UIDevice、uname 和五个基础 sysctl，逐项保留成功值或 errno；不含广告 SDK、设备标识采集、身份修改或真假设备判定。
- `zsh tests/guest_probe/build.sh` 生成 `.build/validation/guest-probe/TBGuestProbe.ipa`。初次链接缺 CoreGraphics，补齐 framework 后编译成功。经当前 VPHONE 内置安装器安装为 User 应用 `com.tb.vphone.guestprobe`；使用 devicectl 指定当前第二台 UDID 启动。没有操作同时连接的实体设备。
- 从应用自己的 Documents 取回实际 JSON：UID/EUID=501，hw.machine=iPhone17,3，hw.model=D47AP，hw.ncpu=4，hw.memsize=4270800896，kern.osrelease=25.1.0；uname.machine=iPhone17,3。编译标志 TARGET_OS_SIMULATOR=0 不能解释成真机。研究系统的 sandbox 等价性未验证。
- 初次报告 PID 1634、时间 2026-09-23T11:14:15Z；定向重启此应用后 PID 1656、时间 11:17:02Z。两次源码标记与实际 main.m SHA-256 相同。源码标记、UID、重启时间变化、PID 变化、五项读取成功及 uname/hw.machine 一致性六项现场检查通过。源码标记仅用于构建追踪，不是可信远程证明。
- 自动点击 Refresh 未使报告时间变化，此交互用例未通过，不能把触摸接口的 ok 当作按钮执行成功；已用独立的进程重启用例验证重新采样。探针页面留在第二台供手动查看；未开启此前 MobileGestalt 实验，未做修改前后固件对照。
- 证据在 `.build/validation/guest-probe/guest-report.json`、`guest-report-relaunch.json`、`validation.json`。可复用构建、安装和取回步骤在 `tests/guest_probe/README.md`；AFC Documents-only 模式仍需 `Documents/report.json` 路径。


## J-2026-09-23-21 — 普通 daemon 部署与调用链运行验收通过

- 目标限于宿主/客体运行版本、哈希和普通控制链路。两项身份实验宏仍为 0，没有修改固件或启用身份隐藏。
- 复现：第二台现有 Connect → Ping 返回 `pong`，Guest Version 返回 `fa5ea10`；宿主为 `0f76ba1`，本地待部署 daemon 也内嵌旧标识。`scripts/vphoned/Makefile` 只依赖源文件，不跟踪 `GIT_HASH` 参数变化，因此宿主重新构建不保证 daemon 重新编译。通过 GitHub MCP 对比官方 `9c23c8adcd4b362120988ab9d228b959bcc23ae3` 同文件，规则相同；不将旧构建标识单独解释为功能源码不同。
- 处理：正常停止第二台，`make -C scripts/vphoned clean` 后执行 `./scripts/build.sh`。实际编译参数为 `-DVPHONED_BUILD_HASH='"0f76ba1"'`。完整构建及 `codesign --verify --deep --strict` 通过，未修改生产代码。构建、bundle 内和 `vm-fresh/.vphoned.signed` 三份 daemon 的 SHA-256 均为 `5551c32ecab8bf871727be7c4459fc8324b49c40d9803b898181e5b8ef9df1eb`。
- 实际执行 `./start.sh 2`。客体日志 16:16:04 记录 hash mismatch、接收 187888 字节更新、写入缓存、退出等待重启；之后 UI Guest Version 返回 `0f76ba1`，Ping 返回 `pong`。该轮采集缺少更新进程重启后的 hash OK，未以连接成功替代它。
- 再次冷启动第二台，16:18:57.971699 客体明确记录 `vphoned: hash OK`；Guest Version 仍为 `0f76ba1`，Home 命令返回 `ok: true`。这验证本次 daemon 部署、重启持久性和普通控制路径。它不验证任何身份实验分支，也不证明整个进程内存的完整性或全部固件状态。
- 启动日志显示初始化完成前会出现连接重置，随后建立连接。J-20 的未连接是当时采样状态，不再视为持续断连；未对启动延迟作根因修复。第二台保持运行，日志采集器已停止，第一台未改动。
- 证据：`.build/validation/runtime-diagnostics/` 下的 `build.log`、`start-2.log`、`guest.log`、`cold-start-2.log`、`cold-guest.log`、`cold-home.json`、`result.json`。可复用用例与版本字段解释见 [运行诊断](../skills/vphone-development/references/runtime-diagnostics.md)。局部 clean 是当前已验证操作方案，未改变增量 Makefile 规则。


## J-2026-09-23-20 — 控制连接复测与宏部署状态核对（尚未修复）

- 重新执行 `./start.sh 2`，第二台可以启动，但 Home 控制请求多次返回 `guest not connected`。直接串口启动时一度取得 `[control] connected to vphoned v1`，Home 返回 `ok: true`；再通过 `start.sh 2` 冷启动后仍复现未连接，不能把短暂恢复报告为修复成功。
- 串口 `launchctl print system/com.vphone.vphoned` 报服务不存在，bootstrap 报 `Service cannot load in requested session`；但随后 `ps` 显示 PID 70、PPID 1 的 `/usr/bin/vphoned` 存在。该 launchctl 查询不能证明 daemon 未启动，早期“服务未注册”的判断撤回。手动启动的诊断副本 PID 465 加载缓存后报 `Address already in use` 并退出，不能将控制恢复归因于该副本。
- USB 日志捕获 `vphoned[70]` 的 `IOKit loaded`、`XPC loaded`，初始化延迟是待验证假设，没有足够证据定位具体阻塞调用。本轮未修改 daemon、系统启动注册或固件，也未重刷实例。
- 源码及 bundle 内宏文件 SHA-256 均为 `86d102ceaa022722c6ff43b048c4e238949c72bfc526d2ad371769896a97e012`，两项 TB 宏仍为 0。构建 daemon 与第二台暂存 daemon SHA-256 均为 `ea7749cdf00d5758288517e208a4433101f8b92b223e3eb2b79a0ce885a4ac58`；这只验证宿主暂存文件一致，不能证明客体运行文件或 DSC 实验已部署。
- 证据保留在 `.build/validation/custom-vm-features/repair-state.json`、`repair-console.log`、`repair-guest.log`、`repair-verified-start-2.log`。Pangle 官方 SDK FAQ 将 20001 定义为缺少适合广告的通用未填充错误；其中模拟器只是排查项，不能作为本设备检测命中的证据：https://www.pangleglobal.com/jp/integration/SDK-FAQ 。没有验证广告加载成功，也没有启用设备伪装。


## J-2026-09-23-19 — 完整构建后通过 start.sh 2 验证（到达锁屏，控制通道未通过）

- 用户要求更新后用 `./start.sh 2` 验证第二台。两项 `TB_VPHONE_*` 宏保持 0，本轮未部署 MobileGestalt 实验，不能算隐藏功能的运行验收。正常停止 `vm-fresh` 并确认 Disk.img 无占用后执行 canonical `scripts/build.sh`。
- 初次打包失败于旧 bundle 中 root 所有的 `scripts/patchers/__pycache__`。仅移动该 root 目录被拒绝；移动其当前用户所有的上层 `scripts` 目录到 `.build/validation/custom-vm-features/stale-root-cache-scripts` 成功，保留约 216 KiB 旧缓存待有管理员权限时清理。随后从头完整构建成功，`codesign --verify --deep --strict` 通过，bundled 宏头、Python 宏解析器及 DSC patcher 与源码 `cmp` 一致。未改构建脚本、系统权限或 guest 固件。
- 实际执行 `./start.sh 2`，映射仍为 `vm-fresh`；iOS 26.1 启动到锁屏，USB `ideviceinfo` 返回 `iPhone17,3` / `vresearch1`。但 host 持续报 vsock `NSPOSIXErrorDomain Code=54 / Connection reset by peer`，未取得 vphoned 握手，交互/应用/广告未验收。正常停止后以 PTY 再次执行同一脚本，锁屏和连接问题均复现。不能因 GUI 出现而标记全部通过，也不能据此认定由本次默认关闭的 Python 定制引起。
- 证据：`.build/validation/custom-vm-features/build-final.log`、`start-2.log`、`start-2-tty.log`、`start-2-final.jpg`。短时 USB 日志采集器已结束；第二台留在锁屏运行，第一台未启动或修改。后续需定位 guest daemon / vsock 服务连接问题；当前不是已验证的真机模式。

## J-2026-09-23-18 — 新增统一宏控制的 MobileGestalt 实验（默认关闭，仅离线验证）

- 用户要求新定制可统一开启/回退，并验证真机表现。未收到“是否包含此前全部定制”的范围答复，按本次新增改动处理，未改造无关的历史定制。`scripts/vphone_custom_features.h` 统一定义总开关与 MobileGestalt 子开关，均默认 0；Python 补丁在写入前读取并严格验证 0/1 定义，任一开关关闭即使用原有 EXP 行为。
- 基于既有 DSC 字符串定位、Mach-O 归属和页哈希更新机制，仅对 libMobileGestalt 做可逆的原 OID/改名 OID 选择。未知目标或无受支持签名页覆盖时，实验在任何写入前拒绝。不是伪造 sysctl 成功返回 0，也不隐藏 IORegistry 或硬件平台。未新增内核、签名绕过或应用注入代码。
- `.venv/bin/python tests/test_custom_vm_features.py`：5 项通过。用本地原 IPSW SystemOS 解密镜像只读挂载，提取约 102 MB 的 `dyld_shared_cache_arm64e.15` 到可丢弃副本，先执行 HEAD 原补丁生成基线，再执行默认/开启/幂等/关闭流程。默认与 HEAD 相同；开启只改 33 字节；关闭后的 SHA-256 精确恢复 `c285b7f828e2fc8915873e65bdb62b1d86f495337cf8ea335befeacde07bdefa`。`roundtrip.json` / `roundtrip.log` 保留在 `.build/validation/custom-vm-features/`。
- 实际客体没有部署实验，原 `vm-fresh` 保持运行。管理员探测 `sudo -n true` 返回需要密码；未请求或记录密码，未对 guest 磁盘写入。没有实体 iPhone 对照，也未在 Pangle 进程中验证 MobileGestalt 返回值。不能将离线字节回退成功记为冷启动/UI/广告成功；完整真机一致性不成立，J-17 硬件层差异仍在。
- 使用和回退限制统一记录在 `0_binary_patch_comparison.md` 的本地实验小节：关闭宏必须重新处理/部署固件，单纯改源码或启动参数不会撤销已安装补丁；bundled 工具使用自己的宏文件副本。

## J-2026-09-23-17 — 当前 EXP 的虚拟化身份暴露（只读取证）

- 范围：源码 HEAD `0f76ba1`；运行进程明确使用 `vm-fresh/config.plist --variant exp`，配对设备与 J-16 重建实例匹配。未更改固件、身份、应用或发起广告请求。
- 实时 `ideviceinfo` 定向查询：`ProductType=iPhone17,3`、`HardwareModel=D47AP`、`HardwarePlatform=vresearch1`、`SerialNumber=vphone-1337`、`ProductVersion=26.1`、`BuildVersion=23B85`、`CPUArchitecture=arm64e`。证明配对主机可读取研究平台与固定项目序列号，不能直接推定普通应用具有相同读取权限。
- 实时 `idevicediagnostics -u <当前实例UDID> ioreg IOService` 返回 `AppleVirtualPlatformARMPE`、`AppleParavirtGPU`、`AppleParavirtDisplay`、`AppleVirtIONetwork`、`AppleVirtIOSocket`、`Virtual USB Touch Screen` 等。只报告匹配的设备名，未保存整个设备信息。IORegistry 诊断通道可见不等于第三方应用沙箱可见。
- 源码对应：`DeviceTreePatcher.basePropertyPatches` 明确将序列号写为 `vphone-1337`；`VPhoneHardware.createModel` 使用 PV=3 / boardID=0x90 的研究平台。`KernelEXPPatchHvVmmRename` 仅重命名 sysctl OID，保留处理函数；`cfw_patch_hv_vmm_dsc.py` 刻意让 libMobileGestalt 与图形/计算组件查询改名后的 OID、继续得到真实 VM 状态。历史 `.build/validation/fresh-vm/cfw-install.log` 也记录了 libMobileGestalt 的此项改写，但该日志早于 J-16，不能用于证明当前重建实例的 DSC 落盘状态。
- 实时 MobileGestalt 查询 `hv-vmm-present` 等键仅返回 `MobileGestaltDeprecated`，没有得到值；未声称当前应用进程读到了 true，也未声称已测得当前 sysctl 返回值。Apple 官方 XNU `bsd/kern/hvg_sysctl.c`（本次经 GitHub MCP 读取）中，arm64 `sysctl_vmm_present` 从 DeviceTree `vmm-present` 取值，作为机制参考，不冒充当前 guest 二进制逐指令验证。
- 结论：已确认当前 VM 向配对诊断通道暴露虚拟化特征；源码并未实现全局隐藏。尚无证据证明 PAGAdSDK 8.3.0.6 读取/上传了上述字段，或其服务端因此返回 20001。后续如需归因，须在应用自身权限上下文观察查询与返回，并关联请求结果；不因通用 no_fill 文案追加身份补丁。


## J-2026-09-22-16 — 授权重建损坏的 vm-fresh（启动恢复，IDFA 待验收）

- 用户明确确认清空重建第二实例。检查原磁盘无占用后删除损坏的 `vm-fresh`，保留第一台 `vm`；复用本地两份 26.1/23B85 IPSW 和 `.venv`，不生成整机备份或归档。
- 新建配置 4 CPU、4096 MiB；`fw prepare` 成功；`fw patch --variant exp --force-exc-guard` 9 个组件 / 179 处实际修改成功。以新 ECID `2AF5A35422349AA0` 明确选择目标，SHSH 获取和 DFU restore 均退出 0，记录 iOS/cloudOS 26.1/23B85。随后 `vm stop` 成功，lsof 确认磁盘释放。
- 管理员认证后 `cfw install --variant exp --root-popup` 退出 0，启动快照切换成功，自动清理固件中间目录。首启已连接 vphoned（iOS 26.1）并进入“你好”新机设置画面，未复现旧卷 corruption/checksum 错误。用户再次报告脚本保护提示后，修正遗留映射为 `1=vm`、`2=vm-fresh`，移除过时的静态损坏提示。新系统尚未完成设置，本次非零独立 IDFA 尚待验收，不能由新 ECID 推定已验证。历史 J-14/J-15 的“未获重建授权”已由本条取代。
- 脚本验收：`zsh -n start.sh`、`git diff --check` 通过；运行中磁盘保护有效。正常停止新实例后实际执行 `./start.sh 2`，再次进入“你好”画面，当前保留该窗口运行。第一入口未改动。
- 本次阶段日志：`/tmp/vphone-rebuild-{prepare,patch,dfu,shsh,restore,cfw}.log`；现场可用空间约 53 GiB，`git check-ignore -v vm-fresh/Disk.img` 命中 `/vm-*/`。完成后清理可重建中间产物，更新此记录及 skill 的实例状态。

## J-2026-09-22-15 — 用户授权删除旧 vm2

- 用户确认旧 `vm2` 不符合两个独立 IDFA 实例的目标并要求删除。现场发现它再次运行；只对匹配 `vm2/config.plist` 的 host 发送 SIGINT，确认 Disk.img/NVRAM 无占用后删除整个 `vm2` 目录。
- 保留 `vm`、`vm-fresh`。`start.sh 2` 改为说明第二入口暂不可用，避免再启动旧克隆或已知损坏的 `vm-fresh`；后者的重建尚未获授权，本次未重刷。目录删除检查通过。

## J-2026-09-22-14 — 快捷启动映射到旧第二实例，独立身份实例仍有卷损坏

- 用户报告两实例 IDFA 相同。运行进程及 `start.sh` 确认当前选择为 `vm` 和 `vm2`；J-10 已记录这两台旧实例 IDFA 相同，验证独立的是 `vm-fresh`。之前把“第二实例”映射成 `vm2` 未体现独立身份目标；NVRAM 属主修复只解决启动权限。
- 保留第一台 `vm` 运行，向 `vm2` host 发送 SIGINT 并确认磁盘释放。启动既有 `vm-fresh` 复查，guest 再次持续报告 `disk2s7 / Container corruption detected / obj_checksum_verify`；随即对该 host 发送 SIGINT 停止失败启动。日志为 `/tmp/vphone-fresh-check-20260922.log`。未改 IDFA、设备身份、固件或重刷磁盘，未将坏实例改成默认第二入口。
- 后续需由用户明确是否允许重建损坏的 `vm-fresh`（会清除其中应用和数据），或要求保留其数据进行恢复。独立实例可用并重新验证非零 IDFA 不同后再更新 `start.sh 2` 映射，不能提前宣称修复完成。

## J-2026-09-22-13 — 第二实例启动被 root 属主的 NVRAM 阻止

- `./start.sh 2` 在写出设备身份后报 POSIX 13。现场 `vm2/nvram.bin` 为 `root:staff 600`，当前用户 tubao 的只打开不写入 `O_RDWR` 检查复现 Permission denied；源码下一步为 `VZMacAuxiliaryStorage` 初始化。
- 通过 macOS 管理员认证仅将该文件属主改为 `tubao:staff`，保留 600 权限及文件内容。三个存储文件读写打开检查通过；重新执行 `./start.sh 2` 已进入 iBoot、Darwin 和 USB 初始化，越过原失败点，实例保持运行。未验收 guest 应用功能。
- `start.sh` 增加现有两实例存储文件的读写权限检查，提前给出具体文件路径。`zsh -n` 和 `git diff --check` 通过。未修改 host/guest 源码、固件补丁或 AMFI 设置。

记录已验证结论、关键证据和未解决的边界；可复用操作见 [开发 skill](../skills/vphone-development/SKILL.md)。不创建 TODO.md。

## J-2026-09-19-12 — 未忽略的 VM 磁盘触发后台 Git 打包，清理遗留临时包

- 环境：本地源码 `0f76ba1214e6ce3e0b35cf46b581069792e53988`；`vm`、`vm-fresh`、`vm2` 的 `du` 分别约 30、19、30 GiB。用户询问目录用途及可清理项，随后要求把预防方法加入项目 skill。
- 证据：`.git` 约 111 GiB，主要是九个 `objects/pack/tmp_pack_*`。现有 `.gitignore` 的 `/vm`、`/vm-*/` 命中前两台，未覆盖 `vm2`。`lsof` 确认 Git PID 53120（`hash-object --stdin-paths`）和 55068（`add --sparse --pathspec-from-file=- --pathspec-file-nul`）正在读取 `vm2/Disk.img`，后者同时写入 `tmp_pack_udG2IC`；父进程 654 为 ChatGPT.app。现场可证明本次后台添加虚拟磁盘造成临时包增长；其余八个旧临时包的各次来源未逐一追溯。
- 处理：在 `.git/info/exclude` 追加精确 `/vm2/` 规则；复核父进程和命令后向上述两条 Git 进程发送 SIGTERM。逐个检查临时文件无占用后删除九个遗留包，共计已分配空间约 111.12 GiB；保留正式 pack/index、用户已有修改及三个 VM 的全部内容。未执行 Git 历史清理或虚拟机删除。
- 验证：`.git` 降至约 1.2 GiB，主机可用空间从约 4 GiB 恢复到 114 GiB；`git fsck --connectivity-only --no-dangling` 退出 0；`git check-ignore -v vm2/Disk.img` 命中本地排除规则，`git status --short` 不再列出 `vm2/`，其他既有工作区变更仍在。相关 Git 进程已退出；本次未做 VM 冷启动验收。
- 预防：创建任何仓库内实例或大体积产物前验证实际目标的忽略规则；实例库优先放仓库外，避免后台版本快照反复打包磁盘。规则与安全清理流程统一维护在 [开发 skill](../skills/vphone-development/SKILL.md) 的“VM 存储与临时产物”。本地排除规则不随克隆传播，也不保证第三方程序不会显式强制添加文件，因此后续仍需执行目标检查。

## J-2026-09-19-11 — vm-fresh 启动报用户卷校验失败，广告取证转旧实例对照

- 主机此前磁盘耗尽，清理后空间恢复。本轮启动已有 vm-fresh（C1E416AA43CCDDEA），内核重复报告 `disk2s7 / Container corruption detected / obj_checksum_verify`，用户界面持续黑屏，Home 未恢复，CoreDevice unavailable。时间相关不能单独证明先前 Pangle 40060 的原因。
- 原镜像停止后仅用 `hdiutil attach -readonly -nomount` 检查；User 卷加密锁定，macOS verifyVolume 报 keybag 错误，受 iOS 加密格式限制，不把该 macOS 错误单独等同于密钥损坏。已卸载只读映像，未修复、重刷或更改身份。vm-fresh 现保持停止。
- 既有旧 vm（9D07DC08906BCCAC）正常启动、解锁并打开 wooshort。通过内置安装器安装本机编译的 Pangle 诊断 IPA 成功；五次点击隐藏入口有效。未修改 vphone host/guest/固件代码。
- 此包新增同配置的官方最小激励加载入口，保留数据处理与个性化选择。自动化未能切换页内开关，已请求用户手动触发；本轮尚无新的加载回调。旧 VM 结果不能替代 vm-fresh 的故障复现。
- 主记录和安装包哈希在宿主项目 `data/pangle-device-diagnosis.md`。本轮主机日志采集已停止，旧 vm 保留在测试页面。现场日志 `/tmp/pangle-vphone-20260919/`。

## 当前结论

- 源码基线：官方 `1.0.14` / `9c23c8adcd4b362120988ab9d228b959bcc23ae3`；自有分支 `tb_dev`。host、guest 和固件补丁代码保持官方版本。
- 完整构建入口：`./scripts/build.sh`，编译自己的源码并打包签名资源。无需使用官方预编译程序，也无需用户手工修改第三方 IPA。
- 官方安装器内部会解包、重签并安装 IPA；用户直接选择原始 IPA 即可。应用的打包工具不是安装前提。
- 当前 `vm/` 为已有 EXP 环境，iPhone/cloudOS 均为 26.1 (23B85)。EXP 是固件变体，通过创建/补丁/安装参数选择，不是 Git 分支。
- 已验证 Orblino Weave 在官方生产源码完整构建后重装、冷启动和游戏交互正常；不代表所有 IPA 均兼容，也不代表干净 EXP 重刷已经验证。

## J-2026-09-18-10 — 独立新建 VM，验证 IDFA 不同（已完成）

- 用户要求保留第一个实例，创建全新实例验证。为避免窗口顺序歧义，保留 `vm` 和 `vm2` 两个旧目录，新建 `vm-fresh`；操作前两台旧 VM 已停止。
- 当前源码 `0f76ba1214e6ce3e0b35cf46b581069792e53988` 经 `scripts/build.sh` 完整构建，`codesign --verify --deep --strict` 通过。复用原始 iPhone/cloudOS 26.1（23B85）IPSW，不复制旧 Disk.img、SEPStorage 或 NVRAM。
- `vm new` 后实测：64 GiB 稀疏磁盘分配字节数为 0、SEPStorage 全零、machineIdentifier 为空。新身份在 DFU 启动时生成，与旧实例不同；具体身份及现场日志仅留本地 `.build/validation/fresh-vm/`。
- 使用 `VPHONE_ROOT=$PWD`、`VPHONE_VENV_DIR=$PWD/.venv`、显式 `--library-root "$PWD"` 复用已有依赖和原始固件缓存。默认包装流程曾开始在 `~/.vphone/venv` 重建依赖，已停止其进程，改用现有可用项目 venv；没有继续使用该未完成环境。
- 官方现有 `fw patch --variant exp --force-exc-guard` 成功：9 个组件、179 条补丁记录（本次流水线输出，不重定义文档中变体汇总口径）；未修改补丁实现。获取新设备 SHSH 后，显式指定新 UDID/ECID 完成恢复，退出码 0，并记录版本信息。
- 用户确认后删除旧导出归档及 SHA-256 文件，保留两台旧 VM。通过系统管理员认证执行 `cfw install --variant exp --root-popup`，退出码 0；启动快照重命名完成，CLI 自动清理本次固件中间目录。完成首次 shell 初始化、关机和再次启动；`vphone_jb_setup.sh` 报告 complete，内置安装器成功安装 Orblino Debug。旧 `vm`、`vm2` 的磁盘及身份文件大小/修改时间仍与操作前一致。
- 首次设置选择不从旧设备或备份传输数据、不登录 Apple 账号；用户确认条款后完成设置，应用成功启动并进入广告测试面板。期间宿主磁盘不足导致一次 guest I/O 错误及启动中断；用户清理空间后，将新实例内存配置降至 4 GiB 再次启动，完成设置及应用验证。测试 IPA 来自现有 Debug-iphoneos 产物，没有修改应用源码。用户手动解锁后，在新实例广告测试面板取得非零 IDFA；再次点击“申请追踪授权并获取 IDFA”实时读取，值保持一致且与用户原截图中两个旧实例的共同值不同。完整标识只保存在本地验证记录中。最终复核两台旧实例磁盘和身份文件的大小、修改时间及可读取身份文件哈希均未变。验证覆盖全新磁盘来源、系统初始化、应用启动及不同 IDFA；未做冷启动后 IDFA 持久性复测，不代表网络隔离或外部服务无法关联。用户解锁后页面已有 Pangle AppID verification failed（40060）提示，本次仅读取 IDFA，未处理广告配置问题。

## J-2026-09-18-09 — 简化广告测试入口

新增 `scripts/ad_test_trace.sh`：默认激励，`interstitial` 切换插屏；自动匹配项目 VM 的预测 UDID 与已连接设备，避免同时连接真机时选错；默认 Orblino 广告位、UTC、45 秒，并生成不覆盖的输出目录。支持预览、只采集、覆盖 VM/时区/广告位，`--yes` 表示操作者已检查测试前置条件。复用 Python/OCR 逻辑，不新增 SDK 行为。

验证：五项隔离测试通过，覆盖多设备选择、插屏/只采集参数、ID 不一致、断连、唯一输出及无效时长。当前两台设备连接时真实 `--dry-run` 选中正确 VPHONE；本轮没有额外请求广告。

## J-2026-09-18-08 — 测试广告自动请求与后台时间核对

- 新增 `scripts/ad_test_trace.py` 和按钮 OCR helper `scripts/ad_test_button.swift`；复用官方 host socket、Orblino Debug 测试面板和 idevicesyslog。不改 IPA/SDK/host 生产源码。每次只操作一个已登记测试设备的加载按钮，输出 UTC/报表时区事件、单调时钟耗时、小时桶和截图；不操作广告素材或自动重试。
- 初版坐标实测受滚动后页面位移影响，15:04:12 误触服务端竞价入口，返回 `bidding_token / ad_not_ready`，不计为普通广告请求。最终移除坐标参数，改用完整截图识别精确按钮文字、两次位置稳定检查；错误入口日志触发停止。低分辨率截图 OCR 不可靠，使用官方 screenshot 的完整分辨率文件。另一次 OCR 超时未发起触摸。
- 最终实测：2026-09-18 15:09:26.254 +08:00 注入激励按钮，111 ms 后收到应用请求开始日志（测试设备验证、canRun=true、attached=true），1096 ms 后收到 no_fill；PID 427 持续运行。确认请求 1、加载成功 0、失败 1、奖励回调 0。曝光/点击缺少对应埋点，汇总为 null，不将触摸当曝光。证据在 `.build/validation/ad-trace-20260918-ocr-verified/`。
- 后台刷新并恢复 wooshort 应用筛选：UTC0、按小时、9/16–9/18、全部广告位；不含美国请求 57、不含美国返回 17、总返回 17、展示/点击/收益 0，最新行仍为 9/17 07 时。当前请求属于 9/18 UTC07 时，尚无对应行。平台小时数据有延迟，建议北京时间 21:00 后检查该小时；测试流量是否进入普通报表尚未确认，未声称逐笔匹配或产生收益。
- 后台“请求量”排除美国，刷新会重置应用筛选；这两个口径要重新确认。没有贯通客户端和后台的 request ID，只能比较时间桶和聚合量。流程见 [广告测试取证](../skills/vphone-development/references/ad-test-trace.md)。六项自动测试、Skill 校验、diff 检查通过；采集器已退出，VM 保持运行。

## J-2026-09-18-07 — 将 EXP 镜像制作沉淀为可复用流程

- 扩展现有 `scripts/exp.sh prepare NAME [--force-exc-guard] [--dry-run] [固件参数]`：完整源码构建 → 新建空 VM → 官方固件准备 → 官方 EXP patch。默认不启用 EXC_GUARD；只接受新名称，不修改现有 VM，不自动恢复或导出。
- 官方 1.0.14 的 `vm create` 没有该参数，`VPhoneCreateOrchestrator` 内部固定 `forceExcGuard: false`。原 `create` 入口现在对误传此参数提前报错并指向 `prepare`，不修改 Swift 源码或复制官方补丁逻辑。
- 完整人工流程见 [EXP 镜像制作](../skills/vphone-development/references/exp-image-workflow.md)，覆盖 DFU 恢复、CFW 安装、首启验收、停机归档以及已有 VM 定点维修的适用边界。原归档未因文档更新而包含 J-06 修复。
- 验证：`python3 tests/test_exp_workflow.py` 六项隔离测试通过；`zsh -n scripts/exp.sh`、Skill `quick_validate.py`、`git diff --check` 通过。本次未新建真实固件、未恢复或重启现有 VM；新建 EXP 的整机验收仍未执行。

## J-2026-09-18-06 — Pangle 初始化闪退：官方 EXC_GUARD 选项未启用

**环境与复现：** 同一 Orblino Debug IPA，PAGAdSDK 8.3.0.6；已有 26.1/23B85 EXP guest。Pangle 已登记 `vphone-exp-orblino`（IDFA 不写入仓库），等待超过 15 分钟后，以测试设备验证模式、必要数据处理开启、个性化关闭发起请求。14:24 和 14:33 两次冷启动均崩溃：`EXC_GUARD / GUARD_TYPE_MACH_PORT / SET_EXCEPTION_BEHAVIOR`，堆栈为 `PAGAdSDKManager -> PAGByteFinderManager -> HeimdallrPAGEmbed -> HMDPAGCrashDetect_mach_start -> task_swap_exception_ports`。这不是此前没有应用 PID 的安装签名故障。

**来源与定位：** 官方 `1.0.14` 的 `KernelPatcher` 和 README 已提供 `--force-exc-guard`（[issue #291](https://github.com/Lakr233/vphone-cli/issues/291) / PR #297）。26.1 的 regular/jb/exp 默认不启用该可选补丁；选择 EXP 不等于已开启全部兼容选项。实际 Preboot 中的 `kernelcache.research.vphone600` 对应目标仍是 `PACIBSP`，证实已有 guest 没有这项补丁。不能把这归因为广告平台识别了虚拟设备。

**最小修复：** 使用本地保留的原始 cloudOS IPSW 恢复临时目录中的固件输入，执行官方完整构建产物的 `patch-firmware --variant exp --force-exc-guard --records-out ...`，生成 `kernel.thread_guard_violation`。旧的已打补丁目录不能直接重复运行完整 patch 流程：iBSS JB 的原始匹配已不存在；必须使用原始输入。当前 guest 与整套重生成固件还有历史差异，因此未整体覆盖。

停止 VM 后，以 APFS clone 备份 Disk.img、NVRAM、SEPStorage 和配置，并保存原 Preboot IMG4。仅把上述官方记录应用到现用内核：验证旧指令及其后 124 字节与官方目标一致；保留 IMG4 manifest 和 payload properties，容器总长度不变，全文件恰好四个字节变化。通过 host 离线挂载 Preboot 完成部署，无需重新恢复、清空数据或修改应用 / VPHONE 生产源码。该研究 VM 兼容选项会禁止 guard violation 的递送，作用范围大于本次 SDK，不应宣称是生产 iOS 的通用修复。

- 官方动态定位记录：`thread_guard_violation`，file offset `0xB4FFCC`，VA `0xFFFFFE0007B53FCC`；这些值仅作为该 kernel 的现场证据，不用于硬编码 patch 逻辑。
- 部署前 IMG4 SHA-256：`2232ccbb3caea8701f1e61ed7a365b4529c7067f01dd4a865598a8915723484d`。
- 部署后 IMG4 SHA-256：`7ea6e3124ec423ed06290d4e276272b1411b28636de6b7ff5a37cf51158962c6`。
- 本地回滚材料：`.build/validation/pre-excguard-backup/`；官方生成记录：`.build/validation/excguard-records.json`。未更改 restore 输入目录中的旧内核；以后重新恢复仍需显式启用官方参数。

**运行验证：** guest 重启后 IDFA 未变，同一 IPA 以 PID 427 运行。14:44:11 激励请求、14:44:55 插屏请求均完成回调，返回 `com.PangleAdSDK / 20001 / no_fill`，不再触发原崩溃。App ID `8895377`、普通激励位 `983634549`、插屏位 `983639115` 与后台匹配。

**仍待确认：** 最初 14:24 首次请求还曾返回 `40060 / AppID verification failed`；修补后的请求未复现，但尚未独立证明其原因，不能把它归因于 EXC_GUARD 或声称已修复 ID 配置。`20001` 是无填充，不是展示验收通过；当前没有成功展示、点击或奖励回调。原生测试面板的权限状态随会话重置，平台测试设备登记则保留。

## J-2026-09-18-03 — IPA 启动拒绝：轻量打包遗漏证书（已定位）

**症状与证据：** 10:51:02 点击 wooshort 后，TXM 报 `CodeSignature: selector: 24 | 0xA1 | 0x30 | 1`，随即 RunningBoard 报 `NSPOSIXErrorDomain Code=85`、`Bad executable (or shared library)`、`Launchd job spawn failed`，没有创建应用 PID。

**原因链路：** 干净 `make bundle` 仅携带 `Contents/Resources/signcert.p12`，官方资源解析却查找 `Contents/Resources/scripts/vphoned/signcert.p12`。文件缺失使 host 不上传 `cert_path`；guest 进入无证书签名分支，最后递归签名还会丢失 entitlements。官方 `scripts/build.sh` 会复制完整 scripts 资源树，因此不触发这一打包路径问题。

**控制实验：** 保持当时 host、guest、固件和 Developer Mode 不变，只将项目已有证书复制到宿主 .app 的预期位置，重新安装原始 IPA：

- 10:53:41，Downloads 中的 Orblino Weave (`com.Orblino-Weave`) 以 PID 892 进入前台主菜单。
- 10:58:24，Downloads 中的 SilentShadowsDeep (`com.SilentShadowsDeep.ssd`) 以 PID 925 进入前台主菜单。

这证明恢复证书输入解决了该安装路径；未独立区分 CMS 与 entitlements 各自的必要性。手工复制只是诊断实验，正式流程使用完整源码打包。

**排除的方向：** 缺少 launchdhook 不是这些 IPA 运行的必要障碍。不能根据没有 `.ips`、系统应用正常或单次 `app_launch=NO` 就修改 launchd/内核。临时 `vreq` 调试入口未保留；当前 host 只提供官方控制协议。

## J-2026-09-18-05 — 官方源码完整构建与冷启动（已验证）

**最终方案：** 不保留证书路径兼容、无证书时强制 `-M`、custom-trust 键拼写这三处生产修补。生产代码与官方 `1.0.14` 一致，使用 `scripts/build.sh` 完整构建，停止旧 host 后启动新产物。

**构建与部署证据：**

- `./scripts/build.sh` 成功，`codesign --verify .build/vphone-cli.app` 通过。脚本重新复制资源目录，不依赖诊断时留下的证书。
- 内置嵌套证书与项目证书 SHA-256 均为 `0d8e568d90518d6cb9580b410a45fea7464cd7ebe6c72c6dc44bdc9b2fa90ae0`。
- 构建与 VM 暂存的 guest SHA-256 均为 `79283a3e850edc27e731fa47ed7620cac4bd34b6243a6af3dbaa3532375d3f82`；Guest Version UI 确认 daemon 更新。运行中的构建标签不会随之后的 Git 历史整理自动改变，以验证时的源码差异和二进制哈希为准。
- 新 host 以普通用户启动：`.build/vphone-cli.app/Contents/MacOS/vphone-cli vm launch vm --library-root "$PWD" --variant exp`。

**应用验证：** 使用 `/Users/tubao/code/private/flywheel/Orblino Weave` 现有 `scripts/build_ipa.sh` 生成 unsigned Release IPA（iPhoneOS SDK 27.0），没有修改应用源码。产物 `ipa_build/Orblino-Weave.ipa` 的 SHA-256 为 `1de3d99587fa5144fdc7879753949c86949b74f3e912901f3f8685809f1ce479`。该脚本的选项应放在 `unsigned` 前，否则 `-o` 不生效。

通过官方 Apps → Install 安装后，PID 406 进入主菜单和 Garden 1。随后完整重启 guest，应用以新 PID 388 运行；12:14 RunningBoard 记录 `running-active-Visible`，拖动成功连接一对图案，界面显示 `Connected 1/4`、`Moves 1`、`Garden 8%`。截图保存在本地 `.build/validation/orblino-rollback-cold-game.jpg`。

**保留的验证：**

- `swift test --no-parallel --filter ResourcesTests`：9 项通过，覆盖完整 bundle 和开发目录的证书查找。
- `python3 tests/test_ipa_signing.py`：带证书签名通过，覆盖主程序、扩展权限及 framework 递归签名。官方无证书权限丢失保留为 expected failure，不能计作通过。
- `quick_validate.py skills/vphone-development`、`zsh -n scripts/exp.sh` 和 `git diff --check` 通过。

## EXP 创建与归档

[scripts/exp.sh](../scripts/exp.sh) 薄封装官方构建、创建及导出命令，具体用法见开发 skill 或 `--help`。不另写固件补丁流水线。

- `create NAME OUTPUT.tzst`：完整编译当前源码，官方 `vm create --variant exp`，再导出。
- `export NAME OUTPUT.tzst`：导出现有、已停止的 VM，附带 SHA-256 文件。
- 检查已覆盖：拒绝覆盖已有 VM/归档、修改固定变体、导出占用中的磁盘；最终脚本用隔离的 1 GiB 空 VM 完成导出、校验、官方导入往返。空 VM 测试不等于固件启动验证。
- 实际归档：`.build/exports/exp-orblino-validated.tzst`，13,006,611,657 字节，SHA-256 `183e7807a998635ef4a97772b1f76190b1239f68e81c589e561475d746460edf`。`zstd -t` 和完整 `tar -tf` 通过，包含磁盘、配置、NVRAM、SEP 和 boot ROM，排除恢复中间目录。
- 该归档包含现用 guest 和已安装应用，不是干净分发镜像或通用 IPSW。尚未执行真实归档导入后启动，也未执行干净 EXP 从零创建。

## 独立遗留问题与操作边界

- **O-2 / launchdhook：** 之前会话记录 EXP 注入 hook 后出现 `launchd cannot be run directly` 启动 panic，并通过只保留 jetsam 修改的 launchd 恢复启动。本轮沿用这个 guest，没有重新验证其根因。重装前需单独调查；历史 `DISABLE_LAUNCHD_HOOK=1` 例外不能悄悄推广为所有 EXP 的默认设置。
- **O-3 / EXP DSC：** 之前记录 hv_vmm/camera 预补丁可能因跳过已安装 cryptex 的复制而未落盘，完整性仍待独立验证。IPA 正常不能证明全部 EXP 能力生效。
- **SSH：** 该 guest 的 root SSH 曾拒绝 `alpine`，不要把默认提示当已验证凭据；已有 USB 配对通道可用于日志与进程检查。
- 取证先关联点击时间、TXM/AMFI 和 RunningBoard，再看应用 PID/前台状态。不要全局忽略 TXM 错误。
- 停机后检查实际 host 和磁盘占用进程；某些停止路径只结束 Virtualization 子进程，host 仍可能存活。只处理本次 VM 的相关进程。
- 宿主控制 socket 的 tap/swipe 使用 guest 像素坐标（当前 1290×2796）；截图后再定位，不复用旧图标位置。先唤醒屏幕再操作。
- 源码、磁盘上的构建产物和运行中进程可能是三个版本。不要仅凭 Git HEAD 或构建成功就声称新代码已部署。

## 官方依据

- [官方源码构建与变体说明](https://github.com/Lakr233/vphone-cli/blob/1.0.14/README.md)
- [完整打包脚本](https://github.com/Lakr233/vphone-cli/blob/1.0.14/scripts/build.sh)
- [资源解析](https://github.com/Lakr233/vphone-cli/blob/1.0.14/sources/VPhoneCore/VPhoneResources.swift)
- [guest 安装器](https://github.com/Lakr233/vphone-cli/blob/1.0.14/scripts/vphoned/vphoned_install.m)


## J-2026-10-03-24 — Facebook 信息流广告有限样本观察

2026-10-03 在虚拟机 2（vm-fresh，ECID `2AF5A35422349AA0`）观察已登录的 Facebook 581.0.0：普通风景、街景、插花视频与照片能够显示，但本次样本未见明确广告标签，不能确认广告展示正常，也不能判定无填充或失败。后续自动锁屏限制了继续观察；Apps 浏览器仍显示 PID 579。公开系统日志未提供明确广告加载或无填充结果；AVFoundation 中断和后台任务警告不能单独归因为广告。未点击广告或改变网络设置。证据及详细边界：`.build/validation/facebook-ads-vm2-20261003/analysis.md` 与 `facebook.log`。Facebook feed 可用不等于第三方 App 的 Audience Network 广告填充已验证。
