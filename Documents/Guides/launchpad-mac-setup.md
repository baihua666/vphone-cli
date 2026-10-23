# Launchpad：其它 Mac 获取、构建与使用

提供已签名发行包后的普通用户路径见 [下载分发与首次使用](launchpad-distribution.md)。本页仍用于源码构建。

适用分支：`origin/tb_dev`。近期功能见 [更新摘要](launchpad-updates-20261023.md)。
这是本地定制源码的部署说明，不是官方公证发行包的安装说明。
更新源码、构建 Launchpad、安装 Core、更新 guest 是四件独立的事；普通应用管理更新只需部署 Launchpad。

## 1. 获取完整源码

需要实体 Apple Silicon Mac、macOS 15 或更新版本，以及支持工程的完整 Xcode（含所需 SDK）。
先确认 `xcode-select -p` 指向 Xcode，再运行 `xcodebuild -version`；首次使用完成 Xcode 许可与组件安装。
仅运行已签名产物不需要 Xcode、Homebrew 或 Python。主机安全设置按 [Host Setup](host-setup.md) 检查，不能用重建 VM 代替权限配置。

首次获取：

```sh
git clone -b tb_dev git@github.com:baihua666/vphone-cli.git
cd vphone-cli
```

已有 checkout：先确认没有未整理的本地修改，再更新；分叉时检查并合并，不强推或 reset：

```sh
git status --short
git pull --ff-only origin tb_dev
```

完整保留 `VPhoneWorkstation/`、`Integrations/ApplicationManagement/` 与 `Integrations/Flywheel/`，它们是 Launchpad 的本地 package 依赖。
无需相邻的 vphone-ws 或 FLYWHEEL 后端仓库。依赖使用仓库锁文件，首次构建需联网下载。

## 2. 构建与测试

从仓库根目录运行，各步骤成功后再继续：

```sh
./scripts/dev.sh test launchpad
swift test --package-path Integrations/ApplicationManagement
swift test --package-path Integrations/Flywheel
zsh VPhoneLaunchpad/Tests/DeviceInitializationTests.sh
zsh VPhoneLaunchpad/Tests/CreationInitializationTests.sh
zsh VPhoneLaunchpad/Tests/InstallMemoryRecoveryTests.sh
./scripts/dev.sh build launchpad
zsh VPhoneLaunchpad/Tests/FlywheelWebActionTests.sh \
  "$PWD/.build/LaunchpadDecodo/Build/Products/Debug"
```

`test launchpad` 当前只运行共享 Workstation/WSCore 测试，不能替代上述业务包与适配器测试。
`build all` 当前只构建 Workstation 和 Core，**不包含 Launchpad**。
产物为 `.build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app`，构建不会部署、停止 VM 或修改实例绑定。
真实代理测试默认跳过；不要为首次构建开启 live 测试，它们需要专用测试实例、账号并可能消耗流量。

只有明确需要 Core 中新增能力时，才按 [共同开发说明](monorepo-development.md) 运行 `test cli` / `build cli` 并单独安排安装验收。
应用管理、版本比较和临时内存恢复复用现有 Core 接口，不要求新建 Core Bundle。

## 3. 签名与部署

Xcode 构建不签名。部署前，在本机 gitignored 的
`VPhoneLaunchpad/Configuration/Developer.xcconfig` 设置 `VPHONE_LAUNCHPAD_TEAM = <自己的团队 ID>`，
然后重新构建。已有文件只编辑必要字段，不覆盖其它设置；团队、证书私钥不提交。
使用与该团队一致、钥匙串中有效的 Apple Development 证书供本机及受控内部测试；内部 DMG 可不公证，但目标 Mac 可能需手动允许打开，必须验证 Helper 授权。具体见 [内部版打包与分发](launchpad-distribution.md)。面向默认 Gatekeeper 准入的分发使用 Developer ID 并公证。

```sh
zsh VPhoneLaunchpad/Build/SignLaunchpad.sh \
  "$PWD/.build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app" \
  'Apple Development: <本机有效签名身份>'
codesign --verify --strict --deep \
  .build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app
```

没有有效签名条件时，不用 ad-hoc 绕过 Helper 互信校验。保留当前可用应用，先解决签名条件。

部署在允许中断的维护窗口进行：记录运行实例、资料库及绑定 → 正常停止受影响实例 → 退出旧 Launchpad并确认进程退出 → 备份旧 app → 将完整签名 app 安装到 `/Applications/vphone-launchpad.app` → 打开并完成 Host Setup、Helper/开发者工具认证 → 按原绑定恢复原先运行的实例。
不要同时运行相同 bundle ID 的两个副本。Debug 构建必须包含 `vphone-launchpad.debug.dylib`，不能仅复制同名主程序。
Helper 是否需要更新以应用校验为准；不能仅按 Helper 版本号推断签名一致。

