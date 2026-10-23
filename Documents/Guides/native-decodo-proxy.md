# 原生 Decodo 代理（可选实验能力）

Launchpad 的代理出口页提供两个方案：**Clash · 现有方案**与**原生 HTTPS · 实验**。
选择标签只切换表单；点击应用、换 IP、切回 Clash 才改变当前实例网络。
默认仍是原有宿主机/Clash 路径。失败不会静默退回宿主机或直接联网。

## 实现与边界

- 复用 vphone 的 `tunnel` 用户态以太网/TCP 层，每个 VM 拥有自己的 HTTPS CONNECT 配置；不依赖 Clash、TUN、进程路径规则或为分流复制 runtime。
- 外层连接限定物理 Wi-Fi/以太网，忽略系统代理，TLS 验证保持开启。Decodo ISP 实测跨端口 TLS 1.3 失败，因此实验实现外层限制 TLS 1.2；不限制 guest HTTPS 使用的 TLS 版本。
- UDP DNS 经相同 Decodo 入口中的 DNS-over-HTTPS 查询 1.1.1.1；Decodo 拒绝 CONNECT 53。内层 TLS 用系统 Security 的 SecureTransport 包装现有通道（已弃用 API，实验实现技术限制），没有另开宿主机直连。
- 支持 IPv4 TCP、UDP DNS；其它 UDP/QUIC 阻止，IPv6 沿用现有栈限制。TCP DNS、纯 UDP App、全部 Instagram 功能尚未验收。
- 切换清除当前 VM 的 TCP/UDP 流；其他 VM 的网络对象与配置不变。会中断该实例现有连接，但不需要重启支持此接口的 VM。
- ISP 复用既有城市规则、随机端口选择；动态住宅复用独立 `session_iplock` / `sessionduration-5`。五分钟不是自动轮换定时器，也不保证每次得到不同公网 IP。

## 本机配置与操作

1. 在所选实例的绑定 CLI 与运行 Core 中检查原生代理能力。官方基线保持 2.8.0；能力缺失时提示失败，不因版本号相同就假定支持，也不自动升级。需要部署 Core 时另行确认并安排维护窗口。
2. 原生页指定本机凭据文件：默认 `~/.vphone/decodo-isp.json`，也可用 `VPHONE_DECODO_ISP_CONFIG` 或直接填绝对路径。JSON 必须含 `username`、`password`，权限 0600；其它字段可保留。动态住宅改选对应套餐，并使用住宅账号文件。不要将真实凭据提交 Git。
3. 选择美国城市参数（例如 `new_york_city`）或住宅 ZIP，再填写此 Mac 的物理网卡类型与 BSD 名称（例如 Wi-Fi / en1）；两者会核对，不能照搬其它 Mac。
4. “直连检测”通过绑定该物理网卡的系统 curl、AliDNS HTTPS 引导解析获取真实 Decodo 网关地址，避免 Clash fake-IP；它消耗少量流量，但不写 VM 或 Clash。
5. “应用原生出口”先验证新入口，再经本机 CLI 应用到此实例；之后从 guest 检测真实 IP。“一键换 IP”走相同流程，创建新配置。
6. “切回 Clash”只移除此实例原生覆盖，恢复原有宿主机路径；不会重载 Clash、修改其账号、节点或规则。原有 Clash 本身仍须工作。

配置保存在 `~/.vphone/native-proxies/<机器路径摘要>/<UUID>.json`（0600），机器目录的 `native-proxy-reference.json` 只保存绝对路径。每次保存独立文件，IPC 结果不确定时不删除可能被 VM 引用的文件。不会同步密钥或这些绝对路径到另一台 Mac；其它 Mac 重新提供凭据、选择本机网卡并应用。

网关真实 IPv4 在应用时解析并保存，不会在后台自动修改当前会话；若供应商更换网关地址，应重新应用/换 IP。配置缺失、权限错误或认证失败时关闭该原生通道，不绕过代理。

## CLI 合同

```sh
vphone-cli vm network <name> --native-proxy-file /absolute/private-config.json --json
vphone-cli vm network <name> --native-proxy-file '' --json
vphone-cli vm network <name> --probe --json
```

原生配置字段：`host`, `address`（真实 IPv4）, `port`, `username`, `password`, `interface`（wifi/ethernet）, `dnsAddress`（默认1.1.1.1）。VM 控制端先验证和保存引用，再切换网络。状态新增 `native_proxy_supported`、`native_proxy_enabled`，客户端同时检查 CLI 选项与运行中核心能力，旧核心不接收修改。

这是本地新增的可选跨进程能力，原生代理在使用时检查绑定 CLI 的选项与运行核心能力；早期 2.9 名称是已纠正的本地错误命名，不是最低版本要求。Launchpad 基础操作的兼容下限保持 2.8.0，不能仅因可选代理阻止既有实例创建或启停。构建不等于部署；不得替换当前 2.8 固定 Bundle 或停机。已有 `/Applications/vphone-launchpad.app` 与 Workstation 仍是现场备用入口。

