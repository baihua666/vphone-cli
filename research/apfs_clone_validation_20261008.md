# APFS 克隆真实 VM 验证（2026-10-08）

本轮目标：保留独立对照镜像，验证共享磁盘块的真实 iOS 虚拟机，而非只验证普通文件的 clonefile 行为。结论按单项验收，不将启动成功等同于全部 App 兼容。

## 环境和隔离

- macOS 27.0.1；本地代码 HEAD `0f76ba1214e6ce3e0b35cf46b581069792e53988`。
- 使用既有已签名 `.build/vphone-cli.app`；host 二进制 SHA-256 `35836b2a2dad944f8ba02d743b4643f28e164c3d58cd3eebf1a91fc23251c48a`。本轮没有替换固件、重新编译运行产物或修改生产代码。
- `vm`：独立历史镜像，保留用于 App 对照；不是本轮克隆来源。
- `vm-fresh`：本轮克隆来源，全程停止，保留原状。
- A：`~/.vphone/VMs/cow-test-a-20261008`。
- B：`~/.vphone/VMs/cow-test-b-20261008`。
- A/B 均为 iOS 26.1，4 核、4 GiB 配置，64 GiB 逻辑磁盘。分配空间与实际私有物理块另行测量。
- 克隆测试结束、对照 `vm` 启动之前，两个原始镜像的 Disk.img、NVRAM、SEPStorage、config.plist 完整 SHA-256、mtime、inode 均与测试前一致。随后对照 `vm` 的正常运行产生自己的客体写入，不再要求它的磁盘保持启动前哈希。

证据根目录：`.build/validation/apfs-vm-20261008/`（被忽略的本地测试产物，包含日志、截图、哈希及 extent 测量 JSON）。

## 与官方实现的关系

通过 GitHub MCP 核对官方 `Lakr233/vphone-cli`，固定最新调研版本 `3823a553b801097ea4ae278a2aeaec1eed1bcf31`，其 10 月 6 日新增研究说明与 `--new-identity` 语义：

