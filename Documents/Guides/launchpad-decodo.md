# Launchpad 的 Decodo 管理

本仓库扩展的 Launchpad 在机器检查器中提供「代理出口 → Decodo 配置与换 IP」，使用原生 Form。可读取本机凭据、选择美国 ZIP、保存独立五分钟 IP Lock 会话、一键申请新会话并从 guest 检测 HTTPS 公网 IPv4。官方上游公证版不包含该业务界面。

共享服务来自现有 `VPhoneWSCore` Swift package；Launchpad 不启动 Workstation，也没有第二套代理写入逻辑。Launchpad 的代理与检测命令解析 `launchpad.json`，不会被旧 `.vphone-ws.json` 覆盖；同一运行路径在所有已登记资料库中的重复绑定会被拒绝。Workstation 保留原绑定解析作为备用。

凭据默认读取 `~/.vphone/decodo.json`，权限为 0600；也可在表单指定绝对路径或通过 `VPHONE_DECODO_CONFIG` 覆盖。已有会话换新直接复用 Clash 节点凭据，不需要再次填写密码。表单不会保存独立凭据文件，保存动作写入原有 Clash 私有节点。

前提是已有 Clash Rule/TUN/strict 配置、对应实例的唯一 PROCESS-PATH 规则及代理扩展，且运行中网络为 tunnel。当前版本不自动安装 Clash、购买流量、建立新路径规则或复制 runtime。切换 Bundle 后应在维护窗口重启并核对实际路径再使用代理功能。

「配置已生效」与「guest 检测成功」分别报告。认证/流量问题可能导致规则正确但无法联网。仅验证 guest HTTPS/TCP 出口；不承诺 UDP、全部 App 或 ZIP 的街道精度。五分钟由供应商处理，不是 UI 自动轮换计时器。

## 验证和部署

- `./scripts/dev.sh test launchpad`：共享核心测试，覆盖 Launchpad 绑定优先级、跨库共用路径拒绝、绑定变化、配置读取无写入、配置与轮换、非 tunnel 拒绝及检测失败状态。
- `./scripts/dev.sh build launchpad`：实际 Xcode UI 集成构建；产物位于 `.build/LaunchpadDecodo/Build/Products/Debug/`。
- 2026-10-22 本次只修改源码并构建测试，**没有替换 /Applications app、启停 VM、修改实际代理或凭据文件**。另一会话正在操作现有两台机器，真实新 UI 验收留待维护窗口；不能复用旧 Workstation 的实测结果当新界面验收。
- 自定义 app 需要正确 Developer ID 和 Helper 互信配置，源码构建不继承官方签名。不要直接覆盖正在使用的官方 app。

其他 Mac 的安装、签名、接入、验收及 Workstation 备用步骤统一见 [vphone-management Skill](../../Skills/vphone-management/SKILL.md)。真实凭据和机器数据不经 Git 同步。
