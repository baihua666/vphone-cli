# 旧实例黑屏：调查与已部署修复

2026-10-26 用户报告 2-20261023 / 3-20261023 一直黑屏。先前仅凭历史连接日志认定系统可用不充分，现撤回该可用性判断。

## 现场结果

- 1 号为健康对照；1、2 同时运行，本轮未启停它们。3 号起始停机，本轮正常启动并最终恢复停机。
- 同一检查 `vphone-launchpad-cli guest send <name> '{"t":"rpc","method":"device.info","screen":true}'`：1 号有 image 字段，2 号重复检查均无 image，3 号也无 image；三者 device.info 均响应，iOS 26.6.2、screen_off=false、locked=false。客体与宿主截图使用不同链路。
- 2 / 3 的 `t:screenshot`（客体 screen.screenshot）都返回桌面，但应用图标缺失；3 号另有 Misconfigured Device / VPHONE600.Default.plist 缺失提示。1 号宿主帧桌面图标正常。
- 3 号第一次正常启动，vphoned 在 15 秒后响应。进程启动/HTTP 响应不作为图形桌面可用验收。
- 两台 restore-info.json 缺失，列表系统列因此为“—”。该元数据缺失不等于没有 iOS，也不能单独解释黑屏。
- 2 / 3 当前 Core 绑定为 2.13.4-local.666ac4da，guestEnvironment 记录仍为 2.8.0-local.199abaf3。但三个实例 device.info 的 vphoned binary_hash 相同，日志可见启动后自动同步 vphoned / hook 库。因此 guestEnvironment 标签本身也不能代表实际每个文件仍是旧版。

## 单变量验证与排除

- 3 号 2 CPU / 3072 MB → 正常停机 → 仅调为 4096 MB → 正常启动：device.info 确认内存改变，但宿主仍无显示帧。随后正常停机，恢复 3072 MB。config.plist 和 launchpad.json 与本轮前备份逐字节一致。
- 1 号和 3 号 EventTimingProfiles 中都无 VPHONE600.Default.plist，所以提示本身不能被当作两台黑屏的特异性原因。
- IOMFB “No Default FB Surface found” 在健康 1 号启动日志中也出现，不能仅凭该条通用日志判定根因。
- 宿主统一日志未提供可归因于此黑屏的特异性错误。RAW 磁盘 userdata format、Spotlight 和未配对生物识别提示不是已证实根因。

## 已定位与尚未定位

已定位：客体内核/桌面在运行，但宿主显示路径未获得可显示帧；属于图形显示故障，而非空盘/未安装 iOS。未证明是哪次升级、迁移、缓存或窗口行为引入，未宣称已修复。

下一步待用户确认：仅 3 号保留停机快照后，对照原 2.8.0 与当前 2.13.4。原因是正常启动会自动同步客体组件，这超出只读检查；不自动切换绑定或执行 cfw install/update-environment。等待期间保持停机，1 / 2 不动。

证据在既有工作树 .build/black-screen-20261026/，包含三台宿主检查结果、3 号 guest 截图、内存对照、配置备份和日志。2 号初次 guest 截图在 .build/separate-app-update/black-screen-2.jpg。未上传任何镜像，没有修改 Core 源码、guest 补丁或 Helper。

## 用户授权后的 Core / 镜像双因素对照

用户明确允许仅 3 号留停机快照后验证 2.8.0 / 2.13.4，允许正常启动自动同步组件。本轮先建立 `before-black-screen-ab-20261026`，且不删除已有 `before-core-280-20261022`。

| 3 号磁盘/SEP/NVRAM 基线 | 2.8.0-local.199abaf3 | 2.13.4-local.666ac4da |
| --- | --- | --- |
| 今天检查前的状态 | 客体有桌面，宿主无 frame；图标缺失 | 客体有桌面，宿主无 frame；图标缺失 |
| 2026-10-22 23:13 迁移前快照 | 宿主有 frame，桌面图标正常 | 宿主有 frame，桌面图标正常 |

每组启动前先停机并从对应快照恢复，避免相邻测试的自动库同步污染基线。历史快照内的信任电脑弹窗未点击，也未增加信任关系。

### 根因定位与证据强度

直接验证：同一配置、同一内核、同一 Core 下，仅更换持久化状态，宿主显示结果从失败变正常，反向对照也一致。最新 App、单一 Core 版本、3 GB 内存、缺失系统版本显示元数据，都不能独立解释本例。

