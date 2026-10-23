# Decodo ISP 双机出口与端口切换实测

2026-10-22，用户授权使用已购共享 ISP 1 GB 流量，暂不要求 ZIP 定位。复用已安装 Instagram 452.0.1，无 IPA 下载、无 VM 重启、无新增购买。

## 配置

复用 Workstation 的「添加已购代理 IP」与「本实例出口 → 应用出口并检测」。已安装 Launchpad 尚无本地代理 UI，Workstation 作为备用；两套管理器的 per-machine runtime 绑定已核对一致。

新增四个 HTTPS 代理端点 `IP · Decodo ISP US 10001` 至 `10004`，网关 isp.decodo.com、对应端口，使用 ISP 用户密码及 country-us 认证参数。凭据存于 gitignored `.local/decodo-isp.json`，权限 0600；原住宅配置保留。

本机沿用已有日本中转节点，新增 isp.decodo.com 的 proxy-server-nameserver-policy，避免 fake-IP 网关解析问题。配置修改已通过 Mihomo 配置校验，并在出口应用时加载。

首次采样发现 HTTP 代理不支持 UDP，Instagram 的 UDP 443 会继续匹配订阅节点。因此在这两台 VM 的 PROCESS-PATH 规则之前新增 AND(PROCESS-PATH,NETWORK UDP,DST-PORT 443) REJECT，仅阻断两台的 QUIC，促使回退 TCP。规则同时保存于当前 rules 扩展和运行配置。其它 UDP 不在本次保证范围。新增规则首次重载触发服务的“生效规则变化”校验；刷新后重新应用成功，随后切换没有再报错。

## 结果

| 实例 | 初始端口 | guest 公网 IP | 切换后 |
|---|---|---|---|
| official-2x-20261016 | 10001 | 9.249.113.0 | 保持 10001；custom 切换后复测仍为 9.249.113.0 |
| custom-2x-20261016 | 10002 | 9.249.113.1 | UI 切至 10003，guest 检测为 9.249.113.10 |

guest IP 来自虚拟 iPhone 内 api.ipify.org HTTPS 探测，不是 Mac 自身出口。未独立验证地址地理库，不承诺 ZIP、独享或永久 IP。

修正 QUIC 后的基线采样中，两台 i.instagram.com / graph.facebook.com 的 TCP 连接分别命中 10001 与 10002，且收到响应字节。custom 切换后重启 Instagram，新的 i.instagram.com / graph.instagram.com / graph.facebook.com TCP 连接命中 10003，official 保持 10001。切换后采样未见这些域名走订阅节点。

两台屏幕均成功显示 Join Instagram 欢迎页。未输入账号、未登录或验证登录后的 Feed/视频/发布业务。为节省流量，保存截图后退出两台 Instagram，虚拟机继续运行。没有精确账单流量增量数据；不将采样字节数冒充供应商计费。

## 用户操作

1. 选中 VM，在「本实例出口」选择 `IP · Decodo ISP US 1000x`。
2. 点击「应用出口并检测」，以“已保存 / 已生效”和新的 guest IP 为准。
3. 两台选择不同端口；10004 可用于下次测试，尚未验证该端口出口。

下方旧「Decodo · 美国 / ZIP / 换新 IP 并检测」仍是动态住宅流程，不能用于 ISP。这次交付的是已有手动端点选择 + 一次应用的闭环，没有把旧按钮改成自动递增 ISP 端口，也没有 ZIP/五分钟住宅会话保证。

私有证据：`.local/isp-validation-20261022/` 下的 tcp-baseline.json、after-switch.json、official-after-custom-switch.json、两台 final.jpg 与 custom-isp-ui.png。备份在同目录；不得提交含认证的 YAML 或原始凭据。

官方资料：[ISP 会话与端口](https://help.decodo.com/docs/isp-pay-per-gb-proxy-session-types)、[认证参数](https://help.decodo.com/docs/isp-pay-per-gb-proxy-user-pass-requests)、[协议](https://help.decodo.com/docs/isp-pay-per-gb-proxy-protocols)。静态端口 10001–63000，10000 为轮换端口；换端口用于请求不同出口，不承诺绝不重复。
