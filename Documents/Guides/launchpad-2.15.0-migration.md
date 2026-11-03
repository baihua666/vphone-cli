# 官方 2.15.0 业务版：跨 Mac 升级与复用

2026-11-03。本说明对应本地测试升级，不代表已公开发布或已完成第二台 Mac 验收。

## 来源与修改摘要

- 官方 tag `2.15.0`：`fd1610d7928aacd6cbc060722bb27fd7d2c76315`。
- 本地合并提交 `94dbabe2`；同步前业务基线 `674b0adb841dbd0492e9649873b307ffb9c1cedb`。
- 保留应用管理/ARM Store、临时安装内存恢复、FLYWHEEL、Decodo/原生代理、
  设备初始化、分发与首次向导、Workstation 备用。保留独立业务模块和既有编译开关。
- 鼠标修复直接来自官方：普通触摸按下不再因接近窗口边缘而吸附到屏幕最左/右边。
  原 Threads 选图关闭按钮中心点击被误改坐标；不需要重刷 iOS、内核或修改分辨率。
- 冲突处理保留本地旧 Core 管理兼容范围、test 身份展示和研究历史；创建初始化
  测试替身适配官方新增 preset 参数接口。没有另加鼠标补丁。
- `MARKETING_VERSION=2.15.0`；Core 身份继续取签名 seal SHA-256 前 8 位。
  不把日期、测试次数、分发 revision 当作官方版本或内容哈希。

## 当前交付状态与限制

| 项目 | 状态 |
| --- | --- |
| 业务源码 | 已合并；本次尚未推送远端或发布 Release |
| Core | 完整构建、ad-hoc 签名及 admission 通过，当前 Mac 已安装并运行 |
| 本次 Core 身份 | `2.15.0-local.f7570c4b`，test，源码构建标识 `94dbabe2` |
| Launchpad 2.15.0 | 完整构建与业务回归通过；等待有效 Apple 签名后部署 |
| 当前已安装 Launchpad | 原已签名业务版 2.13.4，正常管理新 Core |
| 第二台 Mac | 未实测，不能将本机结果当作跨机验收 |

CoreKit 672 项中 670 项通过、2 项失败（3 个断言）：官方已列出 `iPhone15,4`，
但固件目录没有其配对。产品和测试文件与官方 tag 相同。影响该型号的固件目录/
创建覆盖，不隐瞒失败、不虚构下载 URL。旧 Core 能被管理不等于支持新版全部创建命令。

业务验证：ApplicationManagement 11 项、FLYWHEEL 45 项（含目录身份生命周期）、
Distribution 25 项、共享 Workstation 120 项、全部 16 个 Launchpad 独立脚本通过。
启动解锁与 source-sync 回归通过。三个既有可选宏开启/关闭构建均通过；未完成宏隔离
的历史业务仍属未覆盖。真实 ARM 下载、代理换 IP、第二台 Mac 首装不在本次验收范围。

## 在另一台 Mac 获取同一份源码

先记录本机工作区、分支和运行实例；保留本地修改，不使用 reset/clean。
本轮未推送，因此仅 `git pull origin tb_dev` 不保证拿到本次升级。
若使用随附 Git bundle，在已有完整业务仓库根目录运行：

```sh
git status --short
git bundle verify /absolute/path/vphone-business-2.15.0-test.bundle
git fetch /absolute/path/vphone-business-2.15.0-test.bundle \
  tb_dev:refs/remotes/transfer/business-2.15.0-test
git log --oneline HEAD..refs/remotes/transfer/business-2.15.0-test
# 先整理本机未提交修改；在本机业务分支上合并并处理本机独有变更。
git merge --no-ff refs/remotes/transfer/business-2.15.0-test
```

增量 bundle 依赖上述同步前业务基线。`bundle verify` 报缺少 prerequisite 时，
先从既有业务远端获取该基线；不要强行覆盖目标仓库。它不包含未提交修改、账号、
证书、VM、业务数据库或构建产物。须保留整个 monorepo，不单独复制 Launchpad 目录。

## 构建、签名、安装 Launchpad

