---
name: vphone-development
description: Use when developing or debugging this vphone-cli repository, preparing EXP firmware and VM archives, managing VM storage and temporary artifacts, enabling official compatibility patches, or diagnosing IPA installation and launch failures against upstream behavior.
---

# vphone 项目开发与排障

## 管理入口与跨 Mac 同步（2026-10-22）

Launchpad 为统一主入口，Workstation 保留为备用。Decodo 配置、安装与同步使用 [vphone-management](../vphone-management/SKILL.md)；先区分源码构建、签名产物和已安装 app。另一会话使用机器时不部署或操作运行态。以下历史 Workstation 入口不是新部署首选。

## 当前基线（2026-10-16 镜像迁移后，优先于下面的历史流程）

- 官方源码基线为 `dfcfae9c608c432a9a63f846d5cda8272fde0b82`；`main` 跟踪 `upstream/main`，业务分支为 `codex/business-vm`。同步前完整代码保留在 `codex/pre-upstream-sync-20261008`（`d23154b`）。
- 当前架构、构建和测试入口以根目录 `AGENTS.md` 为准：Xcode workspace 的 `VPhone` scheme 生成 `VPhone.bundle`。旧 `scripts/build.sh`、根目录 SwiftPM、Python 固件流水线及 `--variant exp` 已不适用；下面涉及这些内容的步骤仅供 1.0.14 历史排障。
- 新固件按官方 patch sets/presets 选择；不得把旧 EXP 自动映射到某个新 preset。旧 MobileGestalt 可选定制尚未移植，新固件不包含该本地开关。
- 2026-10-16 已将两台镜像独立重建到 `~/.vphone/machines/{official,custom}-2x-20261016`，默认 `start.sh` / `workstation.command` 已切到固定 2.8.0 宿主及新镜像，包含本地启动解锁超时重试。旧镜像和旧入口备份保留，实际应用、冷启动与分流验收见 `Research/branch_workflow.md`。旧 `scripts/exp.sh` 仍仅提示迁移并拒绝执行。Workstation 已验收既有两机的启停/显示；新建向导尚未适配 2.x，创建新机使用原生 CLI。
- 管理员认证要区分入口：`sudo -n` 失败只说明非交互 sudo 当前不可用，不能据此断言必须让用户自己执行。旧版 `--root-popup` 使用 macOS 原生 `do shell script ... with administrator privileges`；新版无内置弹窗时，已授权任务可通过同类系统认证调用固定的新 CLI。密码只由用户在系统弹窗输入，不自动控制被工具禁止的 Terminal，不读取密码。外部原生认证调用新版 root 创建器时，传递当前用户的 `SUDO_UID`/`SUDO_GID`，核对输出属主恢复。
- 新版完整 CFW 安装有所在卷可用容量大于 50 GiB 的固定检查；开始恢复前先核对当前实现和空间，不能仅按稀疏盘占用估计，也不绕过检查。清理源 IPSW 缓存前须保留设备原树供 product/audio repair 使用；可从同次解包原树按 iPhone BuildManifest Digest 校验后保存到安装器指定的 `FirmwareOriginals` 路径。恢复成功而 CFW 未完成时，腾空间后从 `cfw install` 继续，不能重跑 `vm create` 冒充续跑。
- 研究文档位于 `Research/`，调试记录为 `Research/debug_journal.md`。本次迁移与验收范围见 `Research/branch_workflow.md`。
- 新版 VM 安装或恢复本地 IPA/TIPA 时使用 [vphone-app-install](../vphone-app-install/SKILL.md) 及其可执行脚本；它复用原生 API 客户端，大包安装通过 WebSocket 等待结果，不能把 HTTP 超时当作允许立即重装。
- 宿主开机解锁流程修改后运行 `VPhoneExecutable/VPhoneVirtualization/Tests/run-startup-unlock-tests.sh`（编译实际扩展、仅替换测试传输），再用完整 bundle 冷启动验收。`Never` 持久不代表开机解锁通过；读取 `lock` 并核对真实桌面。
- 保留的 Python 取证工具是宿主研究工具，不进入 VPhone.bundle；产品使用上游原生实现。不要恢复已删除的 Python 补丁/安装器或使用旧资源路径测试新版。

