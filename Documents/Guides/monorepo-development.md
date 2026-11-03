# GUI + CLI 共同开发

Launchpad 首次安装或跨 Mac 更新请先读 [部署指南](launchpad-mac-setup.md)，近期功能见 [更新摘要](launchpad-updates-20261023.md)。

跨层职责、VPN 配置归属、接口契约和 CodeGraph 使用以 [架构与维护边界](architecture-boundaries.md) 为准。FLYWHEEL 关联工程、业务代码归属和升级检查见 [FLYWHEEL 与 Launchpad 接入边界](flywheel-integration.md)。

本仓库是主开发仓库，统一在 `tb_dev` 开发。Launchpad 为统一管理主入口，Workstation 保留为备用；管理 GUI 通过原生 CLI 执行实例、恢复、固件与 guest 操作。保留现有构建工具，不复制底层逻辑进 GUI。下述 `scripts/dev.sh` 的 `gui` 仍特指 Workstation，不代表 Launchpad 的构建或部署入口。

## 布局与职责

| 目录 | 职责 |
| --- | --- |
| `VPhoneWorkstation/` | 从 vphone-ws 迁入的 SwiftUI GUI、CLI 适配与测试，保留原 SwiftPM 构建 |
| `VPhoneExecutable/` | 原生 CLI、VM 宿主、固件、恢复与权限工具 |
| `VPhoneKit/` | 原生公共组件 |
| `VPhoneDaemon/`、`VPhoneGuestComponents/` | 客体服务和系统组件 |
| `VPhoneLaunchpad/` | 原生管理主入口；FLYWHEEL 接入仅在此保留界面组装与实例适配，主体业务代码独立维护 |
| `scripts/dev.sh` | 统一构建、测试与开发启动入口 |

CLI 的 Xcode 工程及根目录布局保持不变。GUI 源码直接纳入同一个 Git 仓库，不是 submodule，也没有嵌套 `.git`。原 vphone-ws 提交历史作为导入合并的第二父历史保留，迁入基线为 `7ab3fdb`。旧相邻 vphone-ws 仓库与远端 fork 保留作历史参考，不再作为日常编辑位置。

## 日常开发

