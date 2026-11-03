# Launchpad 2.15.0 本机签名部署与选图验收

2026-11-03，测试产物，未发布应用 Release，也未发布 Threads 帖子。

## 来源与边界

官方产品基线保持 2.15.0；部署源码基于 05d7004d（含选图修复 c549f872），另加独立的仅选图验证入口。使用仓库 Signing/README.md 指定材料和既有 SignLaunchpad.sh。私钥、密码、团队配置不写入本记录；Developer.xcconfig 仍为 gitignored。

通用匹配继续位于独立 PhotoPicker target，不依赖 Threads。此次只在 Threads 适配器和 Launchpad 窄入口增加 `threads-photo-check`：选择、确认、附件核验后返回；没有登录、导入、文案输入、journal 或发布调用。验证结果独立显示，保留原任务状态和 run.log。

编译条件沿用 `VPHONE_CUSTOM_PHOTO_SELECTION`、`VPHONE_CUSTOM_INSTAGRAM_AUTOMATION`、`VPHONE_CUSTOM_THREADS_AUTOMATION`、`VPHONE_CUSTOM_THREADS_DESKTOP`，定义在 Integrations/InstagramAutomation/Package.swift 与已有 Launchpad 构建配置。通用选图默认开启；`VPHONE_PHOTO_SELECTION_DISABLED=1` 关闭后验证入口报明确缺能力错误。未新增底层协议、Core、guest 或 helper 实现。

## 其他 Mac 复用

1. 同步代码；遵循 Signing/README.md 在目标 Mac 本地导入已有签名身份，不在聊天或日志输出密码、私钥。若有效身份为零，检查证书有效期和链；本次缺少 Apple WWDR G3 中间证书，从 Apple 官方证书站下载并导入后恢复有效身份，未改变根信任。
2. 在 gitignored Developer.xcconfig 配置证书对应团队。构建：

   `xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj -scheme VPhoneLaunchpad -configuration Release -derivedDataPath .build/LaunchpadSigned215 -jobs 4 VPHONE_DISTRIBUTION_SIGNING=internalDevelopment build`

3. 用 `VPhoneLaunchpad/Build/SignLaunchpad.sh APP IDENTITY` 签名，再执行 `codesign --verify --deep --strict APP`。使用完整 app，不单独替换启动可执行文件。
4. 正常停止运行实例、退出旧 Launchpad，备份旧 app 后部署签名产物至 /Applications/vphone-launchpad.app。重启应用核对版本和 helper readiness；保留实例原 library、pinned Core、数据与代理配置。
5. 启动实例，打开 Threads 原图任务对应的编辑页或照片选择器，在 Launchpad 任务详情点击“仅验证选图与附件（不发布）”。已存在单张附件时只做核验；需要验证选择过程时先移除测试附件。不要点击发帖/重试发布按钮。

回退可正常退出新 app 后恢复备份完整 app；不改 VM 绑定。停用/删除本次入口时一并移除 ThreadsPhotoValidation、ThreadsExecutionMode、界面按钮和 main 命令分支，通用 PhotoPicker 保持独立。

## 本机证据

- Release 构建成功；完整签名及 strict/deep 校验成功；安装 Info.plist 版本 2.15.0。
- 本机旧 app 备份：`.build/deployment-backups/launchpad-20261103/vphone-launchpad.app`。
- helper 正常报告 ready (21)，没有替换 helper 或 Core。
- 实例 1-20261026 从新界面启动，继续绑定 2.15.0-local.f7570c4b；另一实例保持停止、旧绑定不变。
- 启用测试 40 项通过（ThreadsDesktop 6、PhotoPicker 9、Automation 25）；关闭选图后 33 项通过（6 + 2 + 25）。新增回归先复现验证覆盖 tasks.json，再修复并确认文件字节不变；独立代码复核通过。
- 实际从 Launchpad 安全按钮运行安装包内执行器：`selected one matching photo`，随后 `attachment verified; not published`。相册保留三张重复原图，成功选择一张。
- 界面显示“选图与附件核验通过（本次未发布）”；guest AX 确认一个 image-view，文案为空；原任务 state.json SHA-256 前后一致。保持未发布草稿，未点击 Post。
- 原任务列表的历史“失败”状态刻意保留，最新验证结果显示在下方，不代表本次核验失败。
- 详细本地证据在 `.build/validation/launchpad-deploy-215-20261103/`；不提交用户图片、任务数据、签名私钥或 VM 镜像。