## 以下为 1.0.14 历史排障与验证记录

目标：先核对代码来源和实际运行链路，交付最小可验证修复；把可复用的方法沉淀在这里，把每次事件的证据放在研究日志中。始终用中文沟通，先给出简短计划。

## 项目入口

- 项目根目录以本 skill 的 `../..` 为准，不依赖用户当前目录。
- 先读项目 `AGENTS.md` 与 [调试日志](../../Research/debug_journal.md) 中相关事件。旧日志是线索，需区分已观察事实、假设、已验证结论和已被推翻的判断。
- 存在 `.codegraph/` 时先用 CodeGraph 定位符号、调用路径，再补充定向文件检索；不要自动重建索引。
- 涉及 vphone600 内核分析时转读 [kernel-analysis-vphone600](../kernel-analysis-vphone600/SKILL.md)，并遵守项目内核 patch guardrails。新增二进制补丁需同步 `research/0_binary_patch_comparison.md`；普通安装器修改不增加固件补丁计数。
- 不创建、读取或更新项目 `TODO.md`。本轮计划和进度用对话记录，需要留存的结论写入研究日志。

## VM 存储与临时产物

- 所有用于自动化的镜像（官方对照、业务定制、新建/导入/恢复后的实例）必须在 iOS「设置 → 显示与亮度 → 自动锁定」中选「永不」。这是用户于 2026-10-10 明确要求的基础验收项；应检查实际勾选状态并空闲至少 2 分钟确认不熄屏、不进入锁屏。镜像更新后重新核验，不通过时不得标为自动化就绪。此设置不等于重启后自动解锁，也不要求删除密码或改变认证；冷启动后的解锁路径须单独验证。

