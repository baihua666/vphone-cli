# ARM Store 私下分发版使用说明

适用：Launchpad 2.13.4 修订 10 私下分发版。该安装包内置预设账号，按用户要求仅在线下传递，不上传公开 GitHub Releases。公开仓库只保存不含凭据的业务代码。

## 其它 Mac 安装与使用

1. 从管理员取得 `vphone-launchpad-internalDevelopment-r10.dmg`，打开后将 APP 拖入 Applications。更新前正常退出旧 Launchpad；保留原资料库与实例。
2. 首次运行如被系统阻止，进入“系统设置 → 隐私与安全性 → 仍要打开”。这是未公证的开发签名版。按 APP 首次使用向导完成开发者工具权限和 Helper 管理员认证；密码只在 macOS 弹窗输入。
3. 新 Mac 按[完整安装说明](launchpad-internal-user-guide.md)安装兼容 Core，从管理员提供的本地镜像目录导入并创建实例。已有 Mac 沿用原 Core 与实例；本次更新不要求升级 Core，也不包含镜像。
4. 在主窗口启动目标虚拟机，打开工具栏“应用管理”，选择该实例，等待已安装列表读取成功。未选择、未启动或连接未就绪时，界面显示对应引导；不会猜测安装对象。
5. 切换 ARM Store，输入应用名称和地区（例如 instagram、us）搜索，点击“下载…”。可选择“仅下载”或“下载并安装到”选中的实例。
6. 私有包自动使用预设账号登录，并保存这台 Mac 的 WebKit 会话；无需手动选择 Cookie 文件。正常登录不弹出网页。若官网需要验证码或登录失败，打开“登录／管理账号…”处理网页提示，再重试；不会无限重复提交。
7. 下载完成校验 IPA，并在选择自动安装时通过原 Core 接口上传、安装、读取列表确认。进入“本地应用”查看状态；“已是最新版本”指与本地 IPA 相同，不代表商店最新。下载期间仍可切换本地列表。
8. 安装超时先读取客体列表，避免重复安装；需要临时增配时使用既有确认流程。登录失败、下载失败和安装失败分别显示，不把其中一步失败当作全部成功。

官网密码登录可能跳转至 iOSGods 授权页，再返回 armconverter.com；这是本次已验收的预设账号流程，不复用 Chrome 的 Google 会话。验证码需用户处理，账号失效或网站流程改变可能需要重新构建更新。

## 私有版本更新

管理员私下提供新的 DMG，用户退出旧 APP 后覆盖 Applications 中的 APP。GitHub“检查更新”只能发现公开发行，**不会发现或下载这个私有修订**。本次没有私有更新服务器，不发布含预设账号的公开附件或发行清单。

## 构建与维护

业务实现位于 `Integrations/ApplicationManagement/` 与 Launchpad 的 `Applications/`；复用既有下载器、实例适配器及安装接口。未修改 Core、CLI、guest 或 Helper 源码。上游入口仍使用原有应用管理条件组装点。

预设账号保存在不入库的 `VPhoneLaunchpad/VPhoneLaunchpad/Applications/VPhonePrivateARMStoreAccount.swift`，声明 `VPhonePrivateARMStoreAccount.account` 与 `.password` 两个静态字符串，整个声明由 `VPHONE_CUSTOM_APPLICATION_MANAGEMENT && VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT` 包围。维护者从私有渠道取得该文件，不能提交凭据。

`Configuration/VPhoneLaunchpad.xcconfig` 的 `VPHONE_ARM_STORE_PRESET_ACCOUNT` 默认为空。只有私下打包时显式设为 `VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT`；无预设的构建保留手动官网登录与会话确认。打包脚本拒绝将该开关用于公证公开模式，但不能阻止手工上传私有产物。

私下打包（团队与签名身份由维护者本机提供，不入库）：

```sh
VPHONE_ARM_STORE_PRESET_ACCOUNT=VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT \
  Integrations/Distribution/scripts/package-app.zsh --internal 10 "$SIGNING_IDENTITY"
```

可同时设置既有 `VPHONE_LAUNCHPAD_TEAM`。关闭预设宏后不会编译凭据；关闭 `VPHONE_APPLICATION_MANAGEMENT` 后整个应用管理入口不可达。删除预设能力时一并删除私有文件、Login 中的条件读取、xcconfig 开关与打包参数。关闭宏不会清除此前 WebKit 保存的会话；可先在界面退出登录。

真实部署与安装记录见[验收记录](launchpad-arm-store-deployment-20261027.md)。该记录描述已部署的 r8 基线功能构建；r10 私有发行在已提交 r9 基线上整理相同功能，产物检查见[私有发行记录](launchpad-2.13.4-r10-private-release-notes.md)。
