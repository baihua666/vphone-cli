# Launchpad 应用管理

2026-10-23，本地测试功能。部署及真实验收见 [现场记录](../../Research/Host/launchpad_app_management_deployment_20261023.md)。

首次在其它 Mac 使用前，按 [部署指南](launchpad-mac-setup.md) 配置签名、实例和 ARM 私有会话。

## 使用

主窗口工具栏「应用管理」打开独立单实例窗口。默认扫描 Downloads 顶层与
`~/Library/Application Support/vphone-launchpad/Applications`；导入 IPA 时校验并复制到应用库。
显示包内名称、Bundle ID、真实版本与文件路径。选择目标后可读取已安装列表、安装本地包，
或从 ARM Store 搜索并选择仅下载／下载并安装。下载可能消耗账户额度，复用有效的 0600 私有会话文件。
搜索使用 Apple 应用目录（与 ARM Store 前端相同）；下载使用已有 ARM Store 下载器。
商店标称版本与包内真实版本可能不同，以本地包及客体读回结果为准。

本地列表在选择目标机、重新打开窗口、目标机启动和安装完成后读取已有 `apps.list`。
「刷新」同时刷新本地包和客体版本；「读取已安装」可单独刷新客体。
按 Bundle ID 匹配，先比较版本号，再比较同版本的构建号；本地较新显示「升级…」，
一致显示「已是最新版本」，客体较新显示「虚拟机版本更高」，不存在才显示「安装…」。
这里的最新仅相对于当前本地包，不承诺 ARM Store 最新；右侧菜单保留显式重装／降级确认。
读取失败不当作空列表，版本或构建缺失/不可比较不猜测最新。切换实例时清空旧状态，
晚到的旧请求通过目标路径和请求标识校验丢弃，避免不同资料库或实例串用已安装状态。
版本字段依据 [CFBundleShortVersionString](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring)
与 [CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)。

新版 Launchpad 启动实例时使用原 Core 已有的 `--api-listen 127.0.0.1:0`，动态分配本机端口，
沿用 Core 每次启动生成的认证令牌。Launchpad 对该启动进程设置 `NSUnbufferedIO=YES`，
使原 Core 的连接信息立即写入日志，避免等待标准输出缓冲。连接信息只从所选实例的私有启动日志读取，日志权限 0600，
不显示或记录令牌到应用管理状态。旧的运行会话若没有启用 API，会提示从 Launchpad 重新启动实例；
不会自动重启、更换 Core 或升级 guest。每次操作以完整 library/name 路径定位，不按 UDID 混用。

安装流程：先通过实例 socket 读取 apps.list 确认连接 → 校验 IPA → files.mkdir →
已有 HTTP PUT `/v1/files/content` 流式上传 → 已有 socket RPC `apps.install` → 删除临时包 → apps.list 读回。
上传仅允许本机地址和当前会话令牌，不跟随 HTTP 重定向。安装等待上限 660 秒，失败不自动重试。
若安装超时，不删除客体可能仍在读取的临时包；显示路径并要求先核对实际安装状态。
安装成功的读回不代表应用业务登录或联网功能已验证。

### 安装失败后的临时 8 GB 重试

已提交安装但失败或读回未确认时，原内存小于 8 GB 的实例会出现确认弹窗。用户可以取消，
先读取已安装列表；选择「确认增配并重试」才会停止目标实例。停机可能中断仍在执行的安装，
不把 RPC 超时当作取消成功。损坏包校验失败、上传失败和尚未提交安装的连接错误不触发增配。

确认后固定完整资料库/实例路径，重新读取实际内存及绑定；原内存若已达到 8 GB 则不执行。
流程为正常停止 → 既有 `vm config --memory 8192` → 原 Core 启动并等 guest ready →
重新读取本次启动的上传连接 → 上传及安装一次 → 正常停止 → 恢复实际原内存 → 启动并等 guest ready。
原值可能是 3 GB、4 GB 等，不能写死恢复成 4 GB。安装失败同样执行恢复；不会更新 Core 或 guest。