- APFS 克隆真实已恢复镜像时，先核对运行版本的 clone 语义。本地旧实现删除 NVRAM，不应直接用于已有可启动镜像；官方 2026-10-06 `--new-identity` 仅清空配置 ECID/MAC 及冲突网络参数，保留同一停止时刻的 Disk.img、NVRAM、SEPStorage。本机真实 iOS 克隆验证见 [报告](../../Research/apfs_clone_validation_20261008.md)。新的 ECID 不代表新 IDFA、独立 SEP 根密钥或全新 App 数据。
- 验证克隆占用应比较停机后 `F_LOG2PHYS_EXT` 的物理区间并集；`du` 会重复计算共享块。正常停止应使用 vphone Quit 或先确认实际宿主 PID 的信号入口；lsof 的磁盘持有者可能是 Virtualization XPC，直接向其发信号会造成异常停机。自动化截图复用完整 JSON 响应读取，不能只 recv 一小段就关闭连接。
- 用户要求两个独立身份实例时，先根据创建记录与实际 IDFA 验证结果确定目录映射，不按 `vm2` 名称或不同 ECID 推断广告身份独立。当前历史记录中 `vm` 与旧 `vm2` 的 IDFA 相同，真正全新恢复且验证不同的是 `vm-fresh`；后者于 2026-09-22 经用户授权清空重建，已进入新机设置；本次重建后的 IDFA 尚待完成设置后重新验收。2026-10-08 用户要求只保留官方/定制两个实例，现 `start.sh` 映射为 `1/official=~/.vphone/VMs/stock-regular-guard-20261008`（官方 1.0.14 Regular + 官方 force-exc-guard）和 `2/custom=vm-fresh`（本地构建/历史 EXP）；旧 vm 及临时测试实例已按授权删除。官方 app 保存在 `~/.vphone/runtimes/upstream-1.0.14/`，不随本地 build 替换。此映射不切换 Git 分支，也不自动把新源码补丁部署到已有固件。不能将旧克隆当作已验证独立实例，也不能通过删除 NVRAM、改 ECID 或伪造 IDFA 代替全新系统数据初始化与验收。
- 启动在输出设备身份后报 `NSPOSIXErrorDomain Code=13` 时，先检查实际配置对应的 NVRAM、磁盘和 SEP 文件是否可读写。曾出现 `vm2/nvram.bin` 为 `root:staff 600`；以管理员认证仅修正该文件属主，随后继续用普通用户启动。不要用 `sudo ./start.sh`、递归放宽权限或重建 NVRAM 代替修复，否则可能继续产生 root 文件或丢失实例状态。
- 新建、克隆、导入 VM 或生成大体积备份、归档前，先检查目标位置。优先使用仓库外的既有 VM 库（默认 `~/.vphone/VMs`），不要仅为整理而搬动用户现有实例。必须放在仓库内时，在写入大文件之前用 `git check-ignore -v -- <目标目录>/Disk.img` 验证真实目标被忽略；已有文件再用 `git ls-files -- <目标目录>` 排查是否已被跟踪。`/vm`、`/vm-*/` 不覆盖 `vm2` 或任意新名字，不能凭命名猜测。
- 本机专用目录优先在 `git rev-parse --git-path info/exclude` 返回的文件中追加精确目录规则，保留原内容；需团队共享时才修改 `.gitignore`。忽略规则不影响已跟踪文件，也不能阻止显式强制添加；不要自动移除已有索引或历史。VM 磁盘、SEP/NVRAM 和固件中间产物不应进入代码提交或自动工作区快照。[Git 官方忽略规则](https://github.com/git/git/blob/master/Documentation/gitignore.adoc)
- 大体积操作前用 `df -h` 检查目标卷剩余空间，用 `du` 检查 VM、固件缓存和 Git 对象目录；根据下载、解包、恢复及导出的同时占用预留空间。稀疏磁盘的逻辑容量不等于已分配空间，APFS 克隆可能共享块，不能把多个目录的 `du` 简单相加当作可回收量。空间不足时先解决占用，不连续重试恢复、导出或打包。
- 复用已有固件缓存和已验证实例；仅在任务需要独立环境时新建 VM。临时解包、构建和诊断输出放在已忽略的任务目录，结束时清理本次可重建且未被使用的中间文件；需要保留的证据记录用途及位置。不要反复生成整机副本或归档作为默认排障步骤，也不要把旧 VM、备份或损坏镜像当作普通临时文件删除；遵循用户已明确的保留和清理范围。
- 若空间异常增长，检查 Git 对象目录的 `pack/tmp_pack_*` 及其占用进程。用 `lsof`、PID/父进程和命令确认是否为本仓库虚拟磁盘的后台 `git add`/打包；只停止已确认需要中止的相关操作，不批量杀 Git 或 VM。先修正忽略范围并确认写入已停止，再逐个检查遗留临时包是否无进程占用；仅清理确认遗弃的 `tmp_pack_*`，不删除正式 `.pack/.idx/.rev`，不以 `git gc --prune=now` 或清空 `.git/objects` 代替核查。
- 清理后复查 `df -h`、Git 对象目录占用、`git status --short` 和 `git fsck --connectivity-only --no-dangling`，确认忽略规则生效。分别报告实际回收空间和保留的实例；Git 连通性通过不等于 guest 文件系统或 VM 启动通过。已验证事件见调试日志 J-2026-09-19-12。

## 修改前：核对来源与边界

记录 `git status --short`、当前 HEAD、相关文件差异和 `git remote -v`。区分四层：官方上游、fork 的已提交改动、之前会话的未提交改动、本轮改动。

通过 GitHub MCP 确认 fork 的 parent/source、官方分支及 commit SHA，读取同一 SHA 下相关代码。当前项目已知官方来源为 `Lakr233/vphone-cli`，仍应现场核实；仅仅能在官方仓库 URL 打开一个 commit，不证明它已进入官方分支。

用 `git blame`、`git log -p -- <相关文件>` 追溯引入点，对比官方文件与本地 HEAD，不能把本地 HEAD 直接当官方版本。远端不可访问时明确标注来源尚未核实，不把缺陷定性为官方 BUG。

| 证据 | 处理 |
| --- | --- |
| 相关缺陷在已核实的官方版本中存在 | 修复具体缺陷；注明版本、触发路径和验证范围 |
| 此前本地改动引入问题，官方路径正常 | 优先精确恢复官方行为，避免在错误补丁上继续叠补丁 |
| 临时调试入口、日志增强与最终修复无关 | 在已获清理授权时移出本次修改；保留必要的证据记录 |
| 文件包含用户其他有效修改 | 按 hunk 处理，不整文件 restore；不做全仓 reset/clean |

## IPA 启动失败：取证顺序

1. 确认原始 IPA、bundle ID、VM/iOS 版本、固件 variant、安装入口，以及实际运行的 host/guest 二进制。源码、构建产物和运行中进程可能是三个版本。
2. 保持当前可启动 VM，优先使用已有 USB 配对通道抓一次失败现场。先用 `idevice_id -l` 选择目标设备，再按真实 UDID 运行：

   ```sh
   idevicesyslog -u <目标UDID> --no-colors \
     -p 'SpringBoard|runningboardd|amfid|launchd|installd|lsd|vphoned|kernel'
   ```

   同步记录点击时间、进程名/bundle ID、完整错误链和 PID。若进程已经创建，补充该应用进程日志和 `.ips`。USB 不可用时再考虑现有 guest 文件接口或已配置 SSH；不猜密码，不为取证扩大 socket 权限。
3. 根据现场区分安装/注册失败、spawn 拒绝、dyld/依赖错误、进入应用后的崩溃。`app_launch=NO`、没有 `.ips`、系统应用正常、root daemon 正常，都不能单独定位失败层。
4. `NSPOSIXErrorDomain Code=85` 表示可执行文件/共享库启动拒绝，是定位线索，不等价于某个唯一签名 BUG。按时间关联 TXM/AMFI 和 RunningBoard；不要把某一条 TXM 错误永久归为 rpcserver 噪声。
5. 追踪构建打包 → 资源解析 → host 上传 `cert_path` → guest `vp_sign_app` → LaunchServices 注册 → 实际 spawn。检查原始包和安装后的签名/entitlements，不能只检查 IPA 原件。
6. 每次只改变一个可解释的输入，重新安装同一原始 IPA，再看启动结果。没有定位证据，不新增 launchd/内核补丁，也不把重刷固件当默认尝试。固件重装可能重新注入已知有问题的 hook。

## 已验证的签名与打包约束

- 定性官方 BUG 前核对官方 README、发布 CI、接入方安装渠道和实际产物布局。当前官方完整打包入口是 `scripts/build.sh`，发布包/Homebrew 包会带嵌套证书；本项目快速说明中的 Make 路径不代表发布布局。没有具体接入方环境时，只说明已验证的不受影响路径，不猜其真实配置。
- 使用 `scripts/build.sh` 完整编译自己的源码，保留官方资源查找逻辑。完整 .app 中必须存在 `Contents/Resources/scripts/vphoned/signcert.p12`；不要使用轻量 `make bundle` 替代完整打包，也不要依靠手工复制或历史残留资源通过验证。
- 区分“本地触发条件的必要修复”与“官方正常路径的必要修改”：干净 Make bundle 缺嵌套证书，完整 bundle 和开发目录不缺；先完整打包再运行 Make 留下的旧文件也可能掩盖问题。若使用官方完整布局即可解决，应明确给出无源码修改的方案，不把其他相关缺陷修正称为启动前提。
- `VPhoneControl.signCertURL()` 找不到文件会省略证书上传；安装成功提示不代表签名可执行。缺失的资源需要追到真实消费端。
- ldid 的最终递归签名需保留每个主程序/扩展的 entitlements；`-M` 的用途是合并权限，不应依赖有没有 `-K` 证书。不能简单删除递归签名，framework/dylib 和 bundle seal 仍需要处理。
- Dopamine/TrollStore 上游约定的键是 `jb.pmap_cs.custom_trust`。拼写正确不意味着当前 VM 一定有消费者，也不能由此推断必须注入 hook。
- 恢复证书可能同时改变 CMS 和权限保留。若未做分别控制实验，只能声称“恢复证书输入解决该安装路径”，不能声称独立证明其中某一因素充分必要。
- 2026-09-18 的 J-03 验证补齐证书恢复两款 IPA；J-05 进一步回退三处生产修改、完整源码构建、重编译 Orblino Weave 并验证 guest 重启后启动及游戏连线。因此该工作流无需这三处修改；不推广为所有 IPA 或干净 EXP 固件均已验证。

## SDK 初始化后的 EXC_GUARD

- 已有应用 PID 后在 `task_swap_exception_ports` / 崩溃采集 SDK 初始化中出现 `GUARD_TYPE_MACH_PORT / SET_EXCEPTION_BEHAVIOR`，先检查官方 `--force-exc-guard` 选项和实际启动内核，不重复诊断为安装证书遗漏，也不归因于广告反作弊。
- 26.x EXP 默认不启用此项；官方 `fw patch <name> --variant exp --force-exc-guard` 后需部署到实际启动固件，单纯重编译 host 或传 `vm launch --variant exp` 不会替换已安装内核。该选项会关闭 guard violation 递送，限定用于明确需要的研究 VM，不能默认加到所有 EXP 创建流程。
- 固件流水线使用原始 IPSW 输入；对已经打过补丁的目录重复执行可能因原始指令不再存在而失败。既有 VM 上的离线单项部署属于维护操作：先停止 VM、备份磁盘/NVRAM/SEP 与原 IMG4，使用官方动态生成的记录，核对原指令与目标函数、保留容器属性和 manifest，验证精确 diff 后再部署。不得从日志硬编码地址，不未经对比整体覆盖历史固件。
- 验收必须再次触发原 SDK 初始化，确认应用持续运行并获得回调；`20001/no_fill` 只证明请求链路到达业务结果，不等于广告展示成功。第一次 `40060` 后续未复现，也不足以证明其根因已解决。

## 验证和交付

宿主/客体版本、Ping 往返和部署哈希验收见 [运行版本诊断](references/runtime-diagnostics.md)。Guest Version 返回构建标识，不是文件哈希；仅改变 Git 标识时，现有 daemon Makefile 不会自动重编译，需要先对 `scripts/vphoned` 执行局部 clean，再完整构建。

按改动选择必要检查，不因文档修改重复跑固件全量测试：

| 变更 | 检查 |
| --- | --- |
| 资源解析 | `swift test --no-parallel --filter ResourcesTests`；现有环境变量测试需串行 |
| guest IPA 签名 | `python3 tests/test_ipa_signing.py`；带证书路径必须通过；官方无证书缺陷为 expected failure，不能计作通过 |
| host / 完整产物 | `./scripts/build.sh`；构建、签名、打包 host + guest + runtime assets；不要用轻量 Make bundle 进行 IPA 验收 |
| guest daemon | `make vphoned`；确认实际 daemon 更新/重启后才声称新 guest 代码已部署 |
| 用户可见故障 | 原始 IPA 重新安装、前台页面、PID 持续存在，按问题需要再测相关主要路径 |

缺少 Xcode/ldid 导致测试跳过应标注未验证，不能算通过。host `codesign` 验证证书签名与 guest 启动是不同层级，不能相互替代。

复用现有 VM；确需新启动时先正常停止本次测试相关旧进程，确认退出，再启动。不要清理其他虚拟机或杀所有 Virtualization 服务。结束时停止自己启动的日志采集器，明确哪些临时文件仍供旧进程使用、何时可清理。构建成功不等于已替换运行中的二进制。

交付说明包含：根因与来源、保留的正式改动、移除的调试改动、实际执行的验证、运行态/产物差异和仍未验证的范围。

## 持续沉淀

测试设备上的广告自动请求及后台时间核对，使用 [广告测试取证流程](references/ad-test-trace.md) 和快捷入口 `scripts/ad_test_trace.sh`（底层 `ad_test_trace.py`）。先确认测试设备登记及当前模式；使用新截图识别测试面板按钮，不缓存滚动前坐标。分别记录 UI 操作、SDK 请求开始和回调，按报表时区及延迟核对；没有请求 ID 或测试流量统计依据，不声称与后台逐笔匹配。

每次有新的可复现发现，在 `research/debug_journal.md` 顶部追加事件：环境/版本、症状、证据、来源归属、假设及反证、修复、验证、遗留项。纠正被推翻的旧条目并标注 superseded，避免摘要继续传播旧结论；引用日志片段和版本，不能只留会过期的 `/tmp` 路径。

仅把会改变下一次决策的稳定方法提炼到本 skill：复现条件、有效判断、失效边界、验证命令。现场 PID、UDID、临时路径及单次操作留在日志；同一事实保持一个主记录位置。新增规则应来自真实故障或反例，删掉过时条目，不扩大成泛化平台或自动后台任务。

## EXP 源码构建与可复用归档

- 人工制作镜像、启用官方兼容补丁或重新部署固件时，先读 [EXP 镜像制作流程](references/exp-image-workflow.md)。快捷入口为 `scripts/exp.sh prepare NAME --force-exc-guard`；支持 `--dry-run`，只准备新 VM 的固件，后续恢复、CFW 安装、首启和导出分步进行。
- 官方 1.0.14 的 `vm create` 不提供 `--force-exc-guard`，内部固定关闭。不要向原 `create` 入口透传此参数或假定环境变量生效；需要该选项时使用上述分步流程，不修改 Swift 创建器只为传参。
- 长期基线：官方 `1.0.14` / `9c23c8a`，自有 `codex/business-vm` 维护定制（原 `tb_dev` 保留历史指针；见 research/branch_workflow.md）；更新时重新核对上游，不把本地 HEAD 当官方。EXP 在同一源码内，通过固件参数选择，无需切换所谓 EXP 分支。
- 使用项目根目录的 [scripts/exp.sh](../../scripts/exp.sh)：薄封装官方 `build.sh`、`vm create --variant exp`、`vm export`；不复制固件补丁逻辑。

```sh
# 完整编译当前源码 → 新建 EXP → 首启检查 → 导出压缩包和 SHA-256
./scripts/exp.sh create myphone-exp /absolute/output/myphone-exp.tzst \
  --iphone-source /absolute/firmware/iphone.ipsw \
  --cloudos-source /absolute/firmware/cloudos.ipsw

# 导出已经验证的本项目 vm（先正常停止；export 不自动关闭任何 VM）
VPHONE_LIBRARY_ROOT="$PWD" ./scripts/exp.sh export vm /absolute/output/exp.tzst

# 复用归档：使用新的名字导入，再启动
./.build/vphone-cli.app/Contents/MacOS/vphone-cli vm import /absolute/output/exp.tzst --name restored-exp
./.build/vphone-cli.app/Contents/MacOS/vphone-cli vm launch restored-exp --variant exp
```

- 初次准备依赖仍使用 `scripts/setup_tools.sh`。创建流程需 sudo；在终端交互输入，不把密码写进参数或 skill。省略 IPSW 参数时遵循官方交互选择；可复现基线需记录两份 IPSW 版本/校验值、源码 SHA、submodule gitlinks 和显式环境选项。
- 默认库为 `~/.vphone/VMs`；用 `VPHONE_LIBRARY_ROOT` 指定其他位置，使创建和导出指向同一个库。脚本拒绝覆盖已有 VM/归档和导出占用中的磁盘。
- `.tzst` 是含磁盘、设备身份和客体数据的 VM 归档，不是通用可刷写 IPSW；默认按官方逻辑排除恢复中间目录。要分发干净环境，应新建专用 VM，不发布含个人数据的现用 VM。
- 当前 `vm` 的 EXP 来自历史安装，O-2 launchdhook 和 O-3 DSC 完整性仍需独立验证。导出成功或 IPA 正常，不代表已验证干净 EXP 从零创建。不要为验证 IPA 自动重刷它；历史构建的 `DISABLE_LAUNCHD_HOOK=1` 是有记录的环境例外，不悄悄写成所有 EXP 的默认值。
- 验证分层：完整构建 → guest 版本/哈希确认 → 原始或新编译 IPA 重装 → 冷启动、前台页面和交互 → 停机导出 → 归档完整性。新建、导出、导入、首启分别报告实际执行范围。

## 现有旧实例的 Workstation 管理（2026-10-16）

- `workstation.command` 使用相邻 `vphone-ws` 仓库的本地 app 和现有完整 CLI；两实例通过 `~/.vphone/workstation-library` 的目录链接汇总，sidecar 固定各自宿主及 variant，不升级 guest。验证范围见 [Workstation 报告](../../Research/workstation_validation_20261016.md)。
- 旧 CLI 从汇总库导出前必须解析到真实目录，否则 tar 可能只打包链接。磁盘空间不足时保留“完整导出未验证”，不能以参数测试或空归档代替成功，也不为测试生成额外整机副本。
