# Subway Surfers 非定制对照（2026-10-08）

## 结论状态

**官方 1.0.14 Regular + 官方 `--force-exc-guard` 已复现严重 3D 花屏；本 fork 定制及 EXP 不是症状出现的必要条件。具体图形根因与 APFS 因素仍未定位。**
原 APFS 测试的 Subway Surfers 3.69.2 仍为「3D 图形失败」。进入游戏、计分和暂停成功均不能替代渲染验收。

## 对照来源

- 原 `vm` 和 `vm-fresh` 都是 EXP；历史独立磁盘不等于非定制固件。本轮没有用它们冒充官方 Regular。
- 从 [官方 1.0.14 发布页](https://github.com/Lakr233/vphone-cli/releases/tag/1.0.14) 获取原始发布包。
- 发布 ZIP SHA-256 `5d851835f1ae3d4449601deae5dcb60b3d29620ac549daf6ce2f735009f4bb13`，与 GitHub asset digest 完全匹配；完整 app 的 codesign 校验通过。
- 使用发布包自身 host、脚本和资源；未使用本地自编译 app 或本地 MobileGestalt patcher。抽查 CFW 基础安装器、host 安装器、EXP DSC patcher 与 `9c23c8a` 逐字节相同。
- 新目录 `/Users/tubao/.vphone/VMs/stock-regular-20261008`；空盘独立恢复，4 CPU、4096 MiB、64 GiB 逻辑磁盘；ECID `DE8B035FFDE50E52`。
- iOS / cloudOS 均为 26.1 / 23B85；官方 Regular 默认参数，未加 `--force-exc-guard`、Frida 或 EXP 身份伪装。
- 这里「非定制」指不含本 fork 改动、采用上游 Regular；vphone 必需的官方 CFW 补丁仍存在，不是未经修改的 Apple 原生 iOS。

## 已完成

| 阶段 | 结果 |
| --- | --- |
| 官方包及原始输入 SHA-256 | 已记录 |
| 新 VM 建立 | 完成；未覆盖已有目录 |
| 官方 fw prepare | 退出 0 |
| 官方 fw patch --variant regular | 退出 0；9 个组件、58 条记录 |
| 获取新 ECID 的 SHSH | 退出 0 |
| 显式 ECID 定向 DFU restore | 退出 0，记录 26.1/23B85 |
| 停止 DFU host | 实际 host PID 收到 SIGINT 后退出；磁盘无占用 |
| 官方 cfw install --variant regular --root-popup | 退出 0；Cryptex、GPU 驱动、vphoned 与 snapshot flip 均完成 |
| 首启 | 用户已完成系统设置及 USB 配对 |
| 安装同版 Subway | 官方内置安装器安装成功；3.69.2 / 96072 |
| 默认 Regular 启动 | EXC_GUARD 崩溃，尚未进入 3D |
| Regular + 官方 force-exc-guard | 主菜单和实际跑酷均严重 3D 花屏；截图计分 35，图形验收失败 |

原始 IPA：`~/Downloads/com.kiloo.subwaysurfers-3.69.2-Decrypted.ipa`。
SHA-256：`dc8733dd1908c7f73df2248938a7bab68dd4cddaebfb5a2c01dcca6e2492ede2`。

## 存储与保留

保留 `vm`、`vm-fresh`、两个 cow-test 克隆、历史备份和旧固件解包目录；本轮未启动这些实例。
初始约 31 GiB 空闲。官方准备器普通复制 IPSW 会产生额外 10 GiB，已在恢复前中止首次准备、删除仅本轮生成的不完整缓存，改用 APFS 克隆原始 IPSW 后重新准备成功。
新恢复树的四个大型 DMG/AEA 输入与旧目录 SHA-256 完全相同时，以 clonefile 语义复用底层块；二者仍是独立文件，未更改旧文件。此优化只作用于安装输入，新 Disk.img 来自独立空盘，不是既有 EXP 磁盘的克隆。无需清理之前询问的旧解包目录。

## 下一步验收

1. 系统首启、配对及安装已完成；等待用户完成游戏自身年龄和首次提示。
2. 保持同一 IPA、官方发布 app 与可追溯的兼容选项。
3. 进入同一游戏主菜单、Tap to Play、至少一段实际 3D 跑酷、暂停；保留截图和日志。不能只看加载图、2D 菜单或广告视频。
4. Regular 若同样花屏，说明本地定制和 EXP 不是该症状出现的必要条件；仍需区分虚拟 GPU、宿主系统、游戏包及其兼容性，不能立即锁定某个上游补丁。
5. Regular 若正常，再增加官方 EXP 对照区分上游 EXP 与本地部署差异；Regular/EXP 一次对照不能自动定位某条本地代码。
6. 全部结束后停止本轮启动的 VM，记录磁盘占用和可复现命令。

## 证据

本地证据：`.build/validation/subway-stock-20261008/`，含发布包、原样 app、provenance.json、input-sha256.txt、official-resource-check.json、identical-input-clones.json、prepare/patch/SHSH/restore/CFW 日志。
通过 GitHub MCP 搜索 Subway、Unity、Metal corruption；没有找到同款 Subway 证据。[上游 #420](https://github.com/Lakr233/vphone-cli/issues/420) 是 iOS 18.6.2 UI 渲染异常，版本/症状不同，仅作线索，不用于当前归因。

## 默认 Regular 与官方兼容选项的实测

默认独立 Regular 的 `SubwaySurf-2026-10-07-203744.ips` 显示 `EXC_GUARD / GUARD_TYPE_MACH_PORT / SET_EXCEPTION_BEHAVIOR`，栈为 `FIRCLSMachExceptionInit -> task_swap_exception_ports`。与 MCP 核实的[官方 #291](https://github.com/Lakr233/vphone-cli/issues/291)相符；这证明启动兼容问题，不是花屏复现。

用原始 cloudOS 输入和未修改的官方发布 app 分别重新生成 Regular（58 条记录）及 `--force-exc-guard` Regular（59 条）。实际部署内核 payload 与重新生成的默认 Regular 完全一致；两个 payload 及最终 IMG4 都只相差 4 字节，来自官方动态记录的 `kernel.thread_guard_violation`，保留原 manifest/container。无新增 patch 实现。

默认 Regular 停止后，clonefile 至 `/Users/tubao/.vphone/VMs/stock-regular-guard-20261008`，只部署上述官方 delta，回读哈希验证通过。保持同一身份，仅顺序运行；默认源保持停止且未修改。兼容副本使用官方 app 启动，IP 192.168.64.56。

实际唤醒、解锁并点击后，Subway 已通过加载进入年龄确认页，截图 `guard-first-screen.png`。此前停留 Home 且无新增 crash 的观察不能算第二次启动失败；屏幕锁定时截图可能保留旧帧，必须唤醒后操作并观察应用画面。当前由用户完成游戏年龄和首次提示，再继续实际跑酷及暂停取证。

兼容副本本身使用 APFS 克隆；即使复现也只能先证明本 fork/EXP 并非必要条件。若需排除 APFS 克隆因素，还须在独立磁盘上用相同官方兼容配置复测。不得将此副本称为未启用任何兼容补丁的默认 Regular。

新增证据：`regular-records.json`、两份 official raw payload、`deployment-check.json`、`deployed-guard.json`、原始/兼容 IMG4、`guard-launch-syslog.log`、`guard-crashes/`。仅旧继承崩溃已被拉取；当前没有第二次崩溃证据。

## 实际 3D 对照结果（用户完成游戏引导后）

用户报告“也花屏”，现场再次核对运行进程：官方发布包 app，配置 stock-regular-guard-20261008，variant regular。主菜单截图 `guard-user-corruption.png` 显示大量拉伸几何与重复贴图，Tap to Play 字样正常；实际点击进入跑酷，`guard-play-corruption.png` 计分 35、暂停按钮和金币 HUD 清晰，3D 依然严重损坏。已发送暂停操作并保存 `guard-pause.png`（是否成功暂停以画面为准）。

这与旧 EXP 克隆的症状相同，证明不需要本 fork 自编译宿主、本地 MobileGestalt 定制或 EXP 固件也能出现该故障。不能据此宣称某个 GPU 驱动已被定位，也不能排除同一第三方 IPA、宿主环境、官方兼容补丁或 APFS 克隆变量。默认独立 Regular 保持原样且停止；兼容副本保留当前现场，日志采集器已停止。下一项有区分力的测试是独立磁盘上运行相同官方兼容配置；本轮不将游戏判为通过。

## 独立物理副本续测准备与阻塞

2026-10-08 现场：macOS 27.0.1 (26A434)、Apple M4 10 核 GPU、Metal 4。目标卷仅约 3.65 GiB 可用；Regular Disk.img 逻辑 64 GiB，st_blocks 分配约 17.07 GiB。这里分配值仅用于普通副本容量估算，不能把两份 CoW 的 st_blocks 相加当真实占用。没有足够空间制作不共享块的副本，尚未复制、重刷或删除任何现有 VM。已请求至少 25 GiB 空闲目标位置或明确可清理目录。

完整非 CoW 对照必须用普通读写复制（稀疏零区允许保留），不能再用 clonefile，也不能仅把已参与共享的源盘改名叫“独立盘”。停机复制后需全量哈希相等，并用已有物理 extent 检查确认与当前镜像无交集，再以同一官方 host/兼容选项/IPA 启动验证。为了保持游戏数据一致，可直接复制已完成引导的兼容实例；默认 Regular 仍原样保留。保存当前取证后，向已确认的宿主 PID 27543 发送 SIGINT，宿主/launcher 已退出且 Disk.img 无打开句柄；日志采集器也已停止。

MCP 最新核查：上游 main 已发布 2.8.0，不能把本次 1.0.14 称为最新版。本次仍固定 1.0.14 以避免引入多变量。[PR #624](https://github.com/Lakr233/vphone-cli/pull/624) 针对 iOS 27 分块 DDI 串流引发宿主 GPU 死锁，不是当前 26.1 游戏 3D 畸变的已证实修复；[PR #493](https://github.com/Lakr233/vphone-cli/pull/493) 在 iPhone 26.6.2/cloudOS 26.4 验证 GPU 编译插件解决全屏黑屏，亦不是本例证据。限定仓库的 Subway issue 搜索无结果，不能据此称问题不存在。

已抽取当前日志中 Subway 的 Metal/Unity 行到 `subway-graphics-log-extract.txt`，228 行；看到 Metal shader 编译活动，但这不能证明 shader 输出正确或定位花屏根因。容量与宿主信息见 `independent-control-preflight.json`。

## 用户授权收敛为两个工作镜像（更新此前保留策略）

用户明确只需官方与定制各一份，并授权删除旧独立镜像。已确认无磁盘持有者后删除旧 `vm`、临时 cow-test-a/b 以及被兼容版替代的默认 stock-regular。保留官方 `~/.vphone/VMs/stock-regular-guard-20261008` 与定制 `vm-fresh`。旧配置与删除清单保存于 consolidation/manifest.json；历史备份、日志、截图均未删除。默认 Regular 的崩溃证据和原始 IMG4 保留，但整机已依用户新指示删除。

停机完整扫描两份剩余 Disk.img，物理区间交集为 **0 字节**（remaining-extents.json）。官方盘物理区间约 17.14 GiB，定制盘约 24.28 GiB。官方盘有 clonefile 历史，但其对照源已删除，当前两个工作实例不共享磁盘块；这不等价于历史克隆从未发生。原先“必须额外制作第三份普通副本”的计划因此不再符合仅保留两份工作镜像的要求。

`start.sh official` / `1` 使用独立存放的官方 1.0.14 app 与 Regular；`custom` / `2` 使用本地完整构建与 vm-fresh EXP。默认 official。该入口不切换 Git 分支，不自动部署固件；官方基线固定 1.0.14，并非最新 main。定制盘保留历史 EXP/App 数据，不能仅凭启动本地 app 声称所有新的源码定制都已写入客体。

官方 app 的此前固件安装产生 root-owned __pycache__，迁移后复核时发现资源 seal 因新增缓存不通过。未改签名；把旧 app 留为 installer-cache.app，从已校验原始发布 ZIP 重新解出正式 vphone-cli.app，codesign --verify --deep --strict 已通过。正式运行路径为 ~/.vphone/runtimes/upstream-1.0.14/vphone-cli.app。start.sh zsh 语法及 help 检查通过。

重新解出的官方 app 已检查 118 个发布文件，零差异；通过新 official 启动入口进入 iOS 主屏并再次启动 Subway，加载过程正常。consolidation/official-archive-match.json 保存比对结果。

删除共享对照源后，重新启动经 118 文件验证的官方发布程序；主菜单及实际跑酷（计分 33）仍严重花屏，证据 consolidation/official-unshared-menu.png 与 official-unshared-play.png。两份当前工作盘共享为 0，因此它们之间的实时块共享不是症状必要条件；不能从删除源推导已排除所有历史克隆/快照因素。最终官方 VM 留在主屏，定制 VM 停止。
