# TikTok 安装连接中断（2026-10-23）

目标 `1-20261023`，原 Core `2.8.0-local.199abaf3`，4 GB RAM。
本地 TikTok 47.4.0 包 503055557 bytes，ZIP 完整性检查通过。客体上传文件同样大小，
路径 `/var/mobile/Documents/vphone-installs/4C9C0EF8-A8CA-4A91-9637-86A50395D6AC.ipa`。
apps.list 未找到 `com.zhiliaoapp.musically`。核对进程及客体列表后针对已上传包进行一次诊断调用，
原始宿主响应为 `ok:false`，错误“客户机代理未连接。请等待连接后重试。”，随后 ping 恢复正常。
没有循环重试，也没有删除该临时包。

客体 JetsamEvent-2026-10-23-091113.ips（客体时间与宿主墙钟不同）中：
- largestProcess=vphoned；pageSize=16384。
- vphoned PID 104，rpages=57463，约 898 MiB。
- vphoned PID 63 被标记 reason=vm-compressor-space-shortage，多个系统进程也被回收。
- 当前 vphoned 已变为 PID 511/512，安装连接断开与服务重启吻合。

证据保存在 `.build/validation/app-install-failure-20261023/`。
不能将这个错误归因于单纯超时，也不能声称 TikTok 安装完成。
早期建议调为 8 GB 的方案已暂停：用户最新要求保持 4 GB，先查明内存开销并评估纯 Launchpad 优化；没有执行内存修改。

Launchpad 修正：保留 `VPhoneLaunchpadError` 的 detail 后再传入独立业务模块；
错误原因放在提示开头，状态区可滚动读取完整信息，不再只显示五行。
明确区分“失败或未确认”，只有条件说明“如发生超时或连接中断”，不暗示所有异常都是超时。
测试增加客体拒绝原因不丢失的断言。修复未改变实际安装器或引入自动重试。

## 保持 4 GB 的内存调查

本轮不重试客体安装、不停止应用、不重启或部署。使用安装技能的只读取证流程，
在宿主临时副本上调用原绑定 Core 的既有 `sign --merge`，未修改 Core 源码或安装包原件。

### 数据与定位

- IPA 为 503055557 bytes（约 480 MiB），解包总量 1020145320 bytes（约 973 MiB），3690 个条目。
- `Payload/TikTok.app/Frameworks/MusicallyCore.framework/MusicallyCore` 为 881054288 bytes（约 840 MiB），
  单架构 arm64，不能靠移除多余架构明显缩小。
- 用 `/usr/bin/time -l` 执行原 `2.8.0-local.199abaf3` 的 `vphone-cli sign <临时副本> --merge`：
  成功，2.06 秒，maximum resident set size 1692041216 bytes（约 1.58 GiB），
  peak memory footprint 1685325624 bytes。这是宿主单文件签名实验，不是客体完整安装峰值，
  两端分配器、系统压力及 entitlements 路径不同，不能据此给出客体精确需求。
- `VPhoneMachOImage.init` 用 `file.subdata(in: range)` 复制完整 slice；`signed` 构造完整 `code`，
  最后拼接签名生成输出；`VPhoneSigner.sign(fileAt:)` 同时涉及映射输入及签名结果。
  Apple 文档明确 `subdata(in:)` 返回新副本：
  https://developer.apple.com/documentation/foundation/data/subdata(in:)
- 结合前轮 Jetsam，签名大二进制的整块缓冲是主要嫌疑；没有采集客体分配调用栈，
  不能声称已精确证明发生回收时正在执行哪一行。
- Launchpad 上传使用 `URLSession.upload(fromFile:)`；guest `GuestFileUpload` 分块写盘并通过
  autoRead 反压控制待写队列；Icli 解包使用 65536 bytes 缓冲。流程等待上传完成再提交安装，
  当前 UI 也串行安装。分块上传、并行度改成 1 已是现状，不能算新增优化。
- 本轮 `processes.list` 中六个第三方主进程 footprint 合计 3687936 bytes（约 3.5 MiB）。
  仅为当前快照，不代表失败时或全部扩展进程总量；不能凭 apps.list 的 running 就认定
  清后台能够释放数 GB。没有终止这些进程。

### Launchpad 可行性边界

1. 现有 `apps.install` 无条件调用 guest signer，没有跳过重签或提交宿主预签目录参数；
   宿主预签后仍用此 API 会重复签名，不能解决主要峰值。
2. `apps.register` 是已有目录的注册接口，带所有权限制；不是完整的用户应用容器安装接口。
   简单上传目录再注册会改变容器、升级回滚和卸载语义。不得为了绕过重签伪造容器标记或
   复制底层安装器到 Launchpad。
3. 原 Core 包不含 ideviceinstaller。不能把开发机 Homebrew 工具偷偷变成产品运行依赖，
   或把另一条未经验收的安装链当现有流程优化。
4. 纯 Launchpad 可增加大包/大二进制预检、准确阶段提示、内存压力提示及显式选择后关闭
   用户应用的可选流程；这些提升可解释性或降低背景负载，不消除单次签名的大块内存。
   本轮没有引入未经证实能改善 TikTok 安装的产品改动，也没有自动终止应用。
5. 若未来允许改底层，可比较“签名器有界内存处理”和“安全接收宿主预签包的通用接口”，
   但两者都超出本轮授权，须另说明最小接口、签名/容器校验及兼容影响后获用户确认。

证据：`.build/validation/tiktok-memory-20261023/sign.time`、`processes.json`、`pressure.json`。
临时签名副本仅用于实验；不上传、不作为安装来源。结论是目前没有验证过的纯 Launchpad
流程调整能解决本包在 4 GB 下的主要峰值，不将延长超时或清理磁盘误报为内存修复。

## 临时 8 GB 安装、恢复 4 GB 验收（用户随后授权）

用户要求先验证临时增配方案。本轮仅调整 `1-20261023` 的 memory，仍绑定
`2.8.0-local.199abaf3`，没有更新 Core、guest 或 Launchpad。

1. 备份 config.plist 与 launchpad.json，Launchpad 正常停机后，通过其 `exec --bundle`
   调用既有 `vm config --memory 8192`，再从 Launchpad 启动并等待 guest ready。
2. 客体 `memory.pressure` 读回 hw_memsize=8565800960。TikTok 尚未安装。
3. 临时验收客户端直接编译现有 ApplicationManagement workflow、connection 与既有 socket
   适配代码，对原下载的 TikTok 47.4.0 执行上传、apps.install、apps.list；安装成功并读回
   bundle ID `com.zhiliaoapp.musically`，build 474032。
4. 正常停机，通过相同既有命令恢复 4096 MB 后重启。config.plist 与 launchpad.json
   均与之前备份 `cmp` 一致；其它实例保持停止。
5. 4 GB 下解锁并 apps.launch 成功，PID 350、frontmost_verified=true。每隔 5 秒采样一次，
   六次都为同一 PID，约 30 秒观察后 apps.foreground 仍验证为 TikTok。
   六次 footprint 约 118–193 MiB，resident 约 371–484 MiB，属于采样值而非完整峰值。
6. 截图确认显示正常 TikTok 登录页。未登录、未测试视频播放或长时间使用。

结论：本机本包的“8 GB 安装 → 4 GB 启动”路径真实通过。当前实例保持 4 GB 运行，
TikTok 留在前台；未将这个流程自动接入产品。证据目录
`.build/validation/tiktok-temporary-memory-20261023/`，含安装日志、配置备份、应用信息、
六次运行采样、前台读回与 `tiktok-4gb.jpg`。
