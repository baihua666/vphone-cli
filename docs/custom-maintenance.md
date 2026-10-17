# 定制分支维护

- `upstream`：原作者 `https://github.com/zqxwce/vphone-ws.git`。
- `origin`：个人 fork `git@github.com:baihua666/vphone-ws.git`。
- `main`：上游基线；`tb_dev`：定制代码和回归测试。

日常修改在定制分支完成，执行 `swift test` 后提交并推送。
构建 GUI 使用 `./scripts/bundle.sh`，产物为 `.build/vphone-ws.app`。
构建与发布到运行环境分开：本次提交/推送不替换正在使用的 GUI 或 CLI。

同步上游时先保证工作区干净：

```sh
git fetch upstream
git switch main
git merge --ff-only upstream/main
git switch tb_dev
git merge main
swift test
```

解决冲突并通过测试后，才构建和验证 GUI；最后 `git push origin tb_dev`。
上游接口变更需核对实际绑定的 CLI 版本，不自动升级既有实例。

## 当前定制范围

- 实例 sidecar `.vphone-ws.json` 可指定 `executablePath` 和可选 `variant`；
  旧版实例可传 variant，新版实例可省略。修改 variant 时保留宿主路径。
- 目录链接解析为真实启动、窗口查找和导出路径；详情显示真实目录。
- 停机向匹配 config 路径的 VM 宿主发 SIGINT，并等待磁盘释放，不强杀 XPC。
- 运行中的实例禁用 Export；宿主检查采用实际配置的 CLI 路径。

VM 磁盘、实例 sidecar、本机启动入口、CLI 运行产物与凭据不纳入此仓库。
本机通过相邻 vphone-cli 仓库的 `workstation.command` 传入运行路径；保留其现有配置。
测试通过不等于已验证所有 CLI 版本，也不等于完成真实停机归档及恢复验证。
