# 官方 Launchpad 接入现有两机（2026-10-22）

## 已部署

- 官方 `2.8.0` 公证发行版安装到 `/Applications/vphone-launchpad.app`，Developer ID 与 stapled notarization 验证通过。用户完成管理员认证与开发者工具授权，Helper 15、hostReady、bundleReady 均通过。
- 原运行时通过官方 `bundle install-local` 安装为 `2.8.0-local.b0ffd6cc`，用于 official。用户明确授权保留两份独立 runtime，以维持 PROCESS-PATH 分流；custom 的副本仅新增 `Contents/Resources/instance-route.txt` 后重新签署外层 bundle，安装为 `2.8.0-local.55bcfe1a`。两份内部 CLI/VM cdhash 相同，未修改可执行程序或 guest 资源。
- 两台现有目录 `~/.vphone/machines/{official,custom}-2x-20261016` 原地接入，写入 `launchpad.json`，同步 `.vphone-ws.json` 的 executablePath。未复制磁盘、重建镜像或运行 CFW 安装/升级。启动后 config.plist 与迁移前备份逐字节一致。
- bootChain/guestEnvironment 绑定字段留空：历史创建未由 Launchpad 记录，不虚构版本来源。因此检查器显示“未知”，不代表应用或固件丢失。
- 两机均由官方 app 的 launcher 启动，实际进程路径对应各自的 root-owned Bundle。vphoned 响应，官方列表和 UI 显示两机运行。
- 随后观察到外部操作改变运行状态：custom 日志显示正常 system shutdown / exit 0，official 的进程已被替换并带本轮未使用的 `--api-listen 127.0.0.1:18761`。本轮暂停进一步启停，避免与其它会话冲突；交付时不能声称两台仍同时运行。
- apps.list 确认 official 的 Subway Surf，custom 的 Facebook、Subway Surf、Idle Miner、VPHONE Probe、wooshort 仍在。此次未做应用业务流程验收。

## Decodo 保留与阻塞

当前订阅前置规则及运行配置中，仅把原两条 PROCESS-PATH 替换为上述 Bundle 中的 vphone-vm 路径；节点名称、代理凭据、ZIP 10001、五分钟 IP Lock、中转与 DNS 策略保留。重载后比较 type/payload/proxy，确认其它规则未变；不能比较会变化的命中计数与时间戳。

Workstation 仍可读取新绑定并操作原 Decodo 配置；为排除旧会话问题，已通过其按钮给 custom 申请新会话，保存与生效均成功，但 guest HTTPS 出口检测仍失败。Mihomo 日志确认 custom 命中新 Launchpad ProcessPath 与自身 Decodo 节点，返回 `HTTP need auth`；guest 表现为 TLS -1200/-9816。两机首次出口检测均失败，**本轮未完成双公网出口验收**，不能引用 10 月 21 日结果冒充本轮成功。Decodo 网页会话已退出至登录页，账户流量与凭据有效性仍需登录核对。

官方 Launchpad 当前没有 Decodo 配置或换 IP 页面；代理能力仍由保留的 Workstation 提供，不声称已经迁移业务 UI。

## 证据与恢复

- 脱敏验证文件：`.build/validation/launchpad-20261022/`，包含状态、机器列表、apps.list 与路由。
- 原配置及含敏感数据的 Clash 备份：`~/.vphone/migration-backups/launchpad-20261022/`，不提交。
- 原 runtime、磁盘和旧 Workstation 均保留。回退前正常停止两机；恢复原两份 `.vphone-ws.json`，并仅将两条 Clash 规则映射回原路径后重载。不要用旧备份整体覆盖后续代理账号或节点变更；不要在回退后继续从 Launchpad 启动不同路径。
- 日常启动使用 Finder 的 `/Applications/vphone-launchpad.app`；默认库即 `~/.vphone/machines`，不需要 workstation.command。

官方安装来源：https://github.com/Lakr233/vphone-cli/releases/tag/2.8.0 。本地契约见 `Documents/Guides/launchpad-cli.md`。
