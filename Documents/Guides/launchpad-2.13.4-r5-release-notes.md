# Launchpad 2.13.4 · 内部修订 5

[下载主 APP（DMG，11.0 MiB）](https://github.com/baihua666/vphone-cli/releases/download/launchpad-2.13.4-r5/vphone-launchpad-launchpad-2.13.4-r5.dmg) · [完整安装说明](https://github.com/baihua666/vphone-cli/blob/tb_dev/Documents/Guides/launchpad-internal-user-guide.md)

新 Mac 只需先下载主 APP，Core 与镜像均在 APP 内下载。不需要 Git、Xcode、Homebrew，也无需手工拼接镜像分片。

1. 打开 DMG，将 APP 拖入「应用程序」后启动。内部开发签名、未公证；若 macOS 阻止首次打开，按安装说明在「隐私与安全性」确认来源并允许打开。
2. 在首次使用向导的「1 · 权限设置」中完成开发者工具权限和 Helper 管理员认证，返回重新检查。恢复模式设置仅在 Core 预检明确要求时按说明处理。
3. 「2 · Core 安装」选择本发行版，点击安装匹配 Core，等待下载、SHA-256 校验、安装与主机预检通过。
4. 「3 · 镜像下载」选择「干净 iOS 26.6.2 模板 · 26.6.2-r2」，点击下载。APP 自动下载 11 个分片、合并和校验，支持暂停、继续和失败重试。
5. 「4 · 创建启动」填写新的实例名，创建并启动，等待客体就绪。若已导入但启动失败，点击「重试启动已导入实例」，不重复导入。以后从主列表启动、停止。

向导可从主窗口「版本与镜像」再次打开；每一步独立显示完成状态和错误。系统权限和首次 APP 安装仍需在 macOS 系统界面操作。

## 版本与更新

- 官方基线 2.13.4，上游 `7f55bebdcbed913541928b9c4b1c1ca79abc0822`；构建源码 `130e90761419b43fddc796e198cd781db0b17909`。保留应用管理、ARM Store、临时内存安装、FLYWHEEL、Decodo 和首次向导。
- App 修订 5，Helper 21。App 内检查、下载更新，不依赖 GitHub 匿名 REST API 配额；安装更新时先停止实例、退出 APP 再替换。
- Core `2.13.4-local.666ac4da`，35.2 MiB：[备用 ZIP 下载](https://github.com/baihua666/vphone-cli/releases/download/launchpad-2.13.4-r5/VPhone-2.13.4-local.666ac4da.zip)。安装新 Core 不改绑已有实例。
- 镜像 `clean-ios / 26.6.2-r2`，11,605,975,444 字节，2 CPU / 4 GB / 32 GB / NAT。归档与 r1 字节一致，本修订更新匹配宿主 Core；归档内客体环境和引导链来自 2.8.0，新 Core 启动时会按上游流程同步客体服务及组件，无需手工操作。无账号、业务数据或代理凭据。
- 实体 Apple Silicon Mac、macOS 15+、本机 APFS、管理员权限。导入至少 61 GiB 可用空间，下载缓存另计，建议开始前预留 90 GiB。

## 最终验收（2026-10-26）

- 主 APP 导入、新身份克隆、启动至桌面、磁盘权限失败后恢复重试通过；CoreKit 663 项测试通过。
- 四步向导已显示 **4/4 完成、客体就绪**。无效名称提示及启动中断后的独立重试通过；重试保留同一磁盘，没有重复导入。
- 首次客体同步可能超过向导的 120 秒等待时间；出现超时后可稍候点击「重试启动已导入实例」。测试日志提示新 launchd hook 需重启加载，本次未追加该提示后的冷启动回归。
- App、Core 已完成公开真实下载、大小、SHA-256、签名及 Core seal 验证。镜像采用此前已下载的相同归档，由 APP 完整校验后导入；未重新全量下载 11.6 GB，不将缓存验收表述为全量联网下载通过。
- 原五台实例的绑定和配置核验未变，其它未提交改动未带入。

[完整验收记录及限制](https://github.com/baihua666/vphone-cli/blob/tb_dev/Documents/Guides/launchpad-upstream-2.13.4-validation.md)。本机验证不代替另一台干净 Mac 的首次系统授权。

[镜像发布维护流程](https://github.com/baihua666/vphone-cli/blob/tb_dev/Documents/Guides/launchpad-image-release.md)。镜像更新创建新实例，不覆盖已有磁盘。

下载请使用本页顶部 DMG 和上面明确标注 `2.13.4-local.666ac4da` 的 Core ZIP，或交由 APP 分发目录自动下载。GitHub Actions 追加的 `VPhone-launchpad-2.13.4-r5.zip` 与 `vphone-launchpad-launchpad-2.13.4-r5.zip` 不属于本次验收的内部安装包。

本次仅补充现有 r5 的最终验收及说明，不新增版本、不替换附件。
