# 上游 2.13.4 同步与内部发布验收

## 范围

2026-10-26 用户授权同步上游最新代码、保留 Launchpad 业务功能、构建部署并先用测试实例验收，全部通过后发布。现有 5 台实例不改绑，不带入其它未提交改动。

- 同步起点：`920b106`，干净独立 worktree。
- 上游：`Lakr233/vphone-cli` 的 `7f55bebdcbed913541928b9c4b1c1ca79abc0822`，官方版本基线 **2.13.4**，Helper 内部版本 **21**。
- 采用上游 `7d22444d600fcac2a0eb552208168a6810c9d10c` 的设备编号修复及测试，不自行重写占用检查。该提交明确修复 macOS 27 的 `/dev/null` 设备编号转换导致的克隆 SIGTRAP。
- 保留 Launchpad 应用管理、ARM Store、临时内存恢复、FLYWHEEL、Decodo、设备初始化以及四步分发向导；业务仍通过既有 Core 接口编排。
- 上游新版模板创建流程保留，业务初始化衔接在其实际最终实例首次启动之后，不作用于构建模板。
- 保留原有 2.8 pinned Core 的基础管理准入，不以新默认 Core 覆盖已有绑定；新模板功能使用匹配的新 Core。
- 主工作区的 Workstation 代理选择器和 NFC/研究等未提交改动未复制到本工作区，也不纳入本次提交或构建。

## 验收进度

源码合并与构建回归已完成，尚未部署新版或发布，不能把构建成功当作真实实例验收。

- Core Release 完整 Bundle 构建与包校验通过；合并时去掉本地与上游重复的 `com.apple.private.xpc.service-configure` 权限键，权限值不变。
- CoreKit Debug：663 项测试、69 个 suite 通过，包括大于 Int32.max 的实际设备编号和模板占用检查。
- Launchpad Release 以及关闭分发、应用管理、临时内存编译开关的 Debug 构建通过；关闭构建中没有对应业务模型符号。
- Launchpad 16 个独立脚本测试通过；创建初始化测试适配上游模板流水线，验证初始化失败后的独立重试。
- Distribution 25 项、ApplicationManagement 11 项、FLYWHEEL 45 项测试通过；自动锁定与开机解锁脚本测试通过。
- 构建测试日志保留在本机 `/tmp/vphone-upstream-*.log`、`/tmp/vphone-sync-*.log`。首次 Release 测试因未启用测试访问失败，改用 Debug 后通过；首次签名因上述重复键失败，去重后通过。

现有五台的配置与停止状态基线保存于本地 `.build/upstream-sync-evidence/vms-before.json`。部署和验收后再次核对 CPU、内存、网络、身份及 Core/guest/boot-chain 绑定。
