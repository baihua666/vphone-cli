# Workstation 网络状态与出口检测

在实例详情中查看“网络状态”。“刷新状态”读取当前 VM 的网卡及 guest 地址，不向公网发起检测；“检测 guest 出口 IP”让虚拟 iPhone 内的 vphoned 向 `https://api.ipify.org?format=json` 发起 HTTPS 请求。

两者都不修改 VM 网络配置或 Clash。停止的实例禁用检测。结果按实例隔离，切换实例、停止或刷新后清除旧结果；公网 IP 显示检测时间，不能视作持续监测。

## 字段含义

- 已保存模式：manifest 中的下次启动设置。
- 运行中模式、链路：当前 VM 网卡状态。
- Guest 地址分配设置：例如 DHCP，不是测量到的地址。
- Guest 实际 IPv4：guest `device.network` 返回的 en0 IPv4。
- 公网 IPv4：guest 发起 HTTPS 后服务观察到的出口；不表示静态、独享 IP，也不证明所有 App、DNS 或 UDP 的出口。

实例设置页按绑定 CLI 的帮助检测 tunnel 支持；已有 tunnel 设置即使旧界面不认识也不应悄悄改为 NAT。修改网络模式仍要求停机并在下次启动生效。

## 命令与兼容性

```sh
vphone-cli vm network NAME --library-root /path/to/library --json
vphone-cli vm network NAME --library-root /path/to/library --json --probe
```

`--probe` 不能与 `--link` 一起使用。JSON 继续保留原有网卡字段，新增可选的 `guest_addresses`、`egress` 和 `egress_error`。网卡查询成功而出口失败时仍返回网卡 JSON（退出 0），调用方必须检查 `egress_error`，不能只看退出码；实例未运行/控制连接失败时退出非零。

成功的 `egress` 包含 `ip`、`origin: guest`、`source` 和 UTC `checked_at`。guest API 增加 `network.egress` 方法及 `network_egress` capability。检测固定使用 HTTPS 和系统证书校验，15 秒资源超时；不接受任意 URL，不通过宿主请求兜底。

旧 CLI 没有 `--probe` 时，Workstation 保留网卡查询并提示更新完整运行包；新 CLI 配旧 guest 时显示 guest 的未知方法/未连接错误。此扩展不改变 Launchpad 已依赖的既有参数和字段。

## 实例上下文

`VMCommandContext` 统一解析真实机器目录、真实名称、library root、sidecar 绑定的 CLI 和旧版 variant。启动、info、config、network、clone、rename、delete、export 使用该上下文；列表由默认 CLI 发现，再由绑定 CLI 读取对应实例详情。

新版分离式运行包（存在可执行 `vphone-vm`）通过绑定 CLI 停止，并等待磁盘释放；旧版保留按真实 config 找 AppKit 宿主的兼容停止路径。窗口激活属于 macOS UI，继续按真实 config 定位窗口。

损坏的 sidecar 报错，不静默回退。链接实例的查询、启动、停止、配置和导出解析到真实目录；clone/rename/delete 拒绝对库别名操作并提示真实库，避免创建对象不可见或留下悬空链接。新建/导入属于库级操作，仍用默认 CLI；旧创建向导的 2.x 迁移不在本次范围。

## 开发验证

```sh
scripts/dev.sh test gui
VPhoneDaemon/Tests/run-network-egress-tests.sh
scripts/dev.sh build cli
scripts/dev.sh build gui
```

GUI 测试覆盖绑定宿主与链接目录、损坏绑定、旧 CLI、guest 错误及拒绝 host 来源结果。guest 测试编译实际探测代码并验证返回地址解析。真实验收还需两台 VM 同时运行、分别检测、单独停止和切换实例，确认结果隔离及既有分流配置不变。

## 每台实例选择 Clash 出口

实例详情的“代理出口 · Clash Verge”读取当前订阅的节点；选择节点后点击“应用出口并检测”。它保存该实例的前置 `PROCESS-PATH` 规则，更新当前生成配置，通过 Mihomo 本地 Unix 控制接口重载，并核对完整规则序列只有这一条目标改变。随后只断开该运行程序的旧连接，自动调用绑定 CLI 的 guest 出口检测。检测失败会单独提示，不把规则生效当作公网检测成功。