准备完整 Xcode 及工程需要的 SDK；本次构建使用 Xcode 27。沿用锁定依赖。
先按 [常规跨 Mac 指南](launchpad-mac-setup.md) 跑测试。每个步骤成功后再继续。

1. `security find-identity -v -p codesigning` 确认有效证书及私钥；管理员认证不等于
   开发者签名。本机/受控内部测试可用 Apple Development，公开分发用 Developer ID
   并公证。尽量沿用原团队；更换团队须重新构建双方互信并在目标 Mac 验证 Helper。
2. 在本机 gitignored `VPhoneLaunchpad/Configuration/Developer.xcconfig` 设置
   `VPHONE_LAUNCHPAD_TEAM = <实际团队>`；已有配置只修改必要字段。不要传输私钥给
   接收用户，也不要提交团队私有配置。
3. 本地测试构建明确使用内部签名展示模式，revision 保持开发值 0：

```sh
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj \
  -scheme VPhoneLaunchpad -configuration Debug \
  -derivedDataPath .build/LaunchpadDecodo -jobs 4 \
  VPHONE_DISTRIBUTION_SIGNING=internalDevelopment build
zsh VPhoneLaunchpad/Build/SignLaunchpad.sh \
  "$PWD/.build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app" \
  'Apple Development: <本机有效身份>'
codesign --verify --strict --deep \
  .build/LaunchpadDecodo/Build/Products/Debug/vphone-launchpad.app
```

4. 核对 App/Helper 互信、版本和签名；按维护窗口正常停止受影响 VM、退出旧管理器，
   备份完整旧 App，再复制完整签名 App 到 `/Applications/vphone-launchpad.app`。
   Debug 包必须包含 debug dylib。不要只复制主程序或同时运行两个同标识管理器。
5. 打开后完成系统 Helper/开发者工具认证，核对 library、默认 Core 和每机绑定，
   恢复原先运行的实例。不要覆盖其它 Mac 的代理配置、业务库和实例路径。

无有效证书时保留原 App；不能以 ad-hoc 或删校验绕过 Helper。为其它 Mac 制作
可安装 DMG 时使用 [既有内部打包流程](launchpad-distribution.md)，独立分发 revision
按已有发行记录选择；不要照抄旧文档的 r1，也不要把测试产物直接发布。

## Core 按实例选择升级

已有 Core 满足业务能力时，单独升级 Launchpad 不要求迁移它。确需点击修复的实例：

```sh
LP=/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli
"$LP" vm list
"$LP" bundle install-local /absolute/path/VPhone.bundle --keep-default
# 保存目标的实际旧版本、library 与配置；正常停机后按现有 snapshot 命令备份。
"$LP" vm stop <目标实例>
"$LP" vm set-bundle <目标实例> <安装返回的版本>
"$LP" vm start <目标实例> --wait --timeout 180
```

以上尖括号是占位符，执行前替换为目标 Mac 的实际值。不要抄本机的机器名或绝对路径。
不复制 root store receipt，不自行改目录，不默认添加 `--update-environment`。
正常启动可能同步 vphoned，但不代表完整 guest 环境/内核已更新。核对实际进程路径，
不能只看绑定文件；PROCESS-PATH 代理规则可能依赖旧路径，须按目标机实际配置验收。

## 验收和回退

- 核对已安装 App 版本、Helper ready、业务入口、旧数据、原资料库和逐机 Core 绑定。
- 当前实例能启动解锁；Never 设置有效，空闲至少两分钟仍不锁屏。
- Threads 新建空白帖 → 选图 → 点关闭按钮中心；重复测试宿主像素 tap 和 guest 点坐标。
  从实时 `device.screen` 和 UI tree 获取尺寸，不能把本机 `(126,435)` 写死到其它设备。
  不选图、不发帖，结束后取消空白页。已做全屏/边缘手势回归才能声明其通过。
- 本机升级前快照是 `before-core-215-20261103`。其它 Mac 使用自己的快照名和旧绑定。
  回退先停机、恢复原 Core 绑定并启动；guest 持久变化需要时按自己的快照恢复。
  回退 Launchpad 使用备份的完整签名 App，不重建 VM，不清空业务数据库。

现场证据与准确范围见 [本机验收记录](../../Research/Host/upstream_2_15_0_upgrade_20261103.md)。