已发现与故障一致的具体错误：旧机缺少 PatchPlan.plist / PatchSelection.plist。更新器 readPatchPlan 回退分支打印 `No patch plan recorded; applying every guest patch`，无计划的 on() 会把 legacy 实验客体补丁打开。2 / 3 的 PatchReceipt.Guest Writer 都是 `cfw update-environment`，分别在北京时间 2026-10-22 23:38:33 / 23:46:35 写入；包括 dyld-exp-hv_vmm。健康 1 号保留补丁计划，旧 2 / 3 均无计划。

- 3 号历史正常 / 当前黑屏，以及 2 号当前的 Preboot kernelcache IM4P SHA-256 完全相同：`ebed18ac19baca44bfa19b32d4569af1b92fc2b4664f62350f650d22e728a0df`。
- 只读解出历史 kernelcache payload，其标识为 `Darwin Kernel Version 25.4.0 / RELEASE_ARM64_VRESEARCH1`（vphone600 研究平台使用的 release 内核，本轮未做符号地址/反汇编分析）。字符串表有标准 `hv_vmm_present` / `kern.hv_vmm_present`，无 `Xv_vmm_present`；相同 kernelcache 字节证明当前也未配套改名。
- 历史正常共享缓存 undo ledger 只有 6 个 dyld-cfw-camera 记录；当前 2、3 号均新增 22 个 dyld-exp-hv_vmm 和 1 个 dyld-exp-mis_trust_auth。
- 已抽查当前 3 号真实 chunk `dyld_shared_cache_arm64e.07`，FileOffset 22731205 的原始 h 被改成 X，周围字符串实际为 `kern.Xv_vmm_present`。不是仅凭 receipt 推断文件已修改。
- 此实验补丁的设计契约要求内核 OID 与用户态库配套改名；单独改用户态会查询不存在的 OID，影响需要真实虚拟机判断的图形组件。该配对错误是本例的主要原因，证据强，但本轮尚未做“仅撤回这 22 处修改后出图恢复”的最小修复对照；不能声称每个补丁的独立因果都已验证。

判断：10 月 22 日的旧实例环境迁移在无补丁计划时退回“全部客体补丁”，把实验用户态虚拟化识别改写应用到未改名内核，造成内核/共享缓存不配套。A/B 与文件检查均支持该链路；这是迁移策略缺陷，而非无系统或用户设置了错误版本。不能从快照对照单独排除所有其余同期 guest 修改。

### 最终恢复与后续边界

- 正常停止 3 号，使用当前 Core 的既有 snapshot revert 恢复 `before-black-screen-ab-20261026`，而不是把 10/22 旧数据留在正式实例。
- 3 号 config.plist / launchpad.json 与本轮前备份 cmp 相同；SEPStorage / nvram.bin 与本轮前快照 cmp 相同。磁盘由官方快照恢复成功，未另做 60 GB 全盘散列。
- 最终 3 号保持 2 CPU / 3 GB、Core 2.13.4-local.666ac4da、guestEnvironment 记录 2.8.0-local.199abaf3、stopped；1 / 2 号未启停、未修改绑定，仅对 2 号做只读文件取证。
- 未执行 cfw install、update-environment、内核更新、实验补丁开关变更或重新安装系统；两份快照保留。未上传镜像。
- 真正修复应先确认现有撤销 ledger / 签名页重算能力，再仅撤回错配 guest 实验项并保留用户数据；更新器无计划时不能再默认开启实验补丁。实施属于 guest/Core 范围，须按 AGENTS 单独确认，不由本次 A/B 授权推定。

## 用户确认后的修复与真实验收（2026-10-26，更新以上待修复状态）

用户明确确认：先修 3 号，验收后再停机修 2 号；允许修改 Core 更新器与 guest。安装新 Core 的 macOS 管理员认证由用户在系统弹窗亲自完成，没有读取密码或绕过 Helper。

### 完整原因与必要的缓存恢复

第一轮在 3 号撤回 22 个 dyld-exp-hv_vmm 字节并重算 22 个签名槽位（13 个 chunk，0 skipped），同时从备份恢复 watchdogd 后，宿主仍无显示帧。读取到 MobileGestalt 能力缓存的时间为 2026-10-22 23:46:48，即错误迁移 receipt 的 13 秒之后。将这份可重建缓存另名备份，再正常冷启动，同一 Core、同一其余状态下显示恢复，图标与应用界面正常。仅修补丁字节并不足以撤销已缓存的硬件能力判断。