当前适配 Clash Verge Rev 的订阅规则格式（2.5.8）和 Mihomo HTTP API（1.19.32）：

- VM 必须处于 tunnel 模式，每台实例绑定独立路径的 `vphone-vm`；同一机器库共用运行程序的实例拒绝切换。
- Clash 必须已有该实例唯一的前置规则，且持久化、生成配置、生效规则一致；需要 Rule 模式、TUN 和 strict 进程识别。不自动改全局设置、不新建监听端口或绕过原有 DIRECT 例外。
- 节点来自实际 Mihomo `/proxies`，只显示具体节点和 DIRECT，不修改共享策略组选择。订阅删除节点后需重新选择可用节点。
- 保存到当前订阅所引用的 rules 文件，保留其它规则、注释与顺序。支持普通单行和引号字符串；无法精确定位的 YAML 样式拒绝修改，不全量序列化配置。
- 优先连接本用户的 Clash Verge service socket，兼容普通运行方式的配置 socket。控制密钥只在内存和系统 curl 的 stdin 中传递，不写入实例、命令行参数或日志。
- 两台实例的应用操作共享互斥状态。写入前后检查配置是否变化；失败只尝试恢复仍与本次写入一致的文件，外部修改不覆盖。发生冲突需刷新并在 Clash Verge 重新激活当前订阅。

持久化归属当前订阅：在 Clash Verge 重新激活该订阅或由 Verge 重启内核后仍从该前置规则生成配置；切换到另一个订阅不会擅自把规则复制过去。直接绕过 Verge 启动系统服务的旧 staging 配置不属于此入口。公网检测只验证一次 guest HTTPS 请求，不承诺静态 IP、所有应用或 UDP/DNS 出口。

## 手动添加已购代理 IP

首期复用上面的出口选择和应用流程，无需在 guest 内安装 VPN：

1. 向供应商购买通用 HTTP(S) 或 SOCKS5 代理，取得服务器、端口、用户名和密码。先确认静态/动态、独享性与流量条款；[供应商调研与五机预算](../../Research/Host/ip_pool_strategy_20261021.md)提供候选。
2. 在实例详情的“代理出口 · Clash Verge”点击“添加已购代理 IP”。填写一个可辨认的名称，以及供应商提供的连接参数。服务器只填 IP 或域名，端口单独填写；白名单认证时用户名、密码都留空。
3. 只有供应商明确提供加密代理入口时才启用 TLS。HTTP CONNECT 能访问 HTTPS 网站，不等于代理入口本身支持 TLS。SOCKS5 的 UDP 也需供应商实际支持；未勾选不会宣称覆盖 UDP。
4. 点击“保存到出口列表”，新记录显示为 `IP · 名称`。保存只加载节点，**不会立即改变实例出口**。随后点击“应用出口并检测”，沿既有流程切换并读取 guest 公网 IP。

节点保存在当前订阅绑定的 `type: proxies` 扩展文件 `prepend` 中，运行配置同时更新并通过 Mihomo 重载核对；只插入节点，保留已有节点、规则、注释与其它配置。失败只尝试回滚仍等于本次写入的文件；冲突时刷新核对，不覆盖外部修改。并发添加和切换共用互斥状态。同名节点拒绝添加，不能借添加覆盖原节点。

Clash Verge 重新生成订阅时会把扩展节点加入第一个手动策略组。为保留当前选择，添加前通过内核接口将各手动策略组的当前值存入选择缓存，重载后再次核对；不会主动选择新节点。要求 `profile.store-selected` 未被显式关闭（当前适配内核默认开启）。订阅的代理扩展绑定缺失或配置无法精确修改时拒绝添加，并显示原因。非手动策略组启用 include-all / include-all-proxies 时也拒绝添加，避免新节点被自动用于宿主流量。

这是当前订阅的手动代理列表，不是自动采购或完整库存系统。可跨实例选择其中节点，但不会自动确认两个入口是否对应同一公网 IP，也不自动续费、记录到期或保证断线阻断。修改/删除录入信息可通过 Clash Verge 的该订阅代理扩展管理；此界面首期只提供新增和选择。切换订阅后不会自动把节点复制过去。

