# Launchpad 下载分发与首次使用（第一版）

普通用户请阅读 [其它 Mac 内部安装与使用说明](launchpad-internal-user-guide.md)。本页面向开发与发布维护。

2026-10-24。目标是让其它 Mac 下载签名 App 后，在原生界面完成环境检查、Core 安装、镜像下载和创建启动，不需要安装 Git、Xcode 或命令行依赖。开发机器仍使用 Xcode。
本轮实现客户端及发布工具；用户另行提供干净模板，尚未发布真实镜像。

## 用户入口与版本行为

主窗口工具栏「版本与镜像」打开独立窗口，首次运行自动显示。窗口依次提供：

1. 主机准备：复用 Host Setup。需要实体 Apple Silicon Mac、macOS 15+；管理员认证与 Recovery 中的 Research Guests 设置仍由用户完成。
2. 检查更新：直接读取本项目 `baihua666/vphone-cli/releases/latest/download/launchpad-catalog.json`，无需 REST API 或 Token。GitHub latest 排除 draft/prerelease；再从清单声明的固定 tag 下载清单并核对一致。清单的可选 previousTags 提供最多 99 个历史发行版；发布者只列已发布的正式 tag。404 显示尚无可用目录，其它 HTTP/校验错误不冒充已是最新版本。
3. App：显示本地与最新发布修订，支持选择历史发行版本、下载并校验 DMG，在 Finder 中显示。第一版由用户正常停止实例、退出并备份旧 App 后安装；不自动替换正在运行的 App，也不自动停机。macOS Gatekeeper 继续负责执行准入。
4. Core：下载对应 ZIP，通过现有 local bundle 解析核对 seal 身份，再复用原 Helper 安装、policy/preflight。已有默认值和实例绑定保留；新环境使用已安装核心作为默认候选。缺权限时回到 Host Setup，不自动改变系统安全设置。
5. 镜像：选择模板、版本、新实例名；可仅下载或下载后导入启动。已校验分片跨进程保留，暂停后当前未完成分片重下，不是字节级续传。进度以已校验分片和合并字节显示。
6. 导入：在目标资料库同卷的私有临时目录调用已有 `vm import --name <随机模板名>`，再 `vm clone --new-identity`；源模板不启动。完成后将新目录移入资料库，不覆盖同名对象，写标准 Core 绑定并请求启动，最多等待 guest ping 120 秒。启动未确认时保留实例，可重试启动或从平台管理，不重复导入。

关闭窗口不会取消共享模型中的操作。下载可暂停；导入/Core 安装期间正常退出会被提示阻止。强制结束或断电仍可能留下 `.distribution-<UUID>` 临时目录，需要确认没有进程使用后手动清理；不能宣称导入具有跨进程事务恢复。

## 三种版本分开维护

| 对象 | 身份 | 更新规则 |
| --- | --- | --- |
| App | 官方基线 `CFBundleShortVersionString` + 独立 `VPhoneDistributionRevision` | revision 为正整数、发布时严格递增；本地开发默认 0，标为开发构建；不改变官方基线或 CFBundleVersion |
| Core | 原有 `2.8.0-local.<seal SHA-256 前 8 位>` | 按真实内容识别，不能按发布时间改身份；不会自动迁移现有机器 |
| 镜像 | 稳定 id + 显示 version + 递增 revision + 完整 SHA-256 | 只下载新模板并创建新实例，不原地覆盖用户磁盘 |

Release tag 例如 `launchpad-2.8.0-r1` 是分发标签，不是新的官方产品版本号。相同镜像 id/revision 不得替换内容；App revision 不得对应不同内容。仅更新镜像时可在新 Release 中复用完全相同的 App DMG 与 revision，无需重新构建 App。客户端拒绝有冲突的发行目录。
镜像安装记录独立保存于 `~/Library/Application Support/vphone-launchpad/Distribution/images.json`，不向 VM manifest 添加字段。
记录表示导入来源，不宣称它是当前 guest OS 版本或实时 VM 身份；改名/删除后历史路径仍保留，记录本身不提供任何 VM 操作。模板更新不会更新客体应用。

## 发布目录与完整性

源码包：`Integrations/Distribution`。App 和 publisher 共用 schema/校验规则。
发行清单通过固定 GitHub 仓库的 HTTPS 附件地址读取，限制 1 MiB，并核对 latest 与固定 tag 的清单相同。正常检查不调用 api.github.com，避免共享出口的匿名 REST 配额。附件缺失会在下载时报错，下载后按清单大小和 SHA-256 校验；不再依赖 REST 返回的 asset digest。
下载地址只能由固定仓库、已验证的 tag 和单个文件名组成，不从清单执行 shell 或任意 URL。
附件逐个校验大小和 SHA-256；分片流式合并后再校验完整 archive。哈希/合并使用 1 MiB 缓冲，不把大镜像读入内存。