## 验证

离线测试包括凭据权限、fake-IP 拒绝、DNS 响应、每网络独立状态、TCP/UDP 无隐式回退、旧 CLI 不接收修改。完整 CoreKit、WSCore 和 Launchpad Bundle 名称测试按各项目方式运行。

真实代理网络栈测试是显式启用的 `VPhoneNativeProxyLiveTests`，使用真实 HTTPS 代理、两个独立 TCP 转发器、TCP half-close 与再次换入口，消耗少量流量，不启动 VM。通过 `TEST_RUNNER_VPHONE_NATIVE_PROXY_FIXTURE` 传私有配置路径、`TEST_RUNNER_VPHONE_NATIVE_PROXY_TARGET` 传当时经独立 DNS 解析的 ip.decodo.com IPv4 给 xcodebuild。测试使用独立测试端口 32362 / 42362；此测试配置不能与正在使用这两个端口的业务混用。供应商可能重复 IP，因此不同 IP 的断言依赖当时供应商实际分配。

本轮真实结果及未覆盖项见 [现场记录](../../Research/Host/native_decodo_transport_20261022.md)。网络栈测试不能代替两台完整 guest 与 Instagram 的实测。

候选产物（本机，未覆盖安装）：`.build/NativeProxyBundle/Build/Products/Debug/VPhone.bundle` 与 `.build/NativeProxyLaunchpad/Build/Products/Debug/vphone-launchpad.app`。不要在工作中的实例上替换运行核心。

### 独立测试机的按钮调用链回归

`VPhoneWorkstation/tests/VPhoneWSCoreTests/NativeDecodoLiveTests.swift` 是显式启用的真实 guest 测试，直接调用 Launchpad 按钮使用的 `NativeDecodoController`，不是模拟代理响应。默认跳过；启用后会消耗 Decodo 流量并修改指定测试机的网络覆盖，最后切回宿主机/Clash。

只能用于专门创建的 `native-https-test-a`、`native-https-test-b`，先确认两机由当前验收独占且 guest 已就绪。测试不启动/停止 VM，不改 Clash 配置，不操作其它实例。通过环境变量指定 `VPHONE_NATIVE_VM_LIVE=1`、`VPHONE_NATIVE_VM_CLI`（兼容核心的 CLI 绝对路径）、`VPHONE_NATIVE_VM_ROOT`（测试机库）、`VPHONE_NATIVE_VM_CREDENTIALS`（本机 0600 凭据文件路径）；网卡可通过 `VPHONE_NATIVE_VM_DEVICE` / `VPHONE_NATIVE_VM_INTERFACE` 覆盖。运行：

```sh
swift test --package-path VPhoneWorkstation --filter nativeDecodoTwoGuestRotationAndClashFallback
```

断言覆盖两机不同出口、只换 A 后 B 保持不变、逐台切回 Clash 后仍能从 guest 获取出口。供应商偶然重复分配 IP 时，不同 IP 断言会失败；这不是“永不重复 IP”的产品保证。测试异常会尝试恢复两台测试机的宿主机路径，进程被终止时仍须检查实际状态。

2026-10-22 已用两台独立 2.9 guest 跑通上述真实控制器测试：不同原生出口、只换 A 不改变 B、逐台恢复 Clash 均通过。具体 IP、失败重试与限制见现场记录末节。测试机共用核心即可独立原生分流；该结果不扩展为 Instagram/UDP/IPv6 全功能验收。

## 2026-10-23 地区选择与共用核心修复

以上 2.9 为早期本地错误命名的历史记录。当前官方基线保持 2.8.0，原生代理按运行中核心的能力检测启用，不按自增版本判断。本轮使用 `2.8.0-local.199abaf3`。

- 原生页与 Clash 页复用同一个 Decodo 地区组件：国家、州、城市分类及搜索；数据来自账号授权接口，自动续期沿用已有实现。
- 选择地区后“应用原生出口”，已启用时显示“一键换 IP”。打开界面会从该机器已保存的代理配置恢复已选地区。
- 共用 Core Bundle 导致 Clash 路径分流不可用时，若运行核心支持原生代理，界面优先展示原生页；仅切换表单，不自动改网络。Clash 不可用时也保留地区列表与同步入口，应用按钮明确禁用。
- ISP 新端口避开各资料库已保存的原生代理端口与本应用正在申请的端口；端口不同不承诺供应商永远分配不同 IP。
- 配置仍按实例单独持久化，换出口不修改核心版本或绑定。IPv4 TCP/DNS 支持与 UDP/QUIC、IPv6 限制不变，不能称为全部 App 协议均已支持。
