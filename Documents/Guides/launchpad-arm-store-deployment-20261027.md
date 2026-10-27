# ARM Store 静默登录正式 APP 部署（2026-10-27）

## 部署范围

用户明确要求部署到当前 `/Applications/vphone-launchpad.app`，不改 Core，不带入其它未提交改动。

部署前正式 APP 为 2.13.4、发行修订 8、Helper 构建号 21。主程序 SHA-256 与保留的 r8 发布构建逐字节相同：`587a9c91ae17fb9307f77caa50d9a57014e1d052e6c43aa8ea8577100b90a1d5`。因此从 `3a6f7690` 干净归档重建，只覆盖本次 7 个文件：

- `Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/ARMStore.swift`
- `Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/ApplicationLibrary.swift`
- `Integrations/ApplicationManagement/Sources/VPhoneApplicationManagement/ARMStoreSession.swift`
- `Integrations/ApplicationManagement/Tests/VPhoneApplicationManagementTests/ARMStoreSessionTests.swift`
- `VPhoneLaunchpad/VPhoneLaunchpad/Applications/VPhoneARMStoreLogin.swift`
- `VPhoneLaunchpad/VPhoneLaunchpad/Applications/VPhoneLaunchpadApplicationsModel.swift`
- `VPhoneLaunchpad/VPhoneLaunchpad/Applications/VPhoneLaunchpadApplicationsView.swift`

逐文件与基线 Git blob 比较通过，仅这 7 个文件不同；macOS 大小写不敏感路径单独归一化。未带入工作区中分发、独立更新窗口、旧客体修复等其它未提交改动，也不升级到 r9。

## 构建与安装

- Release 隔离构建通过，沿用原团队内部开发签名，严格递归验签通过。
- 复用原 APP 的 Helper、随包 CLI、启动器三个签名原件，部署后再次逐字节比较相同；Helper 仍 `ready (21)`，无重新安装/授权。
- 产品基线 2.13.4、发行修订 8 不变。本次为本地功能更新，不创建 GitHub Release，不推送明文预设凭据。
- 新主程序 SHA-256：`d63b70edcbb9f2d5ed92e279a77b4a52d9b17e36020f5241534bc9f8c52ef039`。
- 旧 APP 可从 `.build/arm-deploy-evidence/previous.app` 恢复。隔离源码为 `.build/arm-deploy-source/`，审核清单、构建日志和前后状态在 `.build/arm-deploy-evidence/`。

## 正式 UI 验收

- 在正式 APP 主窗口打开“应用管理”，不再显示选择私有 Cookie 文件。
- 未选目标时显示明确引导，不提供可误操作的安装按钮。
- 仅启动既有测试实例 `wizard-r5-check-20261026`，仍绑定 `2.13.4-local.666ac4da`。原 5 台业务实例不启停、不改绑。
- UI 选择测试实例、搜索 Instagram、确认“下载并安装到 wizard-r5-check-20261026”。从“待登录／验证”自动变为“已登录”，没有打开登录窗口或要求 Cookie 文件。
- 下载进行中切换“本地应用”成功，列表仍可浏览，安装相关动作维持串行。
- 真实下载至 `~/Library/Application Support/vphone-launchpad/Applications/389801252-453.0.ipa`，325441910 字节，SHA-256 `03de16ff35ada2284cfca61a66e50f644be75ea3daab9095952faf879e47dbbe`。这次是正式 APP 新发起的下载，不是复用独立测试程序的 `arm-acceptance-instagram.ipa`。
- 正式 UI 最终显示“Instagram 已安装到 wizard-r5-check-20261026，并已读回确认”，列表显示包内版本 453.0.0、构建 1099096960 与目标机一致。“已是最新版本”仅相对于本地包。
- 安装后再启动验证，apps.launch 返回 PID 539、`frontmost_verified=true`，apps.foreground 返回同一 PID 与 `com.burbn.instagram`、`verified=true`。
- 验收后停止测试实例；6 台实例的名称、资料库、Core/guest/bootChain 绑定、内存、CPU 和停止状态与部署前快照一致。
- 正式安装路径验签再次通过。未提交、推送或发布本次代码/凭据。

成功截图：`.build/arm-deploy-evidence/installed-ui.png`。本次真实 UI 验收替代此前“仅独立验收、正式 APP 未部署”的状态说明。
