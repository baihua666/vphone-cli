# Launchpad 发布与更新

2026-10-26：镜像禁止上传，仅从用户本地目录读取。旧的“完整 Release 自带镜像分片”要求已被用户取消；不得再据此上传镜像。

## 用户路径

- App 更新：菜单「VPhone Launchpad → 检查 App 更新…」。从包含该能力的版本开始，点击顶部「更新」即可下载、校验、安装并重启。更旧版本首次需手动安装一次新 DMG。
- Core：按需要单独安装，不自动改绑已有实例或更新 guest。
- 镜像：在「开始使用 → 本地镜像目录」选择包含完整归档及 images.json 的目录。更新本地文件和清单后点击「刷新本地目录」，再校验、创建新实例。现有 VM 不会被覆盖。
- 本地目录格式与维护见 [镜像本地目录](launchpad-image-release.md) 和 [清单示例](local-images.example.json)。原生「文件 → 导入…」仍可使用已有自有归档。

## 发布边界

线上仅允许 App DMG、必要 Core ZIP 和 launchpad-catalog.json；镜像文件、分片和历史镜像引用均禁止。recipe 和 catalog 的 images、previousTags 必须为 []。

`DistributionPublicationPolicy` 在发布目录校验时拒绝镜像记录和未允许文件；publisher 在分片/复制/校验产物前拒绝带镜像的 recipe。`publish-release.zsh` 验证后只选择三个明确文件上传，不按目录通配上传。测试 `scripts/test-publication-policy.zsh <旧含镜像目录>` 用假的 gh 记录器确认拒绝发生在任何上传命令之前。

此为项目发布工具及行为约束，不代表任意手工 gh、CI 或其它工具已被全局拦截。历史已发布附件不会自动删除，删除另需用户明确授权。

## 版本身份

- App：采用实际合入的官方基线，另加严格递增发布 revision。同一公开 revision 不得替换不同内容。草稿可在发布前修正。
- Core：保持官方基线与 `-local.<seal 内容哈希>` 身份；仅更新 App 不重建 Core。
- 本地镜像：稳定 id、显示版本、递增 revision、真实大小及完整 SHA-256，由本地 images.json 管理，独立于 App 发布。

本分支官方基线为 2.13.4，上游 commit 7f55bebdcbed913541928b9c4b1c1ca79abc0822。每次发布另记录实际源码 commit；不要把新上游发布当作已合入。

## 构建和发布

用发布源码的干净快照构建，不能夹带其它会话未完成改动。本机团队配置及私钥不进 Git。

```sh
zsh Integrations/Distribution/scripts/package-app.zsh --internal \
  <新修订> 'Apple Development: <本机有效身份>'
```

内部版有 Apple Development 签名、未公证，不是访问控制。另一台 Mac 的首次打开可能需要系统正常准入确认；不绕过 Gatekeeper、签名或 Helper 授权。当前无写权限安装目录不新增提权自动更新流程，明确报错。

准备 recipe：填入精确 tag、官方 baseline、appRevision、App DMG、原 Core ZIP 与原 seal 身份，signing 为 internalDevelopment，images 与 previousTags 为空。用既有 publisher 生成新的发布目录：

```sh
swift run --package-path Integrations/Distribution distribution-publisher \
  /absolute/recipe.json /absolute/new-output
swift run --package-path Integrations/Distribution distribution-publisher \
  --verify /absolute/new-output
zsh Integrations/Distribution/scripts/publish-release.zsh \
  /absolute/new-output <精确源码commit>
```

工具默认上传草稿。核对草稿只有三个允许附件、SHA-256 和源码 commit 一致后，公开并设为 latest。已公开 tag/附件不替换，使用新 revision。恢复中断的本次未发布草稿时，也必须先通过新发布策略校验，不得补回镜像。

公开后，用全新缓存验证匿名客户端 App/Core 下载、签名、App 修订和 Core seal：

```sh
swift run --package-path Integrations/Distribution distribution-publisher \
  --check-download /absolute/new-cache
```

该验收不下载镜像、不安装 Core、不创建 VM。镜像校验和导入在用户本地目录进行；不得用旧在线镜像命令替代。

## 编译开关和回退

App target 的 `VPhoneLaunchpad.xcconfig` 集中维护：

- `VPHONE_DISTRIBUTION = VPHONE_CUSTOM_DISTRIBUTION`：整个分发/目录入口。
- `VPHONE_APP_UPDATE = VPHONE_CUSTOM_APP_UPDATE`：默认开启，一键更新；清空恢复手动下载安装包。
- `VPHONE_LOCAL_IMAGES = VPHONE_CUSTOM_LOCAL_IMAGES`：默认开启，本地目录管理；清空隐藏目录入口、停止自动读取目录，保留基础文件导入。不会恢复在线镜像下载。

一键更新实现位于 Distribution/AppUpdate，目录适配位于 DistributionLocalImages，纯文件清单规则位于 Integrations/Distribution。删除功能时一并移除实现、窄组装点、条件分支、宏定义与对应测试。发布禁令不依赖 UI 宏，不因关闭本地目录功能而解除。

App 更新在原安装卷的私有目录暂存，经签名、版本和 Helper 签名规则校验，等待旧进程退出后替换并重新打开。替换失败保留或恢复旧版；备份和日志保留于本次 .vphone-update-UUID 目录。有运行/启动中的 VM 或创建/导入/导出任务时拒绝安装；不会自动停止 VM。回退不改实例、Core 绑定、guest 或本地镜像目录。

## App 更新与开始使用分开（当前源码，待发布）

「VPhone Launchpad → 检查 App 更新…」打开独立的 App 更新窗口，只展示当前 App 版本、检查结果、下载进度和安装重启操作；不读取本地镜像清单，不进行 Core 安装或实例创建。开始使用保留权限、Core、本地镜像和创建启动四步，顶部「刷新 Core 目录」只为准备运行组件获取元数据。两个窗口的检查结果、忙碌状态和错误各自维护；均提供「关闭」和 Esc。App 安装重启仍要求虚拟机及开始使用中的操作已结束。

关闭 `VPHONE_APP_UPDATE` 后，独立更新窗口保留检查与手动下载安装包；关闭 `VPHONE_DISTRIBUTION` 则移除这两个本地定制窗口。未变更 Core、guest、Helper 或已有 VM 绑定。
