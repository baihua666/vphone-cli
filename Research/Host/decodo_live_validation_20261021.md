# Decodo 本机配置与两台 VM 实测（2026-10-21）

## 交付

Workstation 从 `VPHONE_DECODO_CONFIG` 指定的私有 JSON 填充表单。仓库启动入口默认传入 `.local/decodo.json`；只传路径，真实凭据不写入源码、启动参数或 Git。打开表单不修改线上会话，用户点击保存才应用。已有 VM 的 ZIP 优先于文件默认值。

测试环境：本机 Clash Verge / Mihomo，official-2x-20261016 和 custom-2x-20261016，各自绑定独立运行目录及 PROCESS-PATH 规则，tunnel 网络，ZIP 10001。没有修改 VM 镜像、安装 guest VPN 或购买额外流量。

## 真实结果

所有下表 IP 均来自各自 pinned CLI 的 `vm network <name> --probe --json`，`egress.origin=guest`，HTTPS 请求 api.ipify.org；换新动作由新版 GUI 按钮触发。时间为北京时间。

| 阶段 | 时间 | official | custom |
|---|---|---|---|
| 两台基线 | 22:32:47–49 | 72.43.150.26 | 173.68.56.230 |
| 只换 custom 后 | 22:33:25–27 | 72.43.150.26（不变） | 143.55.4.105 |
| 再只换 official 后 | 22:33:53–55 | 207.96.121.68 | 143.55.4.105（不变） |

对比脱敏节点快照，只有目标 VM 的 session ID 变化；另一台会话及节点配置不变。每个用户名均带独立 session_iplock 和 sessionduration-5。供应商曾随机重复分配相同 IP，手动再次换新后取得不同 IP；不能宣传“一次点击必定不同”。五分钟参数已验证，未进行完整到期行为测试。

## 连接问题及本机修复

1. 原配置 `proxy-server-nameserver: [udp://127.0.0.1:7874]` 查询自身 fake-IP DNS。内核日志显示连接 gate.decodo.com 时拨号到 198.18.0.5 / 2001:2::4 而超时，guest 表现为 TLS -1200/-9816。
2. 在当前订阅 merge `profiles/mV3VtfToOedl.yaml` 及运行配置添加仅针对 `gate.decodo.com` 的 `dns.proxy-server-nameserver-policy`，使用现有 `tls://223.5.5.5`、`tls://119.29.29.29`。随后首次取得两个不同 guest 出口，但直连真实网关 IP 仍间歇超时。
3. 在两个 Decodo 节点（代理扩展 `profiles/p6a5c7JkJPoi.yaml` 及运行配置）使用现有具体节点 `🇯🇵 日本-广东专线 BGP` 作为 `dialer-proxy`。最终出口由 Decodo 会话决定，中转节点不合并两台会话。
4. 保存和轮换逻辑现在保留已有合法非空 `dialer-proxy`，仍只替换认证字段，拒绝其他额外字段。没有禁用 TLS 校验。
5. 本机修改均先备份至 gitignored `.local/decodo-validation-20261021/`，新配置通过真实 Mihomo `-t` 验证，再经 Unix socket 的 configs payload 加载。DNS修改未改变规则；本机 YAML 序列化使用不折行格式以兼容精确标量编辑器。

此中转为本机排障配置；新环境仍需按实际网络配置中转及 DNS，不是新增通用中转管理界面。当前运行和扩展文件均保留配置，未单独执行 Clash 重启/订阅更新的持久性实测。

官方依据：[Mihomo DNS](https://wiki.metacubex.one/config/dns/)、[dialer-proxy](https://wiki.metacubex.one/config/proxies/dialer-proxy/)、[Decodo 自定义黏性会话](https://help.decodo.com/docs/residential-proxy-custom-sticky-sessions)、[HTTPS 代理协议](https://help.decodo.com/docs/residential-proxy-protocols)。

## 验证与边界

- `scripts/dev.sh test gui`：96 tests passed；新增配置读取测试及中转保留回归测试，后者先确认失败再修复。
- `scripts/dev.sh build gui`：通过，新版已重启并用于上述 GUI 实测。
- 自动填入凭据及密码遮蔽在两台配置表单确认；源码审查无阻塞项。
- 原始 guest JSON 和脱敏会话快照留在 `.local/decodo-validation-20261021/`；含凭据的备份不进入 Git。
- 验证范围是两台 guest HTTPS 公网出口与手动会话轮换；不代表全部 App/UDP/DNS 的出口，也未验证 Instagram 登录或实际 IP 地理库对 ZIP 的判定。
