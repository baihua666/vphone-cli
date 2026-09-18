---
name: vphone-development
description: Use when developing or debugging this vphone-cli repository, especially IPA installation or launch failures, resource packaging, upstream-versus-local regressions, or maintenance of the project's debugging knowledge.
---

# vphone 项目开发与排障

目标：先核对代码来源和实际运行链路，交付最小可验证修复；把可复用的方法沉淀在这里，把每次事件的证据放在研究日志中。始终用中文沟通，先给出简短计划。

## 项目入口

- 项目根目录以本 skill 的 `../..` 为准，不依赖用户当前目录。
- 先读项目 `AGENTS.md` 与 [调试日志](../../research/debug_journal.md) 中相关事件。旧日志是线索，需区分已观察事实、假设、已验证结论和已被推翻的判断。
- 存在 `.codegraph/` 时先用 CodeGraph 定位符号、调用路径，再补充定向文件检索；不要自动重建索引。
- 涉及 vphone600 内核分析时转读 [kernel-analysis-vphone600](../kernel-analysis-vphone600/SKILL.md)，并遵守项目内核 patch guardrails。新增二进制补丁需同步 `research/0_binary_patch_comparison.md`；普通安装器修改不增加固件补丁计数。
- 不创建、读取或更新项目 `TODO.md`。本轮计划和进度用对话记录，需要留存的结论写入研究日志。

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

## 验证和交付

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

每次有新的可复现发现，在 `research/debug_journal.md` 顶部追加事件：环境/版本、症状、证据、来源归属、假设及反证、修复、验证、遗留项。纠正被推翻的旧条目并标注 superseded，避免摘要继续传播旧结论；引用日志片段和版本，不能只留会过期的 `/tmp` 路径。

仅把会改变下一次决策的稳定方法提炼到本 skill：复现条件、有效判断、失效边界、验证命令。现场 PID、UDID、临时路径及单次操作留在日志；同一事实保持一个主记录位置。新增规则应来自真实故障或反例，删掉过时条目，不扩大成泛化平台或自动后台任务。

## EXP 源码构建与可复用归档

- 长期基线：官方 `1.0.14` / `9c23c8a`，自有 `tb_dev` 维护定制；更新时重新核对上游，不把本地 HEAD 当官方。EXP 在同一源码内，通过固件参数选择，无需切换所谓 EXP 分支。
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
