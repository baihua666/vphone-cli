# 原生 Decodo 出口：检测后保存

Launchpad 的代理出口页使用现有实例的 library 和 pinned Core，不升级 Core 或 guest。

1. 选择 ISP 地区或住宅 ZIP，点击「检测所选地区出口」。只通过指定物理网卡访问代理，
   不修改 VM/Clash；成功后显示候选公网 IP，并保留同一网关、端口和认证参数。
2. 实例未运行时，可点击「启动此虚拟机」。读取已保存地区不要求实例先运行。
3. 点击「保存并应用已检测出口」。复检同一候选入口，IP 不一致或检测失败则不应用；
   地区、账号、网卡、实例绑定改变，或端口已被其它实例占用，须重新检测。
4. 通过既有 CLI 保存私有配置并应用到该实例，然后由 guest 实测出口。保存成功与
   guest 验证成功分开报告；guest 检测失败保留已应用配置，可独立重试当前 IP 检测。
5. 关闭并重新打开页面，从该实例既有 native-proxy-reference.json 读回地区和入口。
   旧的检测候选不跨窗口持久化，也不把之前的公网 IP 当作当前实测值。

HTTP 407 仅说明代理拒绝认证，可能涉及账号、套餐或流量；不笼统归因于物理网卡。
DNS、代理检测和 guest 检测分阶段报告；只输出状态码，不显示 provider 响应正文、
curl stderr 或认证参数。没有宿主直连公网兜底，也不关闭 TLS 验证。

## 开关与边界

- 宏：`VPHONE_CUSTOM_NATIVE_PROXY_WORKFLOW`，集中定义于 Workstation `Package.swift`，
  默认启用。`VPHONE_DISABLE_NATIVE_PROXY_WORKFLOW=1` 可构建关闭态。
- 关闭后不创建候选或执行保存候选操作，UI 回到原有检测/轮换入口；错误状态解析仍保留。
- 新状态与校验在 `Proxy/NativeDecodoCandidate.swift`，编排沿用 `NativeDecodoController`；
  UI 只负责组装。只触及既有业务目录和 SwiftPM 设置，不修改公共 Core、CLI、VM 或 helper。
- 删除流程时删除候选文件、controller 的候选状态及窄分支、UI 条件组装和 Package 宏定义。
  不删除现有代理配置；关闭宏不会撤销已经应用的代理。
- 既有原生代理功能本身尚未整体纳入宏隔离；本开关仅覆盖本次检测后保存流程。

测试：`scripts/dev.sh test gui`；关闭态用上述环境变量运行同一命令。覆盖检测不写入、
保存同一端口、复检失败不写入、输入变化失效、保存后地区读回、错误正文不泄露及关闭态无副作用。
真实验收须在可用的供应商账号上完成地区选择、检测、保存、guest IP 一致性与重开读回。

官方参数依据：[ISP 认证](https://help.decodo.com/docs/isp-pay-per-gb-proxy-user-pass-requests)、
[ISP 会话和端口](https://help.decodo.com/docs/isp-pay-per-gb-proxy-session-types)。

2026-10-27：原生 HTTPS 页面仅提供本方案的检测、保存和验证，不提供 Clash 回退。
两套方案使用独立的地区选择状态；顶部选项仅浏览对应配置，实际启用操作位于各自页面。
原生检测失败保留本方案状态并提示重试，不引导或自动切换其他方案。

## 内置代理认证（2026-10-27）

用户明确要求源码纳入真实代理凭据，并在确认仓库公开后再次批准实验分发。`DecodoEmbeddedCredentials.swift`
作为版本化源码编译进应用，原生 HTTPS 与 FLYWHEEL 原生准备流程不再展示凭据
文件字段，也不读取旧路径或环境变量指定文件。安装包复制到其它 Mac 后使用
同一内置账号；网卡、实例目录、Core 绑定仍按目标 Mac 的配置解析。
这仅替代代理认证来源，不替代 Decodo 官网账号登录及地区目录同步。

宏 `VPHONE_CUSTOM_EMBEDDED_DECODO_CREDENTIALS` 在 Workstation/Package.swift
集中定义，默认启用。`VPHONE_DISABLE_EMBEDDED_DECODO_CREDENTIALS=1` 构建关闭态，
恢复原凭据文件读取与对应表单；关闭不会删除或改变已有实例代理配置。
删除此功能时一并移除内置源码、宏设置、凭据读取分支和 UI 条件组装。
测试验证缺失文件、另一 Mac 路径、完整候选保存，以及关闭态缺文件真实失败。
修改内置账号需重新构建安装包。本文件只记录设计，不重复账号值。

## 当前 IP 的单次测量发布（2026-10-27）

原生方案的检测/保存已包含 guest 测量。完成后直接把该结果发布到共享当前 IP
显示，不再串行执行一次 FLYWHEEL 网络测量。原有重复调用会出现“检测完成”而
IP 仍空白，或因第二次失败丢失第一次成功结果。该修复沿用原生流程编译开关。
检测中显示明确进度，失败原因直接显示在 IP 位置，不把失败伪装成尚未检测。
业务打开网页时仍按原契约自行验收，不复用旧 IP 冒充本次网络验证。