缓存位于同一 Distribution 目录下的 `Downloads/`，内容哈希参与文件名。保留分片和完整归档便于再次创建；第一版不自动清理缓存。
下载预留分片＋合并文件空间，导入预留两倍 expandedBytes 和安全余量，不将 APFS 克隆一定共享空间当作容量保证。
信任根为固定 GitHub 仓库的 HTTPS 和 App 系统签名准入；不是独立离线签名目录体系。

## 发布步骤（开发机器）

### 1. 构建 App（内部版或公证版）

当前内部使用选择 **Apple Development 签名、不公证**，复用现有签名脚本和 Helper 互信要求，不接受 ad-hoc/无签名包。团队在本机 Developer.xcconfig 配置，或由 `VPHONE_LAUNCHPAD_TEAM` 环境变量传给打包脚本；不得提交真实团队配置。

```sh
zsh Integrations/Distribution/scripts/package-app.zsh --internal \
  1 'Apple Development: <现有有效身份>'
```

内部包位于 `.build/distribution-app-internalDevelopment-r1/`。发布 recipe 须增加 `"signing": "internalDevelopment"`，工具会将该标识写入 catalog，并与包内 `VPhoneDistributionSigning` 比对；模式不一致拒绝发布。旧目录缺少 signing 时仍按 notarized 处理，不能自动降级。检查更新与下载校验保持启用，界面显示未公证提示。

内部版仅跳过 stapler/spctl 公证准入检查，继续校验 Apple 签名、App 标识、Helper 的签名要求、版本与所有附件哈希。不修改 Helper 权限或 Core。内部签名不是访问控制：向公开 GitHub Release 上传仍会公开附件。

接收方下载后把 App 拖到 Applications；若 macOS 阻止打开，在系统设置「隐私与安全性」核对来源后选择「仍要打开」，不全局关闭 Gatekeeper。随后通过 Host Setup 安装／更新 Helper，在 macOS 弹窗中认证；接收方不需要签名私钥。组织策略可能禁止手动放行，需目标 Mac 实测。开发证书过期或撤销后需重新签名发布。现有 Mac 上已有 Helper 的升级通过不能替代干净 Mac 首装验收。

若以后改用公证分发，使用下面的原有模式：


在本机 gitignored `VPhoneLaunchpad/Configuration/Developer.xcconfig` 设置对应团队，钥匙串准备有效 **Developer ID Application** 证书和 `notarytool` profile。不要把密钥、团队私有配置或公证凭据加入仓库。

```sh
zsh Integrations/Distribution/scripts/package-app.zsh \
  1 'Developer ID Application: <有效身份>' '<notarytool钥匙串profile>'
```

脚本 Release 构建，将独立 revision 写入 Info.plist，调用既有签名脚本，生成带 Applications 快捷方式的 DMG，提交 Apple 公证并 staple/validate。
它不修改已安装 App、不启动 VM，也不创建 Core。相同输出目录已存在时拒绝覆盖。
Apple Development 只能使用上述内部模式；不以本机可运行代替其它 Mac 的分发验收。

### 2. 打包已批准的 Core

```sh
zsh Integrations/Distribution/scripts/package-core.zsh \
  /absolute/path/VPhone.bundle /absolute/new/core-output
```

脚本先验证签名，再以现有 seal 计算身份并压缩，不重签或重建 Core。新功能不要求修改底层。

### 3. 准备模板和发布参数

镜像完整操作及验收步骤见 [镜像发布流程](launchpad-image-release.md)。

复制 [recipe.example.json](../../Integrations/Distribution/recipe.example.json) 到本机私有工作目录，填写真实路径与上述 identity。
`images: []` 允许先发布 App/Core；客户端会明确显示尚无镜像，不能视为完整首次启动验收。
每个镜像条目为：

```json
{
  "id": "clean-ios",
  "version": "2026.10.24",
  "revision": 1,
  "title": "干净 iOS 模板",
  "archive": "/absolute/path/clean.tzst",
  "expandedBytes": 68719476736
}
```

数值仅表示 schema 示例，必须填写实际解压文件占用的保守上界，不照抄示例容量。
模板须在源 VM 正常停机后用已有 export 导出。发布前人工确认无账号、Cookie、代理凭据、业务数据和私有文件引用，验证新身份克隆及跨 Mac 启动。
新身份克隆仅按现有 CLI 清理机器标识/MAC/冲突网络设置，不意味着应用数据、SEP 或所有广告标识自动重置。用户现用 VM 不得直接作模板公开。

```sh
swift run --package-path Integrations/Distribution distribution-publisher \
  /absolute/private/recipe.json /absolute/new/release-output
```

