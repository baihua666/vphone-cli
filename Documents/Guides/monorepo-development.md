# GUI + CLI 共同开发

跨层职责、VPN 配置归属、接口契约和 CodeGraph 使用以 [架构与维护边界](architecture-boundaries.md) 为准。

本仓库是主开发仓库，统一在 `tb_dev` 开发。用户入口为 Workstation GUI；GUI 通过进程调用原生 CLI，CLI 负责实例、恢复、固件与 guest 接口。保留两个项目各自的构建工具，不复制底层逻辑进 GUI。

## 布局与职责

| 目录 | 职责 |
| --- | --- |
| `VPhoneWorkstation/` | 从 vphone-ws 迁入的 SwiftUI GUI、CLI 适配与测试，保留原 SwiftPM 构建 |
| `VPhoneExecutable/` | 原生 CLI、VM 宿主、固件、恢复与权限工具 |
| `VPhoneKit/` | 原生公共组件 |
| `VPhoneDaemon/`、`VPhoneGuestComponents/` | 客体服务和系统组件 |
| `VPhoneLaunchpad/` | 上游自带应用，保留以便同步；本 fork 当前产品入口仍为 Workstation |
| `scripts/dev.sh` | 统一构建、测试与开发启动入口 |

CLI 的 Xcode 工程及根目录布局保持不变。GUI 源码直接纳入同一个 Git 仓库，不是 submodule，也没有嵌套 `.git`。原 vphone-ws 提交历史作为导入合并的第二父历史保留，迁入基线为 `7ab3fdb`。旧相邻 vphone-ws 仓库与远端 fork 保留作历史参考，不再作为日常编辑位置。

## 日常开发

```sh
./scripts/dev.sh test gui
./scripts/dev.sh build gui
./scripts/dev.sh test cli
./scripts/dev.sh build cli
# 或使用 build all / test all
```

`test cli` 运行 `VPhoneCoreKitTests`，不是整个 CLI 测试全集。改动签名、归档、固件或恢复时，另外运行其所属 Xcode 测试 scheme。CLI 完整构建包含 bundle admission 验证。GUI 现有 SwiftPM app target 只在 `VPhoneWorkstation` 内保留，不把 CLI 改成 SwiftPM app。

- `./scripts/dev.sh run` / `./workstation.command`：运行 monorepo 的 GUI，沿用本机已配置的固定宿主和实例库。
- `./scripts/dev.sh run-dev`：使用本仓库刚构建的 GUI + CLI，默认实例库 `~/.vphone/development-machines`，不复制或迁移任何现有实例。可用 `VPHONE_DEV_LIBRARY_ROOT` 显式选择开发库。须先退出已有管理器，以免 macOS 复用进程而忽略新环境变量。
- 开发库内如有 `.vphone-ws.json` 的 `executablePath`，仍按显式固定宿主启动；需要测试本次 CLI 时，必须有意识地检查这个设置，不把 UI 中全局路径当作实际宿主证明。

现有两台实例及其宿主路径还参与 Mac 网络分流。构建不会部署、重签、替换库外固定宿主，也不会修改实例 sidecar、网络配置或固件。启用新的宿主版本需要单独做兼容与运行验收。

## 接口共同开发

界面和 CLI 功能可在同一提交中修改，但保持 `GUI → CLI → VM/guest` 的依赖方向。GUI 解析 CLI 输出的变更需同时覆盖适配层测试；不得用 UI 自行重写固件、恢复、签名或 IPA 安装逻辑。

当前 Workstation 已验证已有 2.x 实例的发现/启停/窗口切换。**新建向导仍带旧版 variant/create 参数，完整 2.x GUI 新建、固件制作及 IPA 管理闭环尚待单独实现。** monorepo 迁移不代表这些功能已完成，也不改变当前公开 JB 模式或恢复旧 EXP 参数。

## 持续同步两个上游

远端职责：

- `origin` → `baihua666/vphone-cli`，发布 monorepo 的 `tb_dev`。
- `upstream` → `Lakr233/vphone-cli`，CLI 上游；`main` 只维护其基线。
- `workstation-upstream` → `zqxwce/vphone-ws`，GUI 上游。
- `workstation-fork` → `baihua666/vphone-ws`，仅保留原定制来源。

每次先提交当前工作，确认工作区干净；分别同步并解决冲突，不强制覆盖：

```sh
# CLI：正常合并，不调整上游目录
 git fetch upstream
 git switch main
 git merge --ff-only upstream/main
 git switch tb_dev
 git merge main

# GUI：按子目录合并，保留历史，不直接 merge 到仓库根目录
 git subtree pull --prefix=VPhoneWorkstation workstation-upstream main

./scripts/dev.sh test all
./scripts/dev.sh build all
git push origin tb_dev
```

以上命令需按阶段执行并检查成功，不在失败后继续。合并后核对 GUI/CLI 参数和 schema 兼容性，再决定运行部署。旧 CLI `tb_dev` 指针已保留为本地 `archive/tb_dev-before-monorepo-20261017`；现有业务工作也仍保留在 `codex/business-vm`。

## CI 与产物

根目录 `.github/workflows/build.yml` 在 `main` / `tb_dev` push 及 PR 上验证原生 bundle 和 Workstation 测试/构建。迁入目录内的 `.github` 只保留上游历史，GitHub 不会执行该嵌套目录的 workflow。

CLI 产物：`.build/XcodeBundle/Build/Products/Debug/VPhone.bundle`。
GUI 产物：`VPhoneWorkstation/.build/vphone-ws.app`。
它们仍是两个产物，由 GUI 调用 CLI；本次没有新增统一安装器、自动升级或发布工作流。VM、IPSW、API token、个人运行配置和构建缓存不入库。

新克隆只有 `origin` 时，先补齐只读同步来源：

```sh
git remote add upstream https://github.com/Lakr233/vphone-cli.git
git remote add workstation-upstream https://github.com/zqxwce/vphone-ws.git
git fetch upstream
# 若本地 main 尚不存在：
git branch --track main upstream/main
```

无需克隆相邻 vphone-ws，也无需复制它的 `.build`。本机 `workstation.command` 是已配置实例的便捷入口；新机器请先用 `build all`，再 `run-dev`，按正式 host setup 和原生 CLI 创建开发实例。

## 本次迁入验证（2026-10-17）

- `scripts/dev.sh test gui`：64 项通过。
- `scripts/dev.sh test cli`：CoreKit 409 项、50 suites 通过。
- `scripts/dev.sh build gui` 与 `build cli`：均成功，CLI 完整 bundle 构建检查通过。
- `scripts/dev.sh run`：实际运行进程位于本仓库 `VPhoneWorkstation/.build`，GUI 显示 Host ready，并列出 official/custom 两台现有 2.x 实例。未重建或更换固定运行宿主。
- 验证基于当前工作区；原来未提交的 guest 解锁修改、研究记录与测试仍由原任务维护，没有混入 monorepo 整合提交。未声称远端提交包含这些本机既有修改，也未重新进行固件恢复或完整归档测试。
