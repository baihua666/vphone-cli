# Native Decodo transport — 2026-10-22

范围：不启停、不更换绑定、不修改正在运行的 official/custom VM 或 Clash。新方案只在隔离构建、网络栈测试中验证；Clash 保留。

## 直接连接证据

- 清除 HTTP(S)/ALL_PROXY 环境，curl 显式绑定 en1，通过绑定物理接口的 AliDNS DoH 取得 isp.decodo.com 的真实 A 记录（149.102.253.118 / .120）；不使用 fake-IP 198.18/15。
- HTTPS 入口端口 32361 返回 72.245.66.178，Decodo/IPInfo: New York City, NY, ZIP 10004。没有 preproxy 或本地 Clash 端口。
- 同条件 SOCKS5h 超时，不将 SOCKS5 当作已验证方案。
- 原生 Network.framework 仅指定 Wi-Fi 时因系统代理失败，加 preferNoProxies 后直连成功；Apple 官方 API 说明该选项忽略系统代理。
- CONNECT 1.1.1.1:53 返回 403。改用 CONNECT 443 内的 DNS-over-HTTPS，得到 63 字节 DNS 响应，rcode=0。

## 两套原生 TCP 栈

测试直接驱动 VPhoneTCPForwarder 的 guest SYN/ACK、数据与 FIN，连接真实 Decodo，再解析目标服务返回的公网 IP。没有使用伪造出口或改变现有 VM。

| 步骤 | A | B |
| --- | --- | --- |
| 初次连接 | 72.245.66.178 | 72.245.66.179 |
| 仅 A 换入口 | 48.45.92.193 | 72.245.66.179 |

跨端口连接最初连续出现 TLS WRONG_VERSION_NUMBER；独立进程单端口正常。禁用会话恢复、独立 privacy context 本身没有解决。限定外层 TLS 1.2 后完整测试通过（13秒），包含 half-close 后继续接收响应。这是当前 ISP 网关兼容性处理，不能据此声称所有网关/套餐都兼容。

私有测试配置和原始构建日志位于 gitignored `.build/direct-proxy-validation/`，不会提交账号密码。

## 交付边界

- 实验 UI 与 CLI / VM 原生接口已实现，2.9 候选产物独立构建。
- 当前已安装 UI、2.8 核心、两台机器的代理、镜像和进程未替换。PID373 启动14:28:45；PID98848 启动14:28:10（本机时间），验证期间保持不变。
- 本轮尚未把新核心启动到两台完整 iPhone guest；Instagram App、guest DNS、UI按钮到guest端到端仍待独立测试实例或获准维护窗口验收。不得用这里的网络栈结果冒充这些项通过。
- UDP/QUIC、TCP DNS 不在当前实现覆盖范围。动态住宅 ZIP 参数复用既有实现，本轮付费流量账户实测为 ISP。

参考：
- https://developer.apple.com/documentation/network/nwparameters/prefernoproxies
- https://help.decodo.com/docs/isp-pay-per-gb-proxy-protocols
- https://github.com/Lakr233/vphone-cli （MCP核对原有用户态TCP转发层）

验证结果：CoreKit 415 项通过（含 opt-in 真实两栈换 IP）；WSCore 117 项通过；Launchpad Bundle 名称/绑定测试通过；完整 VPhone Bundle、Launchpad 构建通过。候选 Launchpad 使用本机既有开发签名，未安装覆盖当前应用。

## 补充：两台独立 guest 验收（2026-10-22 晚间）

此前“未启动两台完整 guest”的边界由本节更新。经用户授权，使用停机检查点创建 `native-https-test-a` / `native-https-test-b`，独立 ECID/MAC、各 2 CPU / 3 GiB，共用独立安装的 `2.9.0-local.f9f452dc` 核心。没有克隆运行中的业务磁盘，没有更改业务机的核心绑定。

真实测试调用与 Launchpad 应用/一键换 IP/切回 Clash 按钮相同的 `NativeDecodoController`，从各 guest 的 HTTPS 请求读取 IP。不是鼠标点击验收，也不是宿主 curl 代替 guest。最终一轮 55.8 秒通过：

