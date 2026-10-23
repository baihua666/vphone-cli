# 镜像发布流程：从干净模板到新 Mac 首次启动

适用于内部发布维护者。2026-10-24。用户安装入口见 [其它 Mac 安装与使用说明](launchpad-internal-user-guide.md)。

**当前状态：APP/Core 已发布；镜像由用户另行提供，尚未发布或完成真实镜像验收。**
下面给出可执行流程与验收标准，不把无镜像 Release 当作新机完整交付。
不修改 Core、CLI 或 guest。开发机使用现有发布工具；接收用户只操作 Launchpad。

## 1. 接收与确认模板

由模板提供者交付以下信息：

- 已正常停机导出的 vphone `.tzst` / `.txz` 完整归档、字节大小和 SHA-256。
- iOS/cloudOS 版本、原 Core 完整版本；当前计划复用 `2.8.0-local.199abaf3`，不匹配时先确认兼容性，不能自动升级底层。
- 解压后容量的保守上界（字节）、CPU/内存配置、推荐主机可用空间。
- 首次启动是否需完成 Setup Assistant、是否有锁屏密码、是否存在特殊网络要求。
- 模板清洁性确认：不含个人 Apple 账号、ARM Store 会话、业务数据、Cookie、代理凭据和私有文件引用。不要从现用用户实例直接导出后公开。

该 GitHub 仓库公开，Release 附件也公开。“内部版”不是下载访问控制。不能公开的模板不得上传到此仓库，应先另行确定分发位置。

如果提供者只有完整实例目录：在源 Launchpad 中正常停止该实例，选择实例的「导出… / Export…」生成归档；不要仅压缩 Disk.img 或运行中的目录。保留原始归档作为可追溯输入。

新身份克隆不会清除账号和应用数据，也不保证所有标识重置；模板清理必须在导出前完成。设置自动锁定“永不”并验证冷启动进入桌面；不能把“永不锁屏”当成启动解锁成功。

## 2. 发布前离线验收

在独立测试实例中导入归档，使用现有「克隆 → 新设备身份」验证新实例能启动；原模板保持停止，不使用用户现用虚拟机做破坏性测试。

核对：归档完整、匹配 Core 可用、能进入桌面、客体服务响应、预期应用可打开、网络可用、停止后再启动正常。检查没有源机器绝对路径或专用代理账号依赖。

`expandedBytes` 应为归档解压后文件逻辑大小的保守上界，而不是压缩包大小或 APFS 共享块占用。可在测试导入目录计算逻辑字节总数后向上取整：

```sh
# 仅统计文件元数据，不修改内容；将路径替换为测试导入的完整实例目录。
find /absolute/test/instance -type f -exec stat -f '%z' {} + \
  | awk '{total += $1} END {printf "%.0f\n", total}'
```

Launchpad 会在此数值基础上预留两倍容量和安全余量。64 GiB 等数值不能无依据照抄。最后必须用真实导入确认空间足够。

## 3. 准备版本和发布 recipe

复制 [镜像 recipe 示例](../../Integrations/Distribution/recipe.image.example.json) 到本机私有目录，再填真实值。示例 `expandedBytes: 0` 故意无效，必须先核算填写；日期、标题及路径也需改为实际信息。

| 字段 | 维护规则 |
| --- | --- |
| tag | 每次新建独立 Release，例如 `launchpad-2.8.0-image-clean-ios-r1`；不得替换 r2 的现有清单或附件 |
| previousTags | 列出此前已正式发布的 tag，最新在前，最多 99 项；不要放本次 tag、draft 或 prerelease |
| baseline / appRevision | 复用当前 App 时仍为 `2.8.0` / `2`；不能把镜像修订当 App 修订 |
| appDMG / coreZIP | 使用当前已发布包的原始字节；仅更新镜像不重建或重签 App/Core |
| coreVersion | 核对实际 seal 身份；所有本次镜像必须与清单里的 Core 一致 |
| images[].id | 稳定模板类型，例如 `clean-ios`，后续版本沿用 |
| version / revision | 人可读版本和严格递增整数修订；同 id/revision 不替换内容 |
| archive / expandedBytes | 真实归档路径及实测容量上界；不手写分片哈希 |

可以在发布机用 `gh release download launchpad-2.8.0-r2 --repo baihua666/vphone-cli --dir /absolute/new/input --pattern '*.dmg' --pattern 'VPhone-*.zip'` 取回原始包。对照原 Release 清单核验 SHA-256 后填写路径，不重新打包。

