# 跨 Mac 部署与 Workstation 备用

完整最新步骤以 [Launchpad 跨 Mac 部署指南](../../../Documents/Guides/launchpad-mac-setup.md) 为准；包含应用管理、FLYWHEEL、签名与本机凭据配置。下文保留代理及备用入口注意事项。

## 同步代码与 Skill

在目标 Mac 的本项目 checkout 拉取包含本次修改的业务分支。先检查工作区；已有修改时不要 reset/clean。整个 monorepo 必须一起拉取：Launchpad 通过本地 Swift package 依赖 `VPhoneWorkstation` 的 `VPhoneWSCore`，不能只复制 Launchpad 目录。依赖版本由 Package.resolved 固定。

在 checkout 中直接让 Codex 读取 `Skills/vphone-management/SKILL.md` 即可使用。需要自动发现时，先确认目标不存在，再执行（在仓库根目录）：

```sh
mkdir -p "$HOME/.codex/skills"
ln -s "$PWD/Skills/vphone-management" "$HOME/.codex/skills/vphone-management"
```

存在同名 Skill 时核对其来源；不要覆盖不相关内容。Skill 随 checkout 更新。不要同步本机 `.local/`、`.build/`、VM 磁盘、Clash 私有文件或签名配置。

## 构建和签名

```sh
./scripts/dev.sh test launchpad
./scripts/dev.sh build launchpad
```

产物在 `.build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app`。这不会安装或重启任何应用。`test launchpad` 运行共享代理/CLI 回归测试；Xcode build 校验实际 Launchpad UI 集成。

**本地编译版不是官方公证发行版。** 不可用 ad-hoc 重签官方 app 后声称原 Helper 仍可用。对外分发使用 Developer ID；仅本机使用可按 `VPhoneLaunchpad/Build/SignLaunchpad.sh` 使用有效 Apple Development 证书。实际校验要求是 Apple 签名链、应用标识和团队 ID，并未限定 Developer ID 类型。必须以所选证书的同一开发团队构建 app 与 Helper 的互信要求（本机 gitignored `VPhoneLaunchpad/Configuration/Developer.xcconfig` 中配置 `VPHONE_LAUNCHPAD_TEAM`）。团队标识、私钥和证书不要提交。跨 Mac 分发需要正常签名/公证流程；没有签名条件时保留官方 app 与 Workstation，不绕过 Helper 的客户端校验。

用户允许维护窗口后才退出旧管理器、保留原 app、安装新 app；由用户完成 macOS 开发者工具权限和 Helper 管理员认证。不要让两个相同 bundle ID 的管理器同时运行。原虚拟机磁盘可继续保留，禁止用重建替代接入。

## 核心 Bundle 与代理

1. 使用 Launchpad 的核心 Bundle 安装入口或 `vphone-launchpad-cli bundle install-local`。同一份程序的相同 seal 会得到同一个 store 版本。
2. 现有机器原地加入资料库，核对每机 `launchpad.json`。导入目录不等于需要 import/export 大磁盘。不要调用 `vm create` 或 `--update-environment` 来接入现有机器。
3. 要按 PROCESS-PATH 保留独立出口，需要两份独立已安装 runtime。只有明确授权才制作独立副本；保留内部可执行程序/guest 资源，外层资源标识改变后重新签署，并通过正常 install-local 安装。保存原绑定供回退。
4. 新路径以安装结果为准，在当前 Clash 订阅的规则扩展中为每台 VM 指向其出口；运行配置重载后核对相同规则。路径可能带空格，必须使用正确 YAML 标量，不能按空格拆命令或直接套旧机路径。
5. 保持当前订阅的其它节点、规则、DNS 和中转字段。没有对应唯一进程规则或代理扩展时，界面会拒绝操作；先在 Clash 中配置。不要通过临时全局切节点假装完成实例分流。
6. 凭据文件模板位于 `Documents/Guides/decodo.example.json`。在本机创建 `~/.vphone/decodo.json`，填写真实账号后 `chmod 600`。迁移密码需用户另行指定安全渠道；Git 不提供它。
7. 验收两机启动、原应用存在、两个 guest HTTPS 出口，以及只换一台时另一台配置不变。流量不足/认证错误时明确未通过，不擅自购买。

## Workstation 备用

- 保留源码 `VPhoneWorkstation/` 和 `workstation.command`，备用 build：`./scripts/dev.sh build gui`。在没有运行中的 Workstation 开发构建时执行，避免覆盖其它会话使用的产物。
- Launchpad 的权威绑定是 `launchpad.json`；Workstation 的权威绑定是 `.vphone-ws.json`。使用备用前核对后者的 executablePath 与 Launchpad 绑定的完整 CLI 一致；不要让备用客户端悄悄使用旧路径。检查整个资料库的独立路径及 Clash 规则。
- `workstation.command` 是仓库开发启动入口，读取目标 Mac 自己的 `~/.vphone/host-config.zsh`。不能照抄其它机器的用户名/目录。`VPHONE_CLI_PATH` 指完整可执行 CLI，`VPHONE_LIBRARY_ROOT` 指实际机器库。
- 现有账号、会话及节点由两个 UI 共用；备用无需重新购买或清空配置。同一时间只让一个管理器修改代理和生命周期。
- 回退 app/运行时前正常停止受影响机器并核对操作者许可；只恢复本次更改的绑定和对应路径规则，不整体覆盖用户后来更新的 Clash 文件。