最终包自动完成这一步：hv_vmm dyld 状态确实变化时，更新器在 guest System 卷写入 `System/Library/Caches/com.vphone.MobileGestalt.invalidate`；vphoned 复用已有 MobileGestalt 缓存失效机制，只移除早于该状态标记的缓存，沿用 health 的 `mobilegestalt_restart_pending`。本轮不新增 RPC、CLI 参数或 Helper 协议，不写恢复版本元数据，不更换内核或设备身份。

2 号使用最终包直接验证自动流程：第一次启动 health 的 mobilegestalt_restart_pending=true；正常停机、第二次冷启动后为 false，宿主帧、桌面图标与 Instagram 欢迎界面全部恢复。没有对 2 号另行手工清缓存。3 号的原缓存备份保留在原 guest 缓存目录的 `com.apple.MobileGestalt.before-display-repair-20261026.plist`，两机修复前缓存亦保存在本机证据目录。

### 源码修正范围

- `FirmwareGuestPatchResolution`：无计划时不自动开启新的实验补丁，其它已有实验 opt-in 按 receipt 保留。hv_vmm 的 guest 半边依据实际内核 OID，而非猜测内核 receipt；显式选择也校验 kernel / dyld / watchdog 配对。
- `VPhoneCustomFirmwareInstaller`：从私有磁盘克隆的 Preboot 只读提取实际 kernelcache，校验 NUL 分隔 OID。普通 guest 与 dyld、Preboot pass 共用 legacy 策略；undo 记录也作为真实已应用状态。状态改变后仅安排上述硬件能力缓存失效。
- `patch-dsc-revert`：读取失败不能冒充没有日志；所有触及签名页 fully attested 后才移除 undo 记录。
- `GuestMobileGestaltCache`：保留设备树时间失效逻辑，增加 hypervisor 修复标记，重建后的新缓存不会反复清理。跨 host/guest 路径有显式契约测试。
- 以上为最初部署修复的源码形态：未新增补丁或改变 preset，没有新增内核指令补丁；现有 experimental hv_vmm 声明与选择开关保留。后续维护隔离已增加具名编译开关，见下节，未替换本机已部署包。

### 构建、测试与部署

- 回归先红：原 legacy 策略使“无计划实验默认关闭”和“未改名内核撤销用户态”断言失败；修复后 FirmwareLegacyGuestPatchTests、FirmwareGuestPatchResolutionTests、DyldSharedCacheUndoLogTests 共 39 测试通过。
- GuestMobileGestaltCache 的真实临时文件测试通过：旧缓存失效、重建缓存保留、相同时间保留、旧设备树失效仍有效、host/guest 标记路径一致。
- 完整 VPhone workspace Debug bundle 构建、bundle admission、deep strict 签名通过；不把单独 CLI 编译当作完整产物。
- 最终正式用于本机修复的内容身份：`2.13.4-local.1da558c7`。seal SHA-256 `1da558c73f7230feb6e5e807c59be64a475601ad0c0f3efc9be23d747dcfe4a8`，helper receipt 归档 SHA-256 `2fd1b2e11d280bb0043a11c4601b20de09824928dd7859dc662f03468a9ee8d1`。官方基线仍 2.13.4 / 7f55bebdcbed913541928b9c4b1c1ca79abc0822，无新产品版本号或公开发行。
- vphoned 实际运行 SHA-256 与最终包相同：`7f67bf34e63807e7b0036ead0b1c21ebdfd33630269f89d55e7827ea99bc49da`。
- 修复过程的中间包 `2.13.4-local.389ee5fd` 保留用于取证，但无实例继续绑定；2、3 最终均绑定 `1da558c7`，原绑定 JSON 保留可回退。默认 Core 和 1 / 4 / 5 / wizard 的绑定未改变。

### 实例结果与保留数据

| 项目 | 2-20261023 | 3-20261023 |
| --- | --- | --- |
| 修复前停机快照 | before-black-screen-repair-20261026 | before-black-screen-repair-20261026 |
| 系统 | iOS 26.6.2，未重装 | iOS 26.6.2，未重装 |
| 原用户应用 | 5 个 Bundle ID、版本、安装路径保持 | 5 个 Bundle ID、版本、安装路径保持 |
| 原 Data 容器目录 | 242 个均保留 | 242 个均保留 |
| 配置 | config.plist 与修前逐字节一致 | config.plist 与修前逐字节一致 |
| 真实 UI | 桌面图标及 Instagram 欢迎界面出图 | 桌面图标及 Instagram 欢迎界面出图 |
| 冷启动 | 最终包两次启动，缓存待重启状态清除 | 最终包冷启动有宿主帧 |
| 自动锁屏 | Never | Never；空闲至少 240 秒仍亮屏未锁定 |
| 最终状态 | running，最终修复 Core | running，最终修复 Core |