| 步骤 | 测试 A | 测试 B |
| --- | --- | --- |
| 各自应用原生 HTTPS | 216.132.139.119 | 216.132.137.1 |
| 仅 A 一键换 IP | 72.245.66.19 | 216.132.137.1 |
| 仅 A 切回 Clash | 210.79.151.66 | 216.132.137.1 |
| B 也切回 Clash | 210.79.151.66 | 210.79.151.66 |

宿主显式请求 Clash `127.0.0.1:7890` 同时得到 `210.79.151.66`，作为回退路径对照；上述表格仍以 guest 输出为准。两台共用核心也能独立原生出口，不需要增加 Clash 进程路径规则。最终状态为两台原生覆盖均关闭。

失败证据一并保留：第一轮两台出口和 A 轮换通过后，A 正常关机（日志 Guest stopped / exit 0），回退检测被中断；用户已授权本轮操作测试机，恢复 A 后继续。下一轮有一次新入口应用后的 guest HTTPS 超时；恢复 Clash 可正常访问，重新应用已知入口也正常。尚未确定该次超时是节点、网络或客体状态原因，不声称已修复；最后整轮通过不代表所有节点长期稳定。失败时没有自动回退，由测试明确调用恢复操作。

测试源：`VPhoneWorkstation/tests/VPhoneWSCoreTests/NativeDecodoLiveTests.swift`，默认跳过，需显式环境变量启用。私有原始日志在 `.build/native-vm-validation/`：`live-test-result.log`、`live-test-result-retry.log`、`live-test-result-final.log`。凭据与私有代理配置不提交。

用户中途暂停期间，其他操作启停了业务机、更新了 Launchpad 和 Clash；不能沿用下午 PID 不变的表述。晚间本轮未操作业务机，重新建立的 Clash 配置哈希与两台业务 `launchpad.json` 哈希在验收后保持一致。本轮仅启停测试 A/B，没有重载或修改 Clash。验收后停止两台测试机释放资源，保留镜像、核心与配置。

两台 `display.auto_lock` 均返回 Never。A 的冷启动控制可连接、解锁可用，但曾读到亮屏锁定，完整自动化就绪仍不能只凭 Never 断言。此次通过范围是 ISP 原生 IPv4 HTTPS、DNS 支撑的真实 guest 出口、独立轮换与显式 Clash 回退；Instagram、全 UDP/QUIC、IPv6 和动态住宅 ZIP 流量套餐未在本次补充验收。

## 2026-10-23 地区 UI 与真实双机回归

- 复用已有 DecodoProxyController 账号地区目录与同一 SwiftUI picker 到原生页，不复制供应商接口。Clash 路由不存在不再隐藏地区目录。保持官方 2.8.0 基线及核心绑定不变。
- 补充原生端口避让（各实例持久配置+进行中申请）、重新打开界面恢复选定地区。新增国家/州/城市/随机参数与端口占用离线测试。
- 共享测试默认并行曾 signal 11 崩溃；串行完整运行 119 项通过。Launchpad Xcode build 通过，使用现有开发证书签名。
- 选择原先停止的 1-20261023 / 4-20261023，明确不操作正在使用的 2、3。两机共用 2.8.0-local.199abaf3，实际控制器调用官网 New York City 地区。
- `nativeRegionsTwoGuestRotation` 真实测试通过：1 初始 48.45.88.48，4 初始 216.132.139.246；只换 1 后为 72.245.66.87，4 仍 216.132.139.246；4 的配置引用逐字节不变。配置及 guest IP 均验证，不以宿主机请求代替 guest。
- 管理台地区与公网数据库可能有差异；不同端口不保证每次不同 IP。本轮不是 Instagram 全协议验收。
- 两机正常重启后仍原生 enabled：1 号 isp.decodo.com:12547 / guest 72.245.66.87，4 号 isp.decodo.com:17589 / guest 216.132.139.246。4 号启动过程中一次探测返回 guest not connected，等待 vphoned 就绪后成功，未据临时错误更换代理。
- 对两份已保存入口的供应商 IPInfo 查询均返回 New York City / New York / US（邮编数据库 10004；不是用户指定街道或 ZIP 承诺）。
- 已部署本地测试版 Launchpad；保留此次未改动的原有签名 Helper 二进制并重签外层 app，避免同内部版本重新编译触发不必要的 Helper 替换。完整代码签名验证通过，核心与实例绑定未变。
