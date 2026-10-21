# Decodo 本机凭据

本机独立文件：仓库根目录 `.local/decodo.json`，权限 `0600`，由 `.gitignore` 排除。Git 只保存 [配置模板](decodo.example.json) 和此说明；真实用户名、密码不要放入提交或日志。

## 使用现有界面

当前 Workstation **不会自动读取这个 JSON 文件**。它是本机凭据备份，不是已接入的配置导入功能。

1. 使用仓库根目录的 `workstation.command` 打开新版 Workstation，使其加载本机固定 CLI 和实例库设置。
2. 启动目标实例，在实例详情的“代理出口 · Clash Verge → Decodo · 美国”点击“配置账号”。
3. 将本机 JSON 的 `username`、`password`、`zip` 分别填写到代理用户名、代理密码、美国 ZIP 字段。测试 ZIP 为 `10001`。
4. 点击“保存、应用并检测”。这会把认证信息写入本机 Clash 私有配置，申请该 VM 的独立五分钟 IP Lock 会话，并检测 guest 公网出口。
5. 后续点击“换新 IP 并检测”即可；不需要重新填写密码。第二台 VM 使用同一账户分别配置，程序为它生成不同会话。

修改独立 JSON 文件不会更新已经生效的 Clash 节点。账号或密码改变时，需要在各实例“修改账号”中重新保存；旧会话凭据会被替换。

## 迁移与验证

新电脑可从模板复制为 `.local/decodo.json`，填写自己的代理凭据，并将文件权限设为 `0600`。真实文件通过本机受控方式单独保存，Git 克隆不包含它。

```sh
git check-ignore -v -- .local/decodo.json
git ls-files -- .local/decodo.json
```

第一条应显示忽略规则，第二条应无输出。不要使用 `git add -f` 强制加入凭据。

流量、共享策略组限制和实网验收边界见 [Workstation 网络说明](workstation-network.md#decodo-美国-zip-与五分钟会话)。
