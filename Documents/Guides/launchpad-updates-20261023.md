# Launchpad 近期更新（2026-10-21～23）

本次整理的是 `tb_dev` 的本地定制功能，不是新的官方版本发布。实际合入的官方基线仍为
`dfcfae9c608c432a9a63f846d5cda8272fde0b82` / 2.8.0，本地产物保留内容哈希并显示 test 标签。
其它 Mac 请从 [获取与部署指南](launchpad-mac-setup.md) 开始，不能只拉代码后继续运行旧 app。

| 更新 | 使用入口与行为 | 依赖与验证边界 |
| --- | --- | --- |
| 本地应用库与 ARM Store | 主窗口「应用管理」；扫描/导入 IPA、在线搜索、下载、安装到明确选择的实例；请求中可切换本地页 | 仅 Launchpad/独立业务包；真实 Instagram 下载、原 Core 安装及启动已验收；账号与会话每机配置 |
| 已安装版本识别 | 自动读取目标 guest `apps.list`；按 Bundle ID、版本和构建显示安装、升级、最新或客体更高 | 不把读取失败当未安装；“最新”仅相对本地包；TikTok 47.4.0 / 474032 真实 UI 已核对 |
| 临时 8 GB 安装重试 | 安装失败后用户确认才停机增配；一次安装后恢复实际原内存并启动，异常保留恢复记录 | 不改 Core；TikTok 实测 8 GB 安装后恢复 4 GB 并启动；自动恢复分支有隔离测试，不承诺断电时即时恢复 |
| Decodo 地区与账号 | 账号设置、授权续期、国家/州/城市搜索、ISP/住宅配置与 IP 检测 | 本机私有配置；网站授权和代理凭据分开；首次授权/验证码仍需正常处理 |
| 每实例原生 HTTPS 代理 | 原生与 Clash 表单；复用地区列表、应用/换 IP、持久化、共享 Core 独立出口 | 可选 Core 能力，按实际探测启用；IPv4 TCP/UDP DNS，非完整 UDP/QUIC/IPv6；两测试 guest 分流与独立换 IP 已实测 |
| FLYWHEEL 本地设备管理 | 独立窗口；编号、地区、备注、关联、启停与平台定位 | 独立 SwiftData，改名/克隆/删除/同名替换及重开回归；没有后端同步；删业务记录不删 VM |
| FLYWHEEL 网络与业务网页 | 登记前准备/检查网络，guest Safari 打开自定义 URL，自动 IP 与可编辑参数，聚焦目标机 | 复用实例绑定及代理；网页打开已实测，未验证远端登录/业务提交 |
| 创建后设备初始化 | Never、respring、解锁、至少 120 秒无输入观察，通过后启用开机解锁；失败独立重试 | 策略在 Launchpad；guest 写设置能力是前期独立 Core 改动，旧 guest 明确报缺能力；不自动升级已有机 |
| 构建身份与兼容 | 本地/CI 包展示 test，保留原版本、内容哈希、receipt 与绑定 | 基础最低版本仍为 2.8.0；不因可选业务能力阻止旧实例基本操作 |

## 维护边界

新业务优先在 Launchpad 或 `Integrations/` 中复用已有接口；修改 CLI/Core/guest 前必须说明原因、最小范围及兼容影响，并得到用户确认。
应用管理的早期 Core 定制已撤回，上传、安装、列表与临时内存配置均使用现有接口。
本次收录的原生代理/初始化 Core 代码属于此前独立功能，不意味着其它 Mac 必须随此次 Launchpad 更新部署它们。

应用管理和临时内存恢复分别受 `VPHONE_CUSTOM_APPLICATION_MANAGEMENT`、
`VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY` 控制，开关在 Launchpad xcconfig 集中维护。
此前的代理、FLYWHEEL、设备初始化尚未逐项完成具名宏隔离；不能把新增开发规范描述为全部功能已可编译关闭。
NFC/Wallet/SE 研究及无 RF 原型不属于本次可用功能交付，不纳入本次提交。

## 详细说明

- [应用管理、失败处理与恢复](launchpad-applications.md)
- [Decodo 配置与授权](launchpad-decodo.md)、[原生代理及协议限制](native-decodo-proxy.md)
- [FLYWHEEL 数据与生命周期](flywheel-integration.md)
- [设备初始化与 guest 能力](launchpad-device-initialization.md)
- [开发、同步与版本规则](monorepo-development.md)

历史现场记录包含当时的实例名、错误命名产物和本机证据路径，仅用于追溯；不是新 Mac 的配置模板。
本机真实验收不等于已在另一台 Mac 从零完成验收，新机器须执行部署指南中的本机检查。

## 本次提交前验证（2026-10-24）

环境：Apple Silicon、Xcode 27.0 / 27A266a。验证未重启现有 VM，也未安装新 Core。

- 应用管理 11 项、FLYWHEEL 45 项、WSCore 120 项通过；需要真实账号/专用 VM 的 live 测试默认未启用。
- 设备初始化策略、创建流水线、临时内存恢复、FLYWHEEL 实际宿主适配器、guest Auto-Lock/迟到锁屏、Bundle 名称和源码同步脚本回归通过；ARM 下载参数/统一安装入口自测通过。
- Launchpad 与完整 Core 构建通过。另将暂存区全部源码导出到独立目录，使用新的 DerivedData 构建 Launchpad，通过；未复制本机签名配置、凭据、未提交源码或业务数据，仅复用已下载的 SwiftPM 依赖缓存。这证明源码闭包可构建，不代替其它 Mac 的签名、Host Setup 或真实 VM 验收。
- CoreKit 全量 415 项首次有两项失败：`BundleActivityTests` 停机判断与 `BundleOperationsTests` 新身份克隆；错误均为临时文件被额外测试进程持有。随后单独重跑这两个 suite，27 项通过。存在并发环境影响的证据，根因未完全确认；不能记为全量测试全部通过。新增代理相关 suite 在全量执行中通过，本轮不改无关生命周期实现。
- 暂存区差异格式、凭据特征/大文件与新增文档相对链接检查通过；修正新增安装 Skill 文件的 Git 路径大小写，避免大小写敏感文件系统缺文件。
