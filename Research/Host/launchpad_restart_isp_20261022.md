# 新版 Launchpad 权限、启停与重启后 ISP 验收

2026-10-22 14:31（Asia/Shanghai）。使用 /Applications/vphone-launchpad.app 本机 Apple Development 签名版。

## 授权修复

用户完成管理员认证后，系统开发者工具列表中旧 Launchpad 开关为 on，但应用实时 EPExecutionPolicy 检查仍不通过。仅移除该旧条目，重新选择 /Applications/vphone-launchpad.app 添加；再执行 Launchpad 主机检查，6/6 通过。
最终 control API 状态：developerTools=true、hostReady=true、canInstallBundles=true、helper=ready (15)，2 台运行。没有修改其它应用授权、直接编辑 TCC 数据库或关闭系统安全机制。

## 启停

通过新版应用内置 vphone-launchpad-cli 控制服务逐台操作，不绕过 Launchpad 启动链。每台均确认 vm list 返回 stopped 后再 start --wait，原绑定未改。
- custom：正常停止，重新启动；vphoned 在 18 秒后响应。
- official：正常停止，重新启动；vphoned 在 26 秒后响应。

首次 custom stop 返回的是仍处于关机中的 running 快照，立即 start 被正确拒绝“already running or busy”。随后等待 stopped 后启动成功。因此不能将 stop 命令返回当成关机已经完成。

## ISP

| 阶段 | official | custom |
|---|---|---|
| 两台重启完成 | 10001 / 9.249.113.0 | 10002 / 9.249.113.1 |
| Launchpad 点击 custom 一键换 IP | 复测仍为 9.249.113.0 | 10003 / 9.249.113.10 |
| Launchpad 点击 official 一键换 IP | 10002 / 9.249.113.1 | 复测仍为 9.249.113.10 |

均为 guest api.ipify.org HTTPS 实测；其它机器没有被一键操作改动。当前有限端点池会复用已空闲的端口，不保证历史 IP 不重复。本次不下载 IPA、不浏览 Feed/视频；未重新做 Instagram 全业务验证。两台最后保留运行，新版 Launchpad 留在 official ISP 窗口。

私有证据目录 `.local/launchpad-restart-20261022/`：两次 stopped 的机器清单、start 返回、guest 探测、最终主机状态、授权通过及两台换 IP 截图。launchpad-cli exec 的子命令数据流在 stderr，stdout 是 bundle/status 包装，采集需分别重定向。