工具按 signing 模式验证 App 公证/签名、App baseline/revision 和 Core seal；镜像每片 1 GiB，最后一片可更小；输出目录必须不存在。
生成 manifest 后只保留声明附件。失败输出不作为正式发行目录，排查后使用新目录。

### 4. 上传 Draft 与发布

在输出目录写 `release-notes.md`，记录实际源码 SHA、变更、验证范围、已知限制、Core 与模板来源。

```sh
zsh Integrations/Distribution/scripts/publish-release.zsh \
  /absolute/release-output <完整40位源码commitSHA>
```

脚本重新验证所有分片、整包、App 签名（公证模式另验公证）与 Core 身份；拒绝额外附件；用开发端 `gh` 上传 **draft** 至固定仓库。用户端不需要 gh。
已有同名 release 不覆盖。发布者核对第二台 Mac 的干净环境验收和公开分发内容后再显式发布；客户端忽略 draft/prerelease。
目录在最终整包齐备后发布，不将仍上传中的分片暴露为可安装版本。

## 编译开关与回退

`VPHONE_CUSTOM_DISTRIBUTION` 由 `VPhoneLaunchpad/Configuration/VPhoneLaunchpad.xcconfig` 的 `VPHONE_DISTRIBUTION` 默认开启。
构建时 `VPHONE_DISTRIBUTION=` 可关闭窗口、工具栏入口、首次引导、任务模型和退出保护，恢复原 Host Setup/Core 自动提示。
独立包保留可编译，但停用后的 App 无该模块的网络、下载或启动副作用。
`VPHONE_DISTRIBUTION_REVISION` 默认 0，正式打包脚本显式赋值；版本比较不复用 Core 内容哈希作大小排序。
移除功能时删除 Distribution UI 目录、独立 package、Xcode 引用、App/Model/RootView 的条件组装、宏及 Info.plist 附加键。
关闭宏不会删除下载、历史记录、已安装 Core 或已创建实例。更新 App 前先完成正在执行的导入/安装。

## 验证与尚未完成的真实验收

业务包测试覆盖 schema、路径/大小限制、分片失败后复用、损坏分片、导入与新身份调用顺序、同名拒绝、失败/取消清理及镜像更新记录。
导入测试使用隔离目录和命令替身，不操作用户 VM，不冒充真实 guest 启动。
本轮不提供假模板，不上传用户现有实例。完整跨 Mac 下载、Helper 认证、模板导入与 guest 启动，必须在获得已签名 App 和用户提供的干净模板后验收。

官方依据：[GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)（单附件小于 2 GiB）、[Apple 打包分发](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)。

### 2026-10-24 本机实现验证

- 分发模块 10 项测试通过，另覆盖发布分片边界与还原、App 不变时独立更新镜像、相同 App 修订的内容冲突，以及发布实例目录前完成绑定准备。
- Launchpad 开启与 `VPHONE_DISTRIBUTION=` 关闭构建均通过；关闭产物中未发现本功能 Model/View 符号。源码差异未触及 Core/CLI/guest。
- 使用已安装 `2.8.0-local.199abaf3` 只读执行 Core 打包，签名验证通过，输出计算身份一致；没有重签、安装或重新绑定实例。
- 发布 zsh 脚本语法检查通过。本机没有 Developer ID Application 证书，仅有 Apple Development 身份，因此未执行正式签名、公证或 GitHub 上传；用户尚未提供干净模板。尚未验证另一台 Mac 的端到端首次运行。
- 本轮未替换正在运行的 Launchpad。源码构建产物在 `.build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app`；这不是已经公证的可分发安装包。

### 2026-10-24 内部签名模式验收（补充，优先于上述首轮未部署记录）