## 4. 分片、清单生成与本地校验

```sh
swift run --package-path Integrations/Distribution distribution-publisher \
  /absolute/private/image-recipe.json /absolute/new/image-release-output

swift run --package-path Integrations/Distribution distribution-publisher \
  --verify /absolute/new/image-release-output
```

工具复用现有逻辑：核验 App 签名/修订、Core seal；镜像按 **1 GiB** 分片，计算每片及完整归档 SHA-256；写 `launchpad-catalog.json`。最终目录包含 App DMG、Core ZIP、清单和全部镜像分片。所有附件都属于本次 Release，不能仅上传分片而遗漏 App/Core。

输出目录必须是新目录。失败或中断的半成品不能发布；确认无任务占用后自行清理，重新使用新目录生成。分片字节改变时必须发布新镜像修订。

## 5. 上传 Draft，核对后发布

在输出目录创建 `release-notes.md`，至少包含：

- APP 下载直链旁的 [安装说明](https://github.com/baihua666/vphone-cli/blob/tb_dev/Documents/Guides/launchpad-internal-user-guide.md)。
- App 基线/修订、Core 完整身份、源码完整 commit SHA。
- 镜像名称/id/version/revision、系统版本、下载总大小与解压空间要求。
- 模板来源和清洁性结论、初始设置要求、已执行验收、明确未通过或未执行的项目。
- 提示新用户在 APP 中下载镜像，不需要手工逐个下载分片；镜像更新创建新实例，不覆盖原磁盘。

```sh
zsh Integrations/Distribution/scripts/publish-release.zsh \
  /absolute/image-release-output <完整40位源码commitSHA>
```

此步骤只创建 draft。发布者核对 GitHub 上的附件数量、每个 size/digest 与本地清单一致，确保全部上传成功、没有私有文件。可通过已登录 gh 下载 draft 附件到新目录，再运行 `--verify` 检查远端字节。

在完成内容审查及离线验证、获准分发后发布并设为 latest：

```sh
gh release edit <本次tag> --repo baihua666/vphone-cli --draft=false --latest
```

普通 APP 不读取 draft/prerelease。不要把无清单的发行版设为 latest。不要在 r2 上覆盖清单来“补镜像”；使用新的镜像 Release 保持历史可追溯。

## 6. 真实下载与新 Mac 完整验收

发布后在开发机执行：

```sh
swift run --package-path Integrations/Distribution distribution-publisher \
  --check-download /absolute/new/online-image-acceptance --include-images
```

此命令要求全新缓存，使用与 APP 相同的无 Token 下载模块，验证 App/Core，并下载清单里的**所有镜像分片**、合并归档和校验完整 SHA-256。清单没有镜像会失败，不把 App/Core 下载成功冒充镜像交付。该命令不安装 Core、不导入或启动虚拟机。

再用另一台符合要求的 Mac 按用户说明完成：

1. 下载 APP → 首次打开 → Helper 管理员认证 → 主机设置。
2. 「版本与镜像 → 检查更新」，选中本次 Release，确认 App/Core/镜像版本。
3. 安装匹配 Core，完成预检。
4. 选择镜像模板和新实例名，确认磁盘空间；点击「下载、导入并启动新实例」。
5. 下载中暂停一次再继续，确认已校验分片可复用，最终完整校验成功。
6. 确认独立新实例出现在列表、Core 绑定正确、客体启动并可操作；停止再启动成功。核对原有实例未被覆盖。
7. 记录目标 Mac 的芯片/macOS、镜像及 Core 版本、耗时、空间、结果和失败步骤；发布说明补充实测结论。

只有下载、合并、导入、独立身份创建、启动均通过，才能标记“新用户完整安装验收通过”。没有用户提供的干净模板或目标 Mac 时，记录待验收，不用测试替身或本机旧实例代替。

## 7. 失败处理与回退

- 上传中断：保持 draft，不暴露半成品；补齐后重新校验全部附件。
- 分片/完整哈希失败：停止安装，核对来源及发布字节；不跳过校验。
- 导入失败：按 APP 错误处理空间、归档或绑定问题；不要删除用户实例或重刷固件。
- 已导入但启动失败：用「重试启动已导入实例」，不要重复导入创建多份。
- 已发布模板存在问题：在说明中标明问题，并将上一份含完整清单的 Release 设为 latest。已下载的坏模板不自动清除；通知使用者停止采用。修复后使用新 revision/tag，保留追溯。

GitHub 官方参考：[管理 Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
