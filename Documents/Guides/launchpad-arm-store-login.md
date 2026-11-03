# ARM Store 内部测试版使用说明

## 2026-11-03 源码中的会话流程修复（测试，尚未部署）

用户直接选择「仅下载」或「下载并安装」。现有 WebKit 会话由应用自动复用；需要恢复时，网站验证完成后自动关闭页面并继续同一请求，无需确认登录或重新点击下载。主界面不展示账号配置、登录状态或预设账号缺失提示。网站确实要求人工验证时才打开页面，用户取消会结束本次下载；等待最多五分钟。下载接口拒绝旧会话时最多重新授权一次，其它配额、会员、网络或安装错误不自动重试。

关闭应用管理宏后保留基础产品入口。当前电脑缺少有效签名身份，测试构建没有替换已安装版本；验证与维护记录见[本轮记录](../../Research/Host/arm_store_session_flow_20261103.md)。以下发行与部署说明保留历史版本事实。

> 分发决策更新：用户于 2026-10-27 明确要求将此预设账号构建直接发布到现有 GitHub Releases。以下私下传递、不公开上传及无法检查更新的说明记录此前决策，现已被覆盖。当前安装包为相同 r10，通过公开 Release 和 APP 检查更新分发；Core 未改，镜像不上传。

下载与更新：[r10 Release](https://github.com/baihua666/vphone-cli/releases/tag/launchpad-2.13.4-r10)。

适用：Launchpad 2.13.4 修订 10 私下分发版。该安装包内置预设账号，按用户最新要求直接在 GitHub Releases 分发。公开仓库只保存不含凭据的业务代码。

## 其它 Mac 安装与使用

1. 从 r10 Release 下载 `vphone-launchpad-launchpad-2.13.4-r10.dmg`，打开后将 APP 拖入 Applications。更新前正常退出旧 Launchpad；保留原资料库与实例。
2. 首次运行如被系统阻止，进入“系统设置 → 隐私与安全性 → 仍要打开”。这是未公证的开发签名版。按 APP 首次使用向导完成开发者工具权限和 Helper 管理员认证；密码只在 macOS 弹窗输入。
3. 新 Mac 按[完整安装说明](launchpad-internal-user-guide.md)安装兼容 Core，从管理员提供的本地镜像目录导入并创建实例。已有 Mac 沿用原 Core 与实例；本次更新不要求升级 Core，也不包含镜像。
4. 在主窗口启动目标虚拟机，打开工具栏“应用管理”，选择该实例，等待已安装列表读取成功。未选择、未启动或连接未就绪时，界面显示对应引导；不会猜测安装对象。
5. 切换 ARM Store，输入应用名称和地区（例如 instagram、us）搜索，点击“下载…”。可选择“仅下载”或“下载并安装到”选中的实例。
6. 下载流程自动复用这台 Mac 的 WebKit 会话；无需选择 Cookie 文件或手动确认登录。会话恢复中如网站需要人工验证，会自动打开页面，验证成功后继续下载；取消验证会取消本次下载。
7. 下载完成校验 IPA，并在选择自动安装时通过原 Core 接口上传、安装、读取列表确认。进入“本地应用”查看状态；“已是最新版本”指与本地 IPA 相同，不代表商店最新。下载期间仍可切换本地列表。
8. 安装超时先读取客体列表，避免重复安装；需要临时增配时使用既有确认流程。登录失败、下载失败和安装失败分别显示，不把其中一步失败当作全部成功。

官网密码登录可能跳转至 iOSGods 授权页，再返回 armconverter.com；这是本次已验收的预设账号流程，不复用 Chrome 的 Google 会话。验证码需用户处理，账号失效或网站流程改变可能需要重新构建更新。

## 版本更新

在 APP 中点击“检查更新”，发现 2.13.4 修订 10 后下载并安装；也可以从 Release 下载 DMG，退出旧 APP 后覆盖 Applications 中的 APP。更新沿用现有 GitHub 发行清单，无需新增服务器。

## 构建与维护

业务实现位于 `Integrations/ApplicationManagement/` 与 Launchpad 的 `Applications/`；复用既有下载器、实例适配器及安装接口。未修改 Core、CLI、guest 或 Helper 源码。上游入口仍使用原有应用管理条件组装点。

预设账号保存在不入库的 `VPhoneLaunchpad/VPhoneLaunchpad/Applications/VPhonePrivateARMStoreAccount.swift`，声明 `VPhonePrivateARMStoreAccount.account` 与 `.password` 两个静态字符串，整个声明由 `VPHONE_CUSTOM_APPLICATION_MANAGEMENT && VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT` 包围。维护者从私有渠道取得该文件，不能提交凭据。

`Configuration/VPhoneLaunchpad.xcconfig` 的 `VPHONE_ARM_STORE_PRESET_ACCOUNT` 默认为空。只有私下打包时显式设为 `VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT`；无预设的构建同样自动确认网站会话，在必要时等待用户完成网站验证。打包脚本拒绝将该开关用于公证公开模式，但不能阻止手工上传私有产物。

私下打包（团队与签名身份由维护者本机提供，不入库）：

```sh
VPHONE_ARM_STORE_PRESET_ACCOUNT=VPHONE_CUSTOM_ARM_STORE_PRESET_ACCOUNT \
  Integrations/Distribution/scripts/package-app.zsh --internal 10 "$SIGNING_IDENTITY"
```

可同时设置既有 `VPHONE_LAUNCHPAD_TEAM`。关闭预设宏后不会编译凭据；关闭 `VPHONE_APPLICATION_MANAGEMENT` 后整个应用管理入口不可达。删除预设能力时一并删除私有文件、Login 中的条件读取、xcconfig 开关与打包参数。关闭宏不会清除此前 WebKit 保存的会话。

真实部署与安装记录见[验收记录](launchpad-arm-store-deployment-20261027.md)。该记录描述已部署的 r8 基线功能构建；r10 私有发行在已提交 r9 基线上整理相同功能，产物检查见[私有发行记录](launchpad-2.13.4-r10-private-release-notes.md)。