应用与目录保留不等于逐项验收所有应用数据内容；没有登录、注册或发送内容。没有改 VM 的 ECID/MAC/内存/CPU/网络配置，没有为修系统列“—”伪造 restore-info.json。系统列的历史元数据缺失仍是另一个显示问题。

沿用的环境更新流程也重新部署了当前 Core 的常规 guest 组件及其既有基础修复，因此不把这一轮表述成只修改 22 个字节、其余所有系统文件都未动。关键缓存步骤则在 3 号做了额外单变量验证，并在 2 号完整自动验收。

环境更新仍提示两台缺少原始 DeviceTree.d47ap.im4p，历史 board audio repair 无法完成。本轮没有下载或补入原始固件，未做音频、Siri、Camera Control 等额外硬件功能验收。没有更换运行中的 Launchpad，没有上传镜像或分片。

回退需要正常停机后用同一实例的修前快照同时恢复 Disk、SEPStorage、NVRAM，再恢复各自备份的原 Core 绑定；不能只恢复 Disk 或把关闭编译宏当作 guest 回退。两台当前修复后的数据不应被自动回滚，必须由用户明确选择。

证据：本工作树 `.build/legacy-guest-repair/`，含 red/green/final tests、完整构建日志、helper 安装与更新输出、两台修前/修后应用与容器清单、实际宿主帧、两次启动 health 状态、配置/绑定备份及签名 seal。快照在各自 VM 的 Snapshots 内。

最终空闲验收：2 号回到主屏幕后无输入 250 秒，3 号最终 Core 冷启动后无输入 865 秒，均有真实宿主帧、screen_off=false、locked=false。两台均确认 Auto-Lock=Never，最终 Core/guestEnvironment 身份一致。再次检查 1 号 boot_session_uuid 与最初只读取证一致，证实未重启；两台修前快照仍在。39 项最终回归、缓存真实文件测试、最终已安装 Core deep strict 签名全部通过。本次构建中间文件的可选清理被工具拒绝（不允许 rm -f 类命令），未绕过限制，构建缓存保留。

## 后续维护隔离（源码整理，未部署）

用户要求本地改动易维护、尽量通过 Hook 隔离。已将 legacy 策略、内核读取适配和 guest 修复标记判断移入各所属 target 的 `Customizations/LegacyGuestRepair/`。上游 `FirmwareGuestPatchResolution.swift` 恢复原样，安装器和缓存原入口仅保留静态调用；不是动态注入。宿主使用闭包复用既有受限读取/写入能力，guest Hook 只读，删除和重启状态仍归原模块。

编译条件 `VPHONE_CUSTOM_LEGACY_GUEST_REPAIR` 在 CLI / FirmwarePatcher / 测试与 guest 的既有 target 配置默认开启；`VPHONE_LEGACY_GUEST_REPAIR=` 可关闭，StageBundle 显式传递到嵌套构建。关闭时不读内核、不读修复标记、不写 guest 标记，并恢复原 no-plan 策略。签名页完整性检查作为通用修正仍留在原代码，不受此本地策略开关控制。

开启的 39 项回归、关闭的 34 项基础回归、guest 两种编译状态测试及关闭宿主 Hook 的零读取/零写入测试通过。完整构建与签名证据位于 `.build/legacy-guest-isolation/`；维护、停用和移除方式见 [静态 Hook 维护说明](../../Documents/Guides/legacy-guest-repair-customization.md)。本轮不安装新包、不改变 VM 绑定或 guest，不把源码开关当作已部署系统回退。

最终完整 VPhone Debug 构建的开关两态均通过 bundle admission 和 deep strict 签名；实际 CLI / vphoned 的标记字串随开关出现或消失，确认嵌套构建没有吞掉空值。仅供本地测试的 ON seal 为 `9e7ad669610ff6f413d27d1ad5d19d6ddd27624324018c60590930944fb9dbfe`，OFF seal 为 `324a75499c2a25923af46dbcfd69b3d8c0c177d82a169cb86343f4e2cd8f106c`。验证期间发现 Xcode 不导出空构建设置，已增加非空前缀转发，并重做完整两态构建，而非仅根据 build 成功判定关闭有效。`verification.json` 记录实际包核对；已安装 `1da558c7` seal 和所有实例的 Core / guestEnvironment 绑定与本轮前一致。新产物未安装、未发布。