- [官方机器身份与克隆实测](https://github.com/Lakr233/vphone-cli/blob/3823a553b801097ea4ae278a2aeaec1eed1bcf31/Research/Host/machine_identity_and_clone.md)
- [官方 BundleOperations 实现](https://github.com/Lakr233/vphone-cli/blob/3823a553b801097ea4ae278a2aeaec1eed1bcf31/VPhoneKit/VPhoneCoreKit/Bundle/VPhoneBundleOperations.swift)

本地旧 `vm clone` 会删除 NVRAM 等文件，不适合作为本轮真实镜像的克隆入口。本轮直接调用 Apple `clonefile` 克隆已停止的完整目录，在新目录中清空 `machineIdentifier` 与 NAT 配置的 `macAddress`，删除派生 UDID 文件及 socket；保留同一时刻的 Disk.img、nvram.bin、SEPStorage。没有使用普通复制回退，两个 clonefile 调用返回 0，耗时约 50 ms、40 ms。其语义与最新官方新身份克隆相符，但**没有声称本机安装了最新版 CLI 或运行了最新版全部测试**。

APFS 写时复制是 Apple 的文件系统能力；新的 ECID 能启动已有恢复镜像，则依赖 vphone 的研究客体及固件补丁。两者应分开理解。

## 已执行用例

| 用例 | 结果 | 证据 / 限制 |
| --- | --- | --- |
| 当前版本 Core 测试 | 132 项、16 suites 通过 | `core-tests.log`；`swift test --no-parallel --filter VPhoneCoreTests`，64.764 s |
| 上游测试来源核对 | 已核对 | 与官方 1.0.14 / `9c23c8a` 同源；ResourcesTests 存在本地补充。不是新上游全量测试 |
| IPA 签名单元测试 | 1 通过、1 expected failure | `ipa-signing-tests.log`；不能记为 2 项通过 |
| 完整目录克隆 | 通过 | `clone-creation.json`，独立 inode，NVRAM/SEP 初始哈希保持一致 |
| 首启与并发 | 通过 | A/B 同时进入 iOS，控制连接正常，独立 ECID/IP |
| A 身份 | 已观测 | ECID `FBAC69E63D7387C0`；第二次启动保持不变 |
| B 身份 | 已观测 | ECID `B6BE77CC9B96E158`；多次启动保持不变 |
| 原镜像不受克隆写入影响 | 通过 | `original-before.json` 与 `original-after-clone-tests.json`，8 个文件全部匹配 |
| B 写入不出现在 A | 通过 | B 上传 isolation-b.txt 后，A 的 Documents 仍只有原 3 项 |
| A 写入不出现在 B | 通过 | A 上传 isolation-a.txt，B 重启后的 Documents 只有自己的 isolation-b.txt |
| B 重启回读 | 通过 | 1 MiB 文件下载 SHA-256 与原文件一致 |
| A 重启回读 | 通过 | `readback-check.json`；1 MiB 文件 SHA-256 一致，B 文件不存在 |
| B Probe 实际运行 | 通过所测路径 | 启动、Refresh、当前时间/系统信息；PID 549；截图 b-probe*.png |
| A Probe 重新安装 | 通过 | 内置安装器返回 User 安装成功；重新启动 PID 578，当前报告时间；a-probe-after-install.png |
| 菜单退出后冷启动 | 通过所测路径 | A 第四次启动后 Probe PID 396、时间 02:41:39Z；最终 Quit 后 launcher 返回 0，a-boot4-exit.json |
| B Subway Surfers 3.69.2 | **图形失败** | 可进入游戏、计分到 43/44、暂停菜单可用；3D 场景严重花屏；b-subway-play.png |
| 独立 vm 的 wooshort | 通过所测路径 | 启动、关卡页面、连线可见；control-wooshort/puzzle*.png |
| A 的 wooshort 对照 | 通过所测路径 | 同款 App 进入 Garden 1，完成两条连线；2/4、Moves 2、28%；a-puzzle-interaction.png |
| 对照 vm 的 devicectl | **受阻** | Developer Mode 未启用，DDI mount 12040 / 0xe800011c；未修改安全设置，改用既有 vphone UI |

上传测试文件各 1 MiB：

- A SHA-256：`65fbeaa907e406a8a678bcc6cc6306f266d4f59560d3d66e3bccf3fcfede576d`。
- B SHA-256：`c2a8a290c7a17ec9e0a047420d629e5f19e1ef50dc51563a3222c9f4a90be90d`。
- A/B 回读文件：`readback/isolation-a.txt`、`readback/isolation-b.txt`，分别与上传文件完全相同。

## 存储测量方法

使用宿主 `F_LOG2PHYS_EXT`。早期逐个比较相同逻辑偏移；最终遍历每个 Disk.img 的全部非 hole 物理区间，排序合并后计算集合并集与交集，覆盖跨逻辑偏移的共享。所有最终测量均在 VM 停止、lsof 确认无磁盘持有者后进行；`extents-during-boot2.json` 仅为运行时采样。

克隆 B 首启前共享 `26,066,259,968` 字节（24.28 GiB），自身不同物理块为 0。停止后的 B：共享 `25,178,091,520` 字节，不同物理块 `778,313,728` 字节（约 0.725 GiB），其余为 hole。不同物理块是相对于源在相同偏移的增量，不是对整个 APFS 卷所有快照、跨偏移共享的全局引用计数。不能将各目录 `du` 相加当真实总占用，也不能把系统 `df` 的变化全归因于 VM。

最终全区间并集结果（`final-physical-union.json`）：

| 镜像 | Disk.img 逻辑容量 | 相对于源新增的物理块 | 与源共享物理块 |
| --- | --- | --- | --- |
| 源 vm-fresh | 64 GiB | 基础数据 24.28 GiB | — |
| 克隆 A（4 次启动、重装 Probe、游戏交互） | 64 GiB | 835,698,688 B，约 0.778 GiB | 25,110,876,160 B |
| 克隆 B（3 次启动、Probe、Subway） | 64 GiB | 778,313,728 B，约 0.725 GiB | 25,178,091,520 B |
| 独立对照 vm | 64 GiB | 自身数据约 19.91 GiB | 与源、A、B 均为 0 |

源+A+B 的 Disk.img 物理区间并集为 `27,680,272,384` B（25.78 GiB）；两个克隆相对于源合计只增加 `1,614,012,416` B（1.50 GiB）。这不包含文件系统元数据、NVRAM/SEP/其他小文件，也不是删除 VM 时可回收空间的承诺，因为卷快照或其他文件仍可能引用物理块。

## 测试中断及限制

1. 初次临时截图客户端只读 4096 字节就关闭连接，随后宿主退出；与旧 HostControl 未处理断开客户端/SIGPIPE 的代码相符，但未取得明确退出信号，根因保留为假设。后续复用 `scripts.ad_test_trace.socket_command` 读取完整 JSON，不再截断响应。
2. 第二次结束测试时错误地向持有磁盘的 Virtualization XPC 进程发送 SIGINT，造成 `VZErrorDomain Code=1`。这是测试操作引入的异常停止，不计作 VM 自发崩溃或正常关机通过。后续改用 vphone 应用 Quit。不要直接把 lsof 的磁盘持有者当作 host 进程。
3. B 经上述中断仍能第三次启动并完整回读测试文件。单次恢复成功不等于任意断电一致性保证。
   A 第三次启动同样回读成功；随后经菜单 Quit 再启动，重新安装的 Probe 仍正常运行。此处测试的是宿主应用退出/重启，不是客体 iOS 的优雅关机协议。
4. 新 ECID 克隆弹出“Trust This Computer”；新增信任询问尚未收到用户确认，未执行配对。已有 vsock 文件浏览器足以完成目前文件测试。
5. 克隆继承源的 App 数据、keychain 和 SEP 根秘密，**没有验证 IDFA、账户、密钥在安全意义上独立**。写入隔离不等于重新恢复后的全新身份。
6. 独立 vm 没有 Subway Surfers，故其花屏尚无相同 App 对照，不能归因于 APFS 或排除 APFS；需要同版原始环境对照后再定位。当前不是“所有 App 验收通过”。
7. 未覆盖长期压力、所有 App、系统升级、全新恢复、Apple 服务登录、跨 APFS 卷复制、磁盘满故障和完整备份恢复。

## 当前判断

真实 iOS 客体已支持共享未修改块、多个副本启动、客体写入隔离以及中断重启后的测试文件持久化。可以继续用于受控测试环境；完整 App 兼容性验收仍有明确失败和未测项，不能给出无条件通过结论。

结束时 vm、vm-fresh、A、B 全部停止，无磁盘持有者；未删除镜像。源 vm-fresh 的最终四文件全量 SHA-256 再次匹配（seed-final-hashes.json）。测试日志、截图及两个 1 MiB 回读样本保留供复核。

继续测试入口（复用既有签名产物）：

```sh
# 独立对照
./start.sh 1
# 两个新方案实例：分别在终端启动；同一实例不得重复启动
./.build/vphone-cli.app/Contents/MacOS/vphone-cli vm launch cow-test-a-20261008 --library-root "$HOME/.vphone/VMs" --variant exp
./.build/vphone-cli.app/Contents/MacOS/vphone-cli vm launch cow-test-b-20261008 --library-root "$HOME/.vphone/VMs" --variant exp
```

## Subway 归因补验更新

官方 1.0.14 Regular + 官方 force-exc-guard 在独立恢复来源的兼容克隆上同样出现严重 3D 花屏，实际跑酷计分 35 已取证。本地定制及 EXP 不是必要条件，游戏仍为失败；兼容对照本身使用 APFS 克隆，因此尚不能排除克隆因素。见[专项报告](subway_stock_comparison_20261008.md)。
