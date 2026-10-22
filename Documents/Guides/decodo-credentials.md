# Decodo 本机凭据

主入口现为本仓库扩展的 Launchpad，读取 `~/.vphone/decodo.json` 或表单指定路径；流程见 [Launchpad Decodo](launchpad-decodo.md)。下文为保留的 Workstation 备用入口，不代表官方发行版已自带该功能。

本机独立文件：仓库根目录 `.local/decodo.json`，权限 `0600`，由 `.gitignore` 排除。Git 只保存 [配置模板](decodo.example.json) 和此说明；真实用户名、密码不要放入提交或日志。

## 使用现有界面

通过 `workstation.command` 启动的新版 Workstation 会读取此 JSON 文件。启动入口只传入 `VPHONE_DECODO_CONFIG` 文件路径，账号密码不会出现在启动参数中；可用该环境变量指定另一个绝对路径。

1. 使用仓库根目录的 `workstation.command` 打开新版 Workstation，使其加载本机固定 CLI 和实例库设置。
2. 启动目标实例，在实例详情的“代理出口 · Clash Verge → Decodo · 美国”点击“配置账号”。
3. 打开配置表单后，会显示“已读取本机配置”，并自动填入 `username`、`password` 和默认 `zip`（测试为 `10001`）。已有实例 ZIP 优先保留，可直接修改；密码保持遮蔽。文件缺失、格式错误或权限过宽会提示原因，仍可手动填写。
4. 点击“保存、应用并检测”。这会把认证信息写入本机 Clash 私有配置，申请该 VM 的独立五分钟 IP Lock 会话，并检测 guest 公网出口。
5. 后续点击“换新 IP 并检测”即可；不需要重新填写密码。第二台 VM 使用同一账户分别配置，程序为它生成不同会话。

修改独立 JSON 文件不会立即更新已经生效的 Clash 节点。账号或密码改变时，重新打开各实例“修改账号”，界面会重新读取文件，再点击保存使其生效；旧会话凭据会被替换。读取文件和打开表单本身不联网、不申请新会话。

## 迁移与验证

新电脑可从模板复制为 `.local/decodo.json`，填写自己的代理凭据，并将文件权限设为 `0600`。真实文件通过本机受控方式单独保存，Git 克隆不包含它。

```sh
git check-ignore -v -- .local/decodo.json
git ls-files -- .local/decodo.json
```

第一条应显示忽略规则，第二条应无输出。不要使用 `git add -f` 强制加入凭据。

流量、共享策略组限制和实网验收边界见 [Workstation 网络说明](workstation-network.md#decodo-美国-zip-与五分钟会话)。

## 本机网关连接

2026-10-21 实测发现本机 Clash 的节点 DNS 指向自身 fake-IP DNS，且直连 Decodo 网关间歇超时。本机已在当前订阅合并配置中为 `gate.decodo.com` 设置真实 DNS 解析，并在两个 Decodo 节点中配置现有日本订阅节点为 `dialer-proxy`。实际链路为 VM → Clash → 订阅中转 → Decodo → 目标网站，最终出口仍是 Decodo 分配的 IP。

“换新 IP”和“修改账号”会保留已有中转字段。中转节点配置属于 Clash；迁移电脑或订阅节点改名时需要重新核对，当前表单不提供中转选择器。五分钟是供应商的会话参数，不是本程序的定时器；随机重复 IP 可再次手动换新，不能保证每次都不同。

实测记录见 [两台 VM 独立出口验收](../../research/Host/decodo_live_validation_20261021.md)。