- `--internal` Release 构建成功，复用当前已安装 App 的 Apple Development 身份及团队；未公证，未修改签名权限或 Helper/Core 协议。成品为 `.build/distribution-app-internalDevelopment-r1/vphone-launchpad-internalDevelopment-r1.dmg`，App 基线 2.8.0、发布修订 1，属于内部测试产物，尚未上传 GitHub。
- DMG SHA-256：`389e3892f150ea5d4b5bea2579c93e9c3e118a2b9c8b73cdb04178bbdba10f9f`。
- Publisher 从真实 DMG 挂载验证 Apple 签名、Helper 签名要求、revision、分发模式，再核对原 Core ZIP seal；生成无镜像的真实发布目录并再次 `--verify` 通过。修正原验证命令 `codesign -R` 参数需使用内联 `-R=<requirement>` 的问题。
- 从 DMG 安装完整 App 到 `/Applications/vphone-launchpad.app`。旧包备份 `.build/distribution-install-backup-r1/vphone-launchpad.app`；无 ad-hoc 重签、无全局 Gatekeeper 关闭。
- 用户在系统弹窗完成 Helper 管理员认证。`status` 返回 `helper: ready (15)`、`hostReady: true`、`canInstallBundles: true`；系统 Helper 与包内副本逐字节相同。
- 原先运行的 `1-20261023` 正常停止后恢复，guest 在 7 秒内响应；内存仍为 4096 MB、Core/guestEnvironment 绑定仍为 `2.8.0-local.199abaf3`，Core seal 与部署前一致。其它实例保持停止。
- 11 项隔离模块测试通过，包括旧目录默认公证、内部模式解码、未知模式拒绝和同修订签名模式冲突。没有使用用户镜像做下载测试。
- 真实更新页面请求已执行，但当前出口 GitHub API 返回 HTTP 403 / rate limit exceeded；未发布目录附件，因此真实在线更新下载尚未完成验收。另一台干净 Mac 的 Gatekeeper、首次 Helper 安装和模板导入也仍待实测，本机升级验收不能代替这些结果。
- 分发宏启用的 Release 打包与 `VPHONE_DISTRIBUTION=` 关闭构建均成功；关闭产物不含 Distribution Model/View 符号，未部署关闭构建。

### 发布与在线下载验收命令

发布 recipe 可指定 `previousTags`（最新在前，最多 99 项，不含本次 tag），使客户端保留历史版本选择。首次发布使用空数组。所有 latest Release 必须包含发行清单；不要把无清单的其它发行版标成 latest。

发布工具默认上传 draft；审核附件后，发布者用 `gh release edit <tag> --draft=false --latest` 公开。源码提交、App 修订、Core seal 应在发布说明中分别记录；已有发布附件不替换。

```sh
swift run --package-path Integrations/Distribution distribution-publisher \
  --check-download /absolute/new/acceptance-cache
```

该验收使用与 App 相同的匿名目录和下载模块，不读取 gh Token，强制新缓存，真实下载 App/Core，再核对大小、SHA-256、签名、修订和 Core seal，不安装或修改 Core。
GitHub 对附件/CDN 的网络限制仍可能存在；本改动消除的是 REST 匿名 API 配额依赖，不承诺无限制网络访问。

### 2026-10-24 r2 已发布与真实下载验收

- 用户授权发布的内部版：[launchpad-2.8.0-r2](https://github.com/baihua666/vphone-cli/releases/tag/launchpad-2.8.0-r2)。Release 非 draft、非 prerelease，并设为 latest；tag 精确指向 `87169bd0abb1ca570cb0ceb868f3baae9c129437`。这仍是 Apple Development 签名、未公证的内部包。
- App：基线 2.8.0 / revision 2，10,813,066 字节，SHA-256 `4a2d572a2c0af6b7987dfe61561764d1738f7c62d7426d15b28d1b5c696446b9`。
- Core：`2.8.0-local.199abaf3`，18,468,317 字节，SHA-256 `26f315c874b0df4c9e62acf5470466ab1039352d79981eb25d72e3366e6c45fa`。复用原 ZIP，无 Core 源码、签名或绑定改动。
- 只有上述两份包和 `launchpad-catalog.json` 三个附件，images 为空。未发布任何现用虚拟机、账号或业务数据。
- 14 项模块测试通过，分发宏开启 Release 打包、关闭 Debug 构建通过。正常版本检查不再请求 REST API；latest 下载和 previousTags 历史清单均固定在本仓库。
- `--check-download` 使用全新 `.build/distribution-online-acceptance-r2-final` 缓存、无 Token 真实下载 App/Core，大小、SHA-256、App/Helper 签名、修订和 Core seal 全部通过。首次并行验收时与安装操作同时挂载同一 DMG 导致资源忙；分开执行并用新缓存重新完整下载后通过，未将失败算作成功。
- 当前 Mac 已从实际下载的 DMG 安装修订 2；主机/Helper ready (15)，APP 内成功获取 `launchpad-2.8.0-r2` 并显示“当前修订 2，未发现更新”、未公证提示和无镜像说明。
- 原运行实例正常停止后恢复，guest 在 8 秒响应；Core/guestEnvironment 绑定仍为 `2.8.0-local.199abaf3`、内存 4096 MB，Core seal 与安装前一致。旧 r1 App 备份在 `.build/distribution-install-backup-r2/vphone-launchpad.app`。
- 另一台干净 Mac 的首装与镜像导入仍未验收；本次结果覆盖本机真实发行下载、升级和原实例恢复，不扩大为跨 Mac 全链路结论。
- 真实 APP 内点击「下载 App 更新安装包」后完成独立网络下载，页面显示「App 安装包已校验」及「在 Finder 中显示安装包」。App 缓存文件再次核对 SHA-256 与发布附件相同。