供应商认证信息由外部内核读取，写入本机私有权限（0600）的代理扩展和生成配置；不写进 VM manifest、sidecar、Git 或日志。控制接口密钥继续沿用原有传递方式。节点保存成功不等于已连接供应商；实际可用性看 guest 检测及目标 App 验收结果。共用 runtime 的实例仍拒绝切换，不因录入代理而放宽隔离约束。

开发验证：`./scripts/dev.sh test gui`；本机有 Mihomo 时可设置 `VPHONE_TEST_MIHOMO=/absolute/path/to/verge-mihomo` 运行同一测试命令，额外执行五个录入节点的真实内核 `-t` 配置校验。该校验不启动服务或修改现有 TUN，不证明供应商可达或 App 流量已通过代理。

## Decodo 美国 ZIP 与五分钟会话

实例详情的同一代理区域增加 **Decodo · 美国**。此入口复用现有 Clash TUN、进程规则、连接清理和 guest 检测，无需安装 guest VPN，不需要供应商管理 API Token。

1. 准备已开通 Residential 流量的 Decodo 账号；在运行中的 tunnel 实例上填写五位美国 ZIP（保留前导零，例如 `02108`），点击“配置账号”。填写控制台的原始代理用户名与代理密码，不是网站登录密码；用户名可带 `user-` 前缀，但不要附加位置或会话参数。
2. 点击“保存、应用并检测”。应用创建该实例的专属节点，以 HTTPS 连接 `gate.decodo.com:7000`，生成独立随机会话 ID，并设置 `country-us`、`zip`、`session_iplock` 和 `sessionduration-5`。节点名由真实实例目录生成，当前订阅内一台实例只维护一个，重新打开界面会读取已保存 ZIP 和会话 ID。
3. 点击“换新 IP 并检测”可用原 ZIP 或新 ZIP 重新申请会话。操作更新同一节点，保存规则、重载内核并核对，再只断开该 VM 的旧连接，最后显示 guest 的实测公网 IPv4。不会新增一串历史节点，也不记录永久 IP 去重库。随机拿到旧 IP 仍可能发生。
4. 每台 VM 分别配置；账户可以相同，会话 ID 独立。其它 VM 的 Decodo 专属节点不出现在本实例可选列表中。共用运行程序路径仍会被拒绝；节点被其它规则、当前策略组或自动策略组共享时拒绝更新。开启 `include-all` / `include-all-proxies` 的非手动策略组会自动收集新节点，因此此入口拒绝该配置，要求先解除这种自动共享。

五分钟是**供应商的会话有效期参数**，从供应商实际使用会话时计，不是管理器每 300 秒定时断网或自动轮换。IP Lock 在出口离线时按供应商契约返回错误；不保证住宅设备持续在线五分钟。会话到期后供应商可能分配新出口，已有长连接也不保证第 300 秒立刻断开；在任务边界使用换新 IP 按钮。ZIP 是供应商位置筛选，不保证门牌或固定半径；本版本不查询地理数据库、不会自动扩大 ZIP 范围，也不显示未经检测的公网 IP。实现依据：[高级参数](https://help.decodo.com/docs/residential-proxy-advanced-parameters)、[IP Lock](https://help.decodo.com/docs/residential-proxy-custom-sticky-sessions)、[HTTPS 入口](https://help.decodo.com/docs/residential-proxy-protocols)。

此版本只配置 HTTPS/TCP 代理，不承诺 UDP/QUIC、DNS 或所有 App 的流量覆盖。规则生效与 guest HTTPS 探测成功是不同状态；后者也不等于 Instagram 已验收。代理凭据沿用私有权限的 Clash 文件，不展示密码、不放入进程参数或 VM 元数据；全量配置解析错误会被转换为不含配置原文的提示。修改凭据时重新填写账号密码。切换 Clash 订阅、改名/移动真实实例目录后，需在新上下文重新配置；不会自动迁移或删除旧节点。

2026-10-21 开发验证：GUI 构建、自动化测试和本机 Mihomo `-t` 配置校验；覆盖五台实例独立节点/会话、反复换会话不增节点、跨实例选择拒绝、失败回滚、外部修改保留、自动共享拒绝、YAML 行内/块式及特殊字符凭据。用户暂未购买账号，因此没有真实 Decodo 连接、ZIP 库存/定位或 Instagram 实网验收。没有修改当前 Clash、VM 镜像或固定 runtime。