Core 版本仍沿用实际官方基线 **2.8.0** 与 `-local.<内容哈希>`。不要复制其它 Mac 的 receipt、改目录或写死本机曾经出现的 hash；正常安装器决定该包身份。
每台 VM 使用自己的 `launchpad.json` 绑定；更改默认 Core 只影响新建/库级命令，不是批量升级。
接入已有资料库不需要重新 create/restore。新 Mac 没有 VM 时，先完成 Core 安装和正常新建/恢复，拉代码不会生成磁盘。

## 4. 本机必配项目

| 功能 | 每台 Mac 自己配置 | 不能从 Git 获得的状态 |
| --- | --- | --- |
| 应用管理 | 主窗口工具栏「应用管理」；选择完整资料库/实例路径 | 已下载 IPA、guest 已安装应用 |
| ARM Store | 在该 Mac 正常登录；提供有效私有 Cookie 文件，并在 ARM 页选择它 | 网站登录、下载额度、Cookie 与临时 token |
| Decodo | 「设置」/「Decodo 账号设置…」；网站授权与代理账号分别配置 | 密码、JWT、refresh token、API Key |
| 原生代理 | 选择该 Mac 的真实物理网卡及私有代理文件 | 网卡名称、网关地址、每实例代理引用 |
| FLYWHEEL | 新增本地业务关联、填写业务网页 URL/参数 | 本地 SwiftData 数据库与网页偏好 |
| Workstation 备用 | 单独配置 `~/.vphone/host-config.zsh` 与 sidecar | 其它 Mac 的 runtime 绝对路径 |

ARM 会话文件只包含一行 Cookie 请求头值（不含 `Cookie:` 前缀），权限 `0600`，放仓库外或 gitignored `.local/`。
已有 Chrome 登录会话可在用户授权后用
`skills/vphone-app-install/scripts/export-armstore-session.sh --profile <本机实际Chrome配置目录> --output <私有文件路径>` 导出；只支持实现中已适配的加密格式，可能需要钥匙串认证。
失败时按正常网页登录和会话更新处理，不猜密码、不绕过验证码。参见 [ARM 会话与下载说明](../../skills/vphone-app-install/references/armstore-api.md)。
在 ARM 页选中该文件后才可下载；本地 IPA 安装不需要 ARM 登录。

Decodo 网站账号模板为 [decodo-account.example.json](decodo-account.example.json)，代理账号模板为 [decodo.example.json](decodo.example.json)。
真实配置放 `~/.vphone/` 并设 `0600`，不要把网站邮箱密码当作代理用户名密码。详见 [Decodo](launchpad-decodo.md) 与 [原生代理](native-decodo-proxy.md)。
网卡不能照抄 `en1`；Clash 分流需要本机有效规则，原生代理需要运行 Core 的实际能力支持，不自动升级 Core。

FLYWHEEL 的 `~/Library/Application Support/vphone-launchpad/Flywheel/` 是本机库。
备份时退出应用并保留整个目录；即使单独迁移数据库，另一 Mac 的目录身份也不同，必须显式重新关联 VM。
不按同名或 UDID 自动认领。业务后端尚未接入，无需部署 JeecgBoot 才能使用本地管理。

## 5. 更新后的验收与回退

1. 打开 Launchpad，核对 Helper、资料库、原 Core 绑定和实例启停；确认旧应用与数据仍在。
2. 应用管理选择运行实例，读取已安装列表。TikTok 等已装包显示与本地版本的比较结果；“最新”仅指相对本地包。
3. 若旧实例启动时未启用应用上传 API，正常停止后从新版 Launchpad 启动；不要因此重装 Core。
4. ARM 搜索时可切换「本地应用」。下载需要真实登录与额度；未做真实下载不能标为认证链路已验收。
5. 大包安装失败先刷新客体列表，超时不等于取消。选择临时 8 GB 后，完成或失败都应恢复原内存并启动；8 GB 是 VM 配置内存，宿主实际占用还包含虚拟化开销，不能承诺总占用不超过 8 GB。
6. 如提示恢复失败，先完成「恢复原内存并启动」，保留恢复记录。不要在有待恢复任务时回退或禁用恢复功能。
7. 按实际使用范围核对代理 guest 出口、FLYWHEEL 关联与网页参数；没有账号或专用测试环境时标记未验证。

回退前正常停止受影响实例，恢复备份的完整签名 app，再按原绑定启动。
普通 Launchpad 更新不改 Core/guest，不需要回退磁盘。应用安装、Never 设置或网络修改是独立持久状态，回退 app 不会自动撤销它们。
功能宏与关闭步骤见 [应用管理](launchpad-applications.md)。

Git 只同步源码/测试/文档，不同步 `.local/`、`.build/`、签名配置、日志、VM、IPSW、IPA、业务库或账号。
