# Decodo ISP 纽约城市出口验证

日期：2026-10-22。目标为 ZIP 10001 所在纽约市，复用已购 ISP Pay/GB，不新增购买。
已更新真实 /Applications/vphone-launchpad.app，使用现有 Apple Development 证书签名。
共享业务逻辑在 VPhoneWSCore，Launchpad 复用；核心 Bundle、VM 镜像、Instagram 安装不变。

## 实现与官方参数

官方文档：https://help.decodo.com/docs/isp-pay-per-gb-proxy-user-pass-requests
ISP 网关 isp.decodo.com；静态端口 10001–63000。每台建立独立稳定名称的节点；
每次获取/换新从完整范围中排除所有已配置的 ISP 端口，再选取新端口。
凭据加入 country-us-city-new_york_city。保留已有 TLS、中转、DNS、UDP443 拒绝规则及其它实例规则。

文档给出的 new_york 在本账户返回 HTTP 400；new_york_city 实测成功。
New York 自动归一为 new_york_city，既不使用州参数也不降级为全国随机。
原 ISPProxyPool.next 四节点轮换已移除。手动节点选择的通用能力保留。

## Guest 实测

| 实例/阶段 | 端口 | guest 公网 IPv4 | ipwhois.app 归属地 |
|---|---:|---|---|
| custom 初次成功 | 32361 | 72.245.66.178 | New York City |
| official 初次成功 | 55632 | 48.45.92.155 | Houston（明确提示不符） |
| official 第一次换新 | 17459 | 216.132.139.129 | Princeton（明确提示不符） |
| official 最终 New York 别名换新 | 52898 | 72.245.70.229 | New York City |
| custom 在 official 换新后复测 | 32361 | 72.245.66.178 | 沿用首次纽约结果 |

最终两台并行 guest probe：
- official 2026-10-22T06:53:20Z：72.245.70.229
- custom 2026-10-22T06:53:19Z：72.245.66.178
- 均 origin=guest，source=https://api.ipify.org?format=json，未返回错误。
- official 换新未更改 custom 的端口、规则及公网 IP。

已用 Decodo /json?provider=IPinfo 交叉检查端口17459与32361：
分别返回与 guest 相同的216.132.139.129和72.245.66.178，均称New York City、ZIP10004。
前者与ipwhois.app Princeton不一致，证明不能保证所有App采用相同归属地数据库。
最终没有把ZIP10004说成ZIP10001，也不能证明距目标街道多近。

## 范围与证据

本轮使用小 JSON 请求进行代理链路验收，未下载IPA、视频或登录Instagram账号；
不能将HTTPS出口结果表述成Instagram服务端已经认定目标邮编。
本机原始探测JSON、界面截图在gitignored .local/isp-city-20261022；
供应商认证只从本机配置读取，没有进入日志或此报告。
已保留此前新增的归属地查询及备用服务代码。

测试：./scripts/dev.sh test launchpad，105项通过；Xcode Launchpad构建成功；
签名通过codesign --verify --deep --strict。单测覆盖城市参数、完整端口范围、
独立节点创建、重复换端口及只断开目标实例连接。未重启VM。

交付前再次核验：Launchpad主机设置6/6，developerTools=true，helper=ready(15)，
hostReady=true，canInstallBundles=true；两台running。系统Helper更新认证已生效。