产品版本号表示实际合入的官方代码基线，本地开发不得更改；本地构建必须保留官方 `-local.<内容哈希>` 身份机制。`test`、时间与用户发布确认只能作为附加信息，不能替代哈希；AI 自行构建默认作为测试产物，不能自行转为发布。完整约束见根 [AGENTS.md 的官方基线版本与本地标识](../../AGENTS.md#官方基线版本与本地标识)。Launchpad 核心包列表及新建/更换核心包菜单将本地与 CI 构建默认展示为 `test`；官方发行版不加标签，检查通过或设为默认也不会去掉标签。当前没有用户发布确认的持久化记录或提升为发布版的操作，不根据 `local` 推断是谁构建。机器可解析的版本、安装目录、receipt 和实例绑定保持原格式，未往版本字符串自动追加 `test` 或时间。

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

## 远端仓库与跨 PC 配置

2026-11-03 起，日常开发与跨 PC 同步以独立私有仓库为准。远端名称与地址统一如下；已有公开 Fork 及官方上游继续保留：

| 远端 | URL | 职责 |
| --- | --- | --- |
| `private` | `git@github.com:baihua666/vphone-cli-private.git` | 私有开发与跨 PC 同步；默认推送目标，默认分支 `tb_dev` |
| `origin` | `git@github.com:baihua666/vphone-cli.git` | 公开 Fork；仅按明确授权同步可公开内容或维护发行 |
| `upstream` | `https://github.com/Lakr233/vphone-cli.git` | 官方 CLI 来源；本地 `main` 跟踪 `upstream/main` |
| `workstation-upstream` | `https://github.com/zqxwce/vphone-ws.git` | Workstation subtree 上游 |
| `workstation-fork` | `git@github.com:baihua666/vphone-ws.git` | 原 Workstation 定制来源，保留历史参考 |

### 已有公开 Fork 克隆的 PC

先检查工作区与远端。保留未提交工作和本地分支，不重新克隆覆盖工作目录：

```sh
git status --short --branch
git remote -v
# 仅在尚无 private 远端时添加；已存在则先核对 URL，不盲目覆盖。
git remote add private git@github.com:baihua666/vphone-cli-private.git
git fetch private
git config --local remote.pushDefault private
git config --local branch.tb_dev.pushRemote private
git branch --set-upstream-to=private/tb_dev tb_dev
```

上述命令逐步执行；尚无本地 `tb_dev` 时，用 `git switch --track -c tb_dev private/tb_dev` 创建，再设置跟踪关系。私有访问失败时检查当前 GitHub 账号、SSH key 和仓库权限，不回退推送公开 Fork。

### 新 PC 首次克隆

显式使用 `--origin private`，避免将私有仓库误命名为约定中的公开 `origin`：

```sh
git clone --origin private --branch tb_dev git@github.com:baihua666/vphone-cli-private.git vphone-cli
cd vphone-cli
git remote add origin git@github.com:baihua666/vphone-cli.git
git remote add upstream https://github.com/Lakr233/vphone-cli.git
git remote add workstation-upstream https://github.com/zqxwce/vphone-ws.git
git remote add workstation-fork git@github.com:baihua666/vphone-ws.git
git config --local remote.pushDefault private
git config --local branch.tb_dev.pushRemote private
```

不需要克隆相邻 GUI 仓库。构建、签名、安装、账号和实例接入继续按 [部署指南](launchpad-mac-setup.md) 操作。

### 每台 PC 的配置验收

Git 远端、跟踪分支及 `.git/config` 不会随提交或 pull 自动复制；从公开仓库拉到本文后，仍须在该 PC 执行配置。每个独立 clone 都要配置；同一仓库的 linked worktree 通常共享仓库级设置。

```sh
git switch tb_dev
git remote -v
git config --get remote.pushDefault
git config --get-regexp '^branch\..*\.pushRemote$'
git rev-parse --abbrev-ref '@{upstream}'
git rev-parse --abbrev-ref '@{push}'
git push --dry-run --porcelain
```

默认远端应为 `private`，`tb_dev` 的 upstream 与 push 都应为 `private/tb_dev`，dry-run 的目标应为私有仓库。其它开发分支若已有 `branch.<name>.pushRemote`，会覆盖 `remote.pushDefault`，须逐项核对并改为 `private`；不要修改 `main` 从 `upstream/main` 拉取官方基线的职责。Git 配置优先级见 [Git 官方说明](https://github.com/git/git/blob/master/Documentation/config/remote.adoc)。

### 公开同步边界

“提交 / push / 同步代码”默认仅推私有仓库。公开 Fork 只接收用户明确授权公开的内容；本次规范同步两个仓库是单次授权，不表示后续业务代码自动双推。私有仓库访问失败或公开分支缺少业务提交，都不是改推公开仓库的理由。

公开推送前核对全部待推送提交和文件差异，不能只看最后一个提交。若开发分支已经含未公开内容，从公开基线另建分支并 cherry-pick 已核对的公开提交，不能整体 merge 私有分支。禁用 `push --mirror`、`push --all` 及同一远端多个 push URL 的自动双推做法；普通同步不删除或改写公开历史，也不复制 Release 附件。已公开的历史不会因新建私有仓库而变为私有。

## 多台 Mac 仅同步源码

多台 Mac 通过 `private/tb_dev` 同步代码、测试、工程与依赖锁文件、通用脚本、使用文档和技能。每台 Mac 自己构建、创建和管理实例；镜像、IPSW、IPA、固定宿主、归档、日志、令牌和本机运行配置不同步、不进 Git。构建产物在各机器本地生成。私有仓库同样遵守镜像及分片禁止上传的要求。

通用说明放在 `Documents/Guides/`；研究结论在 `Research/` 记录版本、复现方法和验证范围。本机路径、实例清单和代理节点留在仓库外，不把一台机器的运行状态当作其他机器的前置条件。不要仅为同步文档复制原始日志或含凭据的现场响应。

### 本机启动配置

`start.sh` 和 `workstation.command` 默认读取仓库外的 `~/.vphone/host-config.zsh`；可用 `VPHONE_HOST_CONFIG` 指向另一个本地文件。它是会被执行的 zsh 配置，只使用自己维护的文件。新机器自行创建，已有配置按需编辑，不直接覆盖。示例（路径和实例名须替换为本机实际值）：

```zsh
# ~/.vphone/host-config.zsh — 不提交，不复制到其他 Mac
: ${VPHONE_CLI_PATH:="$HOME/.vphone/runtimes/my-build/VPhone.bundle/Contents/MacOS/vphone-cli"}
: ${VPHONE_LIBRARY_ROOT:="$HOME/.vphone/machines"}
: ${VPHONE_OFFICIAL_NAME:=my-research-phone}
: ${VPHONE_CUSTOM_NAME:=my-test-phone}
# 两个别名需要不同宿主时，再设置 VPHONE_OFFICIAL_CLI / VPHONE_CUSTOM_CLI。
```

上述写法让已设置的环境变量优先；自行编写配置时也应保留这个约定。`start.sh official|1` 与 `custom|2` 使用对应别名和宿主，别名宿主未配置时使用 `VPHONE_CLI_PATH`。不提供宿主时明确报错，不自动选用新构建替换固定版本。`workstation.command` 使用仓库内 GUI 和本机的 CLI/实例库；实例 sidecar 的固定宿主仍由现有 GUI 解析。

已有管理器运行时，macOS 可能复用原进程，修改配置不会立即改变它。不要为更新源码停止 VM；需要应用新管理器配置时，在合适时机退出管理器再打开。不要覆盖运行中的固定 bundle，也不要修改现有实例 sidecar 或代理路径规则。`run-dev` 继续使用独立开发库，不读取这份正式启动配置。

### 忽略规则与提交

所有 Mac 都要排除的运行数据放根 `.gitignore`；仅某台机器的临时文件放 `.git/info/exclude`，后者不会随 clone 同步。镜像和固定宿主优先保存在仓库外。新建大文件前用 `git check-ignore -v -- <目标文件>` 核对；用 `git ls-files -- <目标路径>` 排查是否已跟踪。忽略规则不影响已跟踪文件，也不能阻止 `git add -f`，不能把它当强制上传拦截。不要忽略全部 JSON、plist 或数据库后缀，以免隐藏工程和测试资源。

首次获取按上方“新 PC 首次克隆”配置远端后，再在本机构建：

```sh
./scripts/dev.sh build launchpad
# 签名、安装、账号与实例接入继续按部署指南操作。
```

每次换 Mac 工作先检查工作区，再更新。存在未完成修改时先整理，不能直接覆盖：

```sh
git status --short
git switch tb_dev
git pull --ff-only private tb_dev
```

完成一个改动后，代码、对应测试和文档一起提交；独立改动分开。选择具体文件或使用 `git add -p`，新增文件单独添加，避免将无关现场文件一起暂存：

```sh
git add -p
# git add -- 本次新增的具体文件
git diff --cached --stat
git diff --cached --check
git diff --cached
# 按变更范围运行所属测试和构建；仅脚本/同步规范变更：
zsh scripts/tests/source-sync-tests.zsh
git commit -m "Describe the complete change"
git push
```

`push` 只上传提交历史，不上传未提交文件或仓库外配置。两台机器都产生新提交时，`pull --ff-only` 会拒绝分叉；先检查双方提交，正常合并、解决冲突并验证，再 push，不强推覆盖。镜像永远不参与这条同步路径，也不因 pull 自动创建、迁移或启动。

## 接口共同开发

界面和 CLI 功能可在同一提交中修改，但保持 `GUI → CLI → VM/guest` 的依赖方向。GUI 解析 CLI 输出的变更需同时覆盖适配层测试；不得用 UI 自行重写固件、恢复、签名或 IPA 安装逻辑。

当前 Workstation 已验证已有 2.x 实例的发现/启停/窗口切换。**新建向导仍带旧版 variant/create 参数，完整 2.x GUI 新建、固件制作及 IPA 管理闭环尚待单独实现。** monorepo 迁移不代表这些功能已完成，也不改变当前公开 JB 模式或恢复旧 EXP 参数。

## 持续同步两个上游

远端地址与默认推送规则见上方“远端仓库与跨 PC 配置”。`main` 只维护官方 CLI 基线；Workstation 按子目录同步，合并后的开发代码推送到 `private`。

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
git push private tb_dev
```

以上命令需按阶段执行并检查成功，不在失败后继续。合并后核对 GUI/CLI 参数和 schema 兼容性，再决定运行部署。旧 CLI `tb_dev` 指针已保留为本地 `archive/tb_dev-before-monorepo-20261017`；现有业务工作也仍保留在 `codex/business-vm`。

## CI 与产物

根目录 `.github/workflows/build.yml` 在 `main` / `tb_dev` push 及 PR 上验证启动配置/忽略规则、原生 bundle 和 Workstation 测试/构建。迁入目录内的 `.github` 只保留上游历史，GitHub 不会执行该嵌套目录的 workflow。

CLI 产物：`.build/XcodeBundle/Build/Products/Debug/VPhone.bundle`。
GUI 产物：`VPhoneWorkstation/.build/vphone-ws.app`。
它们仍是两个产物，由 GUI 调用 CLI；本次没有新增统一安装器、自动升级或发布工作流。VM、IPSW、API token、个人运行配置和构建缓存不入库。

按上方配置好远端后，若本地 `main` 尚不存在，再建立官方跟踪分支：

```sh
git fetch upstream
# 若本地 main 尚不存在：
git branch --track main upstream/main
```

无需克隆相邻 vphone-ws，也无需复制它的 `.build`。本机 `workstation.command` 是已配置实例的便捷入口；新机器以 Launchpad 部署指南为主；只有测试备用 Workstation 时才使用 `build all` / `run-dev`，按正式 host setup 创建独立开发实例。

## 本次迁入验证（2026-10-17）

- `scripts/dev.sh test gui`：64 项通过。
- `scripts/dev.sh test cli`：CoreKit 409 项、50 suites 通过。
- `scripts/dev.sh build gui` 与 `build cli`：均成功，CLI 完整 bundle 构建检查通过。
- `scripts/dev.sh run`：实际运行进程位于本仓库 `VPhoneWorkstation/.build`，GUI 显示 Host ready，并列出 official/custom 两台现有 2.x 实例。未重建或更换固定运行宿主。
- 验证基于当前工作区；原来未提交的 guest 解锁修改、研究记录与测试仍由原任务维护，没有混入 monorepo 整合提交。未声称远端提交包含这些本机既有修改，也未重新进行固件恢复或完整归档测试。