第一步停机之前，在 Launchpad 自己的 Application Support 下写入
`install-memory-recovery.json`，保存目录设备/inode 身份、原绑定及原内存。
关闭应用管理窗口不取消流程。Launchpad 退出或被强制结束会延后恢复；下次启动自动只补做恢复，
不重新安装。恢复失败保留记录、显示错误，并提供「恢复原内存并启动」。目录身份或 Core 绑定
变化时拒绝对新对象操作；同名替换不会被误恢复。记录损坏时不覆盖、不猜测原内存。
不能保证机器断电、磁盘不可用或启动失败时即时恢复，必须保留明确的待恢复状态。

恢复期间在 Launchpad 内保留目标实例操作锁，阻止该实例的启停、配置、绑定和其它冲突写操作；
不同实例保持可用。这不是对另一个宿主 CLI 进程或手工编辑文件的系统级锁。

独立开关 `VPHONE_CUSTOM_TEMPORARY_INSTALL_MEMORY` 在同一 xcconfig 中由
`VPHONE_TEMPORARY_INSTALL_MEMORY` 默认启用；传空关闭此恢复 UI、启动恢复及操作锁，基础应用管理仍可用。
关闭或删除功能前必须完成所有待恢复记录；关闭编译宏不能撤销已经写入的内存配置。
删除时一并删除 `TemporaryInstallMemory.swift`、Launchpad 的两个 Recovery/InstallMemory 实现文件、
模型/View/平台生命周期与机器操作的条件接入点、测试及该宏配置。

## 边界与回退

- `Integrations/ApplicationManagement` 保存本地库、下载、安装编排及现有 HTTP 协议适配；
  下载脚本编译同一 ARM Store 源文件，避免复制下载协议。
- Launchpad `Applications/` 负责 UI、选中实例 socket 适配及私有启动日志；启动入口仅增加条件组装。
- 本功能不新增 Core/CLI/guest/helper 命令；只有明确确认的临时增配流程通过既有 CLI 修改并恢复内存配置，不改绑定或固件。
  早期新增的 `application_capabilities`／`application_install` 和 VMKit 宏定义已撤销。
- `VPHONE_CUSTOM_APPLICATION_MANAGEMENT` 仅由 Launchpad 的
  `Configuration/VPhoneLaunchpad.xcconfig` 通过 `VPHONE_APPLICATION_MANAGEMENT` 定义，默认开启。
  构建参数 `VPHONE_APPLICATION_MANAGEMENT=` 关闭窗口、按钮、安装入口及启动 API 参数。
  已经运行的进程不会因重新编译自动关闭监听；正常停止后由关闭功能的 Launchpad 再启动才回到基础启动路径。
- 删除功能时删除 Applications 目录、独立 package/脚本引用、App/RootView/启动组装点及宏定义。
  缓存 IPA 和已安装客体应用不自动删除。官方版本号不变，实例保留原 pinned Core。
- 尽量避免修改 CLI/底层；确需修改必须先说明原因、最小范围和影响，并经用户明确确认，见根 AGENTS.md。

## 验证

11 个 package 测试通过，覆盖版本/构建数字比较、缺失版本、客体列表解析，以及临时内存正常恢复、各阶段失败、取消后恢复、恢复失败保留记录、记录重开，
以及下载参数、目录/损坏包、真实 ZIP 元数据/去重、安装读回、
断线不上传、上传失败不安装、安装超时不重试及不删除输入、会话端点/令牌校验。
Launchpad 功能开启和关闭构建均通过；不再构建或部署 Core。
`zsh VPhoneLaunchpad/Tests/InstallMemoryRecoveryTests.sh` 编译实际 Launchpad adapter，使用隔离生命周期
测试替身验证命令参数、成功/失败恢复、同名不同库操作隔离、重开只恢复、Core 变化及同名目录替换拒绝。
临时内存独立关闭、应用管理全部关闭及开启构建均验证；真实部署/界面验收状态见现场记录。
上传依据已有 guest API 协议；系统流式上传使用
[Apple URLSession upload](https://developer.apple.com/documentation/foundation/urlsession/upload(for:fromfile:delegate:))。

2026-10-23 UI 修正：请求期间不再禁用整窗，应用来源页签保持可切换，本地列表可浏览和筛选。
本地筛选与 ARM Store 查询分开保存；涉及安装／下载／导入／刷新等动作仍串行，防止重复执行。
该修正仅涉及 Launchpad View，不改 Core 或 CLI。构建及签名校验通过；实际部署以现场记录为准。
