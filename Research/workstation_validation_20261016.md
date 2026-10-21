# vphone-ws + 现有完整 CLI 验证（2026-10-16）

## 入口与边界

运行仓库根目录 `./workstation.command`，或在 Finder 中双击该文件。它打开相邻仓库 `../vphone-ws/.build/vphone-ws.app`，显式传入既有完整 CLI 和专用实例库；不执行构建、不下载宿主、不迁移固件。

来源：[zqxwce/vphone-ws](https://github.com/zqxwce/vphone-ws)，本地基线 `f2a982f3ebe81cf1e9415a87c552ece1a815b036`，本次通过 GitHub MCP 核对官方 README，并读取该基线源码。当前修改位于相邻仓库，未提交/推送。

汇总库 `~/.vphone/workstation-library` 只包含两个同名目录链接，不复制磁盘：

| 实例 | 原目录 | 固件 / 完整宿主 |
| --- | --- | --- |
| stock-regular-guard-20261008 | ~/.vphone/VMs/stock-regular-guard-20261008 | Regular；~/.vphone/runtimes/legacy-clipboard-20261012/vphone-cli.app |
| vm-fresh | 本仓库 vm-fresh | EXP；本仓库 .build/vphone-cli.app |

每台原目录的 `.vphone-ws.json` 记录 `variant` 与 `executablePath`。全局 CLI 仅供实例查询、配置与归档；启动按实例选择现有宿主。`start.sh`、现有固件、IPA 安装器和签名资源未修改。当前业务分支的 EXP 制作入口已在此前迁移时禁用，本次不恢复旧流水线、不把新版 JB 当作 EXP；历史制作流程仍以原有保留基线为准。

## 已实测

- 实例发现：GUI 同时列出两台，版本均为 26.1/23B85，变体分别 regular / experimental。
- 同时运行：两台均通过 GUI 启动；进程参数分别为原目录 config.plist、原宿主和 `--variant regular/exp`，GUI 均显示 Running，guest 窗口均 connected。
- 窗口切换：分别点击 Show screen，得到对应 ECID 后缀 `DE8B035FFDE50E52` / `2AF5A35422349AA0` 的窗口，官方窗口保留中文粘贴宿主的 Edit 菜单。
- 独立停止：GUI 停止 EXP 后，官方宿主持续运行且 EXP 磁盘释放；反向停止官方后，EXP 持续运行且官方磁盘释放。随后分别从 GUI 再次启动。
- 管理器退出后两台继续运行，重开管理器可以重新发现；不以关闭管理器代替 VM 停机。
- 测试：`swift test` 63 项通过，`scripts/bundle.sh` 完成 release app 构建，两个仓库 `git diff --check` 通过。

## 必要的小改动

1. 沿用 VariantStore 的现有 sidecar，增加可选宿主路径并在启动时传 variant；修改 variant 时保留宿主路径。
2. 启动和 Show screen 解析汇总库目录链接，使用真实 config 路径，兼容原 start.sh 启动的实例。
3. 旧 1.0.14 `vm stop` 按 lsof 磁盘持有者发信号，可能命中 Virtualization XPC。本次 GUI 停止改为匹配该实例 `--config` 的 AppKit 宿主、发 SIGINT 并等待磁盘释放，超时提示而不强杀。
4. 导出参数解析链接到真实实例目录，避免旧 tar 仅归档目录链接；运行中禁用 Export。实例详情显示真实目录。

未加入中文翻译、批量操作或新建镜像流程；本次仅验证以上生命周期功能。Clone/Rename/Delete 等原有功能没有做真实数据验收，尤其不要用旧 clone 行为建立独立身份实例。

## 导出限制

当前卷约剩 17 GiB，两个磁盘已分配约 18/24 GiB，且 guest 数据可能难以压缩。为避免重演磁盘耗尽，没有生成完整归档。已验证运行中 Export 禁用、停止后可用，以及目录链接解析的回归测试；这些不等于完整归档成功。

完整停机导出仍待至少 30 GiB 空闲的目标目录。之后从 GUI 停止目标实例并确认 Stopped，选择 Export；完成后检查压缩完整性和 tar 目录中包含实际 Disk.img/config.plist/NVRAM/SEPStorage，不应只有链接。无需复制 VM 或新建实例。当前没有遗留大体积导出或备份文件。

补充：HostReadiness 原来忽略 `VPHONE_CLI_PATH`，在非 PATH 宿主下误报未安装。现传入实际解析出的 CLI 路径，并新增回归测试；不改 AMFI/SIP/Research Guests 检查或系统设置。
