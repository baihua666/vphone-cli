# 清理与镜像共享验证（2026-10-10）

## 已执行清理

用户授权后，检查无运行中的 VM/构建及候选目录无文件持有者，删除：

- `.build/validation/pre-excguard-backup`
- `.build/validation/excguard-stage`
- `ipsws` 与 `~/.vphone/ipsws`
- `.build/out`、`.build/arm64-apple-macosx`、`.build/upstream-sync-tests`
- `.venv` 与 `~/.vphone/venv`

两份工作镜像及其完整状态文件、`.build/vphone-cli.app`、`~/.vphone/runtimes/upstream-1.0.14/vphone-cli.app`、历史截图/日志/哈希、Git 全部保留。旧回滚整机备份已依本轮授权删除。

`df -k` 可用空间由 49544348 KiB 到 94857220 KiB，增加 45312872 KiB（43.21 GiB）；这是该时段卷净变化，其他进程也可能影响。清理后官方运行包签名、start.sh 语法及 Git 连通性检查通过。

## 官方共享实现

GitHub MCP 获取官方 2.9.2 发布信息及 `Research/Host/disk_rebase.md`、`VPhoneDiskRebase.swift`、命令源码。下载 VPhone-2.9.2.zip SHA-256 为 `0af6dfa9706a80b4103a773c1b7fa809b036fb79dd4cd5bf64f2e680710bc3db`，匹配发布 digest，完整 bundle 签名通过。

新命令对旧 VM 配置报 schema version 2 要求，未修改旧配置，未重刷 VM。采用临时新版 manifest 包装磁盘文件，重用官方未修改发布 CLI 的存储算法：临时 target/base 的 Disk.img 分别 hardlink 到停止的定制/官方磁盘，故不产生整盘副本；临时配置仅用于离线存储研究，绝不启动。官方活动检查按 inode 检查文件持有者，所以读取原路径的校验进程亦被检测并拒绝并发。

算法在临时 target 内从 base clonefile 生成新文件，写入差异、逐字节验证、原子替换临时链接。原定制磁盘在正式回填前仍原样保留。正式回填需再次确认停机、完整磁盘哈希一致及身份文件不变。完成后删除临时包装及硬链接，不留下第三份工作镜像。VM 启动仍使用既有 1.0.14，2.9.2 不安装 guest 组件。

证据目录：`.build/validation/storage-cleanup-20261010/`。本轮未改产品源码，未把新固件流水线部署到旧 VM。

状态：离线共享重排、全盘哈希与双实例启动已完成；具体运行范围见下文。

## 存储结果

官方 dry-run：12.31 GB newly shared，0.07 GB already shared（包含洞，不代表此前两盘确实共享），13.37 GB 差异独立写入，0.97 GB 转稀疏洞。真实重排 91 秒，官方逐字节校验通过，报告与 dry-run 一致。

定制盘 64 GiB 完整 SHA-256 操作前后均为 `791f27ae35941d67b8a0a7a335bd51e21dbacb7fab4028bd52c3cf0eac820a42`。官方原盘操作前后均为 `b004732a3059e3284bce5535217fbfb8f9066660cd868b17e8cbd62e8258f9e0`。两台 config、NVRAM、SEPStorage、两份启动 ROM 共 10 个文件在启动前全部通过原哈希检查。

重排后独立 F_LOG2PHYS_EXT 扫描两盘全区间并集 32296443904 字节（30.08 GiB），0 错误；stat 分配字节相加与并集差约 12.38 GB。目录只剩两份实际镜像，临时包装及硬链接已全部移除，两个 Disk.img 链接数均回到 1。官方使用完整镜像文件，定制版也有完整逻辑镜像文件，底层相同块由 APFS 引用计数共享；任一侧后续写入会 CoW。

正式替换后 `df -k` 可用空间从 93180556 增至 105567124 KiB，净增约 11.81 GiB（该时段宿主其他写入也影响 df）。包括清理步骤在内，暂时可用空间由约 47.2 GiB 增至约 100.7 GiB；实际启动后会有缓存与 CoW 增长。

双机运行后最终扫描仓库与 `~/.vphone`：大文件物理区间并集 37086143545 字节，加小文件分配 270069760 字节，合计约 34.79 GiB，扫描 0 错误（`total-physical-final.txt`）。小文件按分配块计、运行中存在写入，因此为近似占用；不含 APFS 元数据/系统快照。宿主整个卷剩余约 96 GiB，不应将其他宿主进程产生的差额全部归于 vphone。

## 运行验证

两台 VM 使用原 1.0.14 app 并发冷启动、vphoned connected。定制 ECID `2AF5A35422349AA0`，IP 192.168.64.59；官方 ECID `DE8B035FFDE50E52`，IP 192.168.64.60。均通过既有 host control 的 power 唤醒、等待 2 秒后底部上滑解锁，进入 Settings 并正常操作。原生窗口拖动未成功，不能把失败手势误判为磁盘损坏。

用户要求所有镜像不得自动锁屏：两台原设置均为 1 minute，现均改成 Never，已保存 `custom-autolock-never.png`、`official-autolock-never.png`。该偏好纳入 branch_workflow 和开发 skill 的镜像基础验收要求。无密码变更，无新增固件补丁。

设置入口经 MCP 核对 [Apple 使用手册](https://support.apple.com/zh-cn/guide/iphone/iph7117338a8/ios)。测试时曾在两台交替发送唤醒/按键后观察到黑屏，因此重新唤醒后停止所有输入，单独计时验证，不能仅凭 socket 截图判断亮屏（该接口可能返回熄屏前缓存画面）。

18:12:35 起不再发送任何触摸/按键，18:14:40 用原生窗口截图检查：定制 VM 仍在亮屏主屏幕，官方 VM 仍在亮屏 Display & Brightness，Auto-Lock 显示 Never。无输入超过 2 分钟，均未自动锁屏；补充截图 `custom-idle-over-2min.png`、`official-idle-over-2min.png`。返回上一级后设置仍为 Never；本轮未再重启验证该偏好持久化，也未实现开机自动解锁。两台 VM 留在运行状态。

本轮确认存储重排字节不变、身份状态文件不变、两实例并发启动及 Settings 操作，不把第三方 App 全功能或 Subway 图形判为通过。Subway 官方对照也花屏的既有结论不变，根因尚未定位。
