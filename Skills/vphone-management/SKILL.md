---
name: vphone-management
description: 配置和升级 vphone Launchpad 管理界面、Decodo 美国 ZIP 与每实例五分钟代理会话，或在其他 Mac 同步部署；Workstation 仅作备用。不用于重建固件或下载 IPA。
---

# vPhone 管理与 Decodo

优先使用本仓库扩展的 **Launchpad** 作为统一入口；官方发行版没有本地增加的 Decodo 页面。复用 `VPhoneWSCore`，不复制供应商认证、Clash 配置编辑或会话轮换逻辑。Workstation 是同一服务的备用客户端。

## 开始前

- 先确认本机仓库、已安装 app 签名、核心 Bundle、实例库、`launchpad.json` 与正在运行的实例。用户说不影响其它操作时，只构建测试，不退出管理器、替换 app、启停 VM 或重载 Clash。
- 读 [跨 Mac 部署与备用方案](references/deployment.md)。涉及源码变更时还读仓库 `AGENTS.md` 和 `Documents/Guides/architecture-boundaries.md`。
- 源码位于 `VPhoneLaunchpad/`；共享服务在 `VPhoneWorkstation/Sources/VPhoneWSCore/Proxy/`。CLI 与 VM 网络层不应引入 Decodo/Clash 配置知识。
- 不把本机 ZIP、节点名、runtime 哈希、用户名或目录当成别的 Mac 的默认事实。先读取目标机配置，再选兼容的 2.x 版本。

## 操作与验收

1. 选择目标机器 → 检查器「代理出口」→「Decodo 配置与换 IP」。打开窗口、读取文件、刷新配置只读取数据；保存或换新才修改代理。
2. 凭据优先用 `~/.vphone/decodo.json`（0600）；也可在表单输入绝对路径，或用 `VPHONE_DECODO_CONFIG` 覆盖。只在本机保存真实凭据，不进 Git、日志、命令行、截图或同步包。
3. 要求 Clash Verge Rule + TUN + strict 进程识别、机器实时网络为 tunnel、每机独立 vphone-vm 路径、当前订阅已有对应的唯一 PROCESS-PATH 规则及代理扩展。共用 Bundle 的机器不能按路径分流；先解决绑定与规则，不能静默自动复制 runtime。
4. 填美国五位 ZIP，保存后创建该机独立 session_iplock、sessionduration-5。换新仅更新目标会话并断开其旧连接；不承诺每次不同 IP，不把五分钟参数解释成自动定时换 IP。
5. 分别记录配置保存、Mihomo 生效、guest 实测出口。两机应同时得到各自 guest IP；只换一台后复测两台，核对另一台会话和规则未改。供应商自然更换 IP 不等于本程序修改了另一台。不要用 Mac 自身的 curl 或旧测试结果冒充 guest 成功。
6. `HTTP need auth` 表示代理认证被拒绝，需检查有效流量/凭据；不要关闭 TLS 校验。DNS fake-IP 或网关超时需核对已有 DNS 和中转配置，不盲目复制其它 Mac 的节点名。

Launchpad 的客户端环境/启动链显示“未知”可能只是历史 VM 未记录来源；不要为去掉提示执行 restore 或 CFW 更新。切换运行时后在允许的维护窗口重启再验收代理，不能只看新的磁盘绑定认为运行中进程也已切换。

当前代码验证与部署边界见 `Documents/Guides/launchpad-decodo.md`；真实现场记录在 `Research/Host/`。测试通过不等于已部署，构建 app 不等于有可用 Helper 签名。
