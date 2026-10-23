# Decodo 充值后复测：产品流量不匹配

2026-10-22，用户告知已购买 1 GB，授权低流量复测两台 Instagram 独立出口与一键换 IP。

- 两台 VM 继续运行，无重启、无 IPA 下载或安装。
- 已安装 Launchpad UI 尚无代理区域，沿用已部署 Workstation 备用界面；核对 `.vphone-ws.json` 与 Launchpad 绑定完全一致。
- 定制实例点击换新并检测，新会话前缀 e502a5c8；guest 探测 TLS 失败。
- 单次独立小流量 CONNECT 诊断返回 HTTP 407，x-error-message 为当前流量上限已达到。没有继续反复刷新 Instagram。
- 用户已登录后台现场核对：`/static-isp-proxies/proxy-setup` 为共享 ISP 按流量付费，1 GB plan，已激活，0 / 1 GB；网关 isp.decodo.com，与动态住宅网关不同。
- `/residential-proxies/proxy-setup` 为动态住宅 100 MB Trial，已取消、距离停用还有 2 天，用量 0.14 / 0.1 GB。
- 所以充值并未恢复当前动态住宅账号。不能宣称购买无效或 1 GB 已耗尽，也不能将 ISP 端口直接套入当前 session_iplock + ZIP 参数。

等待用户选择：适配已购 ISP 的独立端口/出口，或由用户处理动态住宅套餐后继续现有方案。没有代购、退款、修改套餐或切换两台至 ISP。原始诊断在 gitignored `.local/decodo-retest-20261022/`。此轮未完成独立出口/换 IP 验收。

后续：用户选择使用已购 ISP，已完成手动端口切换与两台 Instagram 未登录欢迎页实测，详见 [ISP 验证记录](decodo_isp_validation_20261022.md)。
