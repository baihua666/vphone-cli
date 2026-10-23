# Instagram 安装与 Decodo 验收（2026-10-22）

## 已完成

- 用户授权正常重启两台机器，临时启用仅 loopback 的安装 API。严格沿用 Launchpad 绑定：official 为 2.8.0-local.b0ffd6cc，custom 为 2.8.0-local.55bcfe1a。
- 统一入口 `skills/vphone-app-install/scripts/install-workflow.sh --config "$PWD/.local/instagram-install.json"` 实际完成两台安装。Instagram bundle ID com.burbn.instagram，包内版本 452.0.1，网站请求版本 452.0.0。每台返回安装成功，并验证启动后进程持续存在 20 秒。
- 定制实例启动初期 guest not connected，随后自动恢复；没有更换镜像或部署新运行时。
- 完成后正常停止临时 API 启动进程，重新通过 vphone-launchpad-cli vm start 启动两台，恢复原管理路径。
- UI 证据：官方实例 Instagram 显示 Page isn't available right now，定制实例显示加载中。不能据此宣称登录/业务页面可用。

## Decodo 验收阻塞与证据

- 实际连接记录出现 Instagram/Meta 域名：i.instagram.com、graph.instagram.com、graph.facebook.com、scontent.xx.fbcdn.net。部分连接链为普通订阅节点，不能当成 Decodo 分流成功。
- Clash 当前规则列表中有两台当前运行路径各自的 ProcessPath → Decodo 节点，规则计数有命中；重新应用定制实例规则后，警告日志明确显示命中该 Decodo 节点但返回 HTTP need auth。
- 通过 Workstation 的“换新 IP 并检测”按钮，定制实例会话从 033c0959 更新为 fbc80790；guest IP 检测仍失败。这里只验证了会话更新，没有验证新的公网 IP。
- 代理凭据与本机配置匹配。独立 CONNECT 请求得到 HTTP 407，`x-error-message` 明确为 `Access denied. You've reached your current traffic limit. Please contact support or your account manager to review or adjust your limit.`
- Decodo 浏览器后台会话已过期，显示登录页。没有自动购买或修改额度。

## 后续验收

账户恢复可用流量后，重新申请两台五分钟会话，先取得两个 guest 实测出口，再在同一会话期内启动/刷新 Instagram，采集当前进程的新连接及代理链。分别点击每台换 IP，重复两台出口检测，验证目标 IP 改变而另一台保持不变。若 Instagram 尝试 UDP/QUIC，现有 HTTP 代理不能承诺承载，必须从实际新连接区分 TCP 与 UDP，不能把仅 HTTPS 探测成功推广成全 App 流量隔离。

本轮证据（私有、Git 忽略）：`.local/instagram-validation-20261022/`，包括 install.log、两台 screenshot、连接快照、Clash warning、Decodo 407 响应头。会话/密码均不记录在本报告。
