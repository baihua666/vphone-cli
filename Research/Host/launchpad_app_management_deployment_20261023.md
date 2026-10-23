# Launchpad 应用管理部署验收（2026-10-23）

用户明确要求更新当前 Launchpad，复用 ARM Store 会话，完成真实下载及虚拟机安装。

## 已完成

- 部署前 Launchpad CLI status：5 台实例，running=0，无安装任务，Helper ready (15)。
- 另一个 vphone 会话正在独立 NFCNoRF 宿主研究，没有 guest 操作；本次不触及其测试实例 5。
- Launchpad 以原安装团队身份重建，签署 debug dylib、preview dylib、helper、CLI、launcher 和外层 app。
  `codesign --verify --strict --deep` 通过。旧 app 备份在忽略目录
  `.build/validation/app-management-deploy-20261023/previous.app`。
- 已替换 `/Applications/vphone-launchpad.app`，真实窗口显示应用管理入口、本地 IPA 和在线搜索。
  安装后的 debug dylib 与构建产物 SHA-256 均为
  `54c12bb607a5bef93b897746a41f9516104b601c41ae4568245527267a0ecdf9`。
- 旧 ARM Store Cookie 实际返回 401；在 `https://armconverter.com/store/us/389801252`
  正常点击 Sign In，现有 iOSGods 会话自动续期成功。重新导出至既有 0600 私有文件，未输出凭据。
- 在真实 Launchpad 搜索 Instagram，点击仅下载，最终页面明确显示下载完成。
  下载包：`~/Library/Application Support/vphone-launchpad/Applications/389801252-452.0.0.ipa`，305 MiB。
  ZIP 完整性检查通过，Bundle ID `com.burbn.instagram`，包内版本 `452.0.1`。
  SHA-256：`2a237f532b3eb34c9aa0c65eed799e701e5cb08de1e363921c7600d405e49db1`。
- 启用应用管理宏的完整 Core Bundle 构建成功。经现有 Launchpad CLI `bundle install-local --keep-default`
  发起安装；真实标识 `2.8.0-local.5e1720bf`，由签名内容哈希产生，未修改官方版本。

## 早期部署记录（已由下述方案取代）

管理员认证后 `2.8.0-local.5e1720bf` 安装到版本库，但未绑定实例、未设为默认。
用户随后明确要求业务优先在 Launchpad，撤回应用管理专用 Core 扩展。本次未移除该未绑定的历史测试产物，
它不是应用管理的运行依赖；不再按早期计划切换 Core。

## 最终实现与实装验收（2026-10-23 21:07 北京时间）

- 已撤掉 `application_capabilities` / `application_install`、对应 CoreKit import，以及
  Virtualization 项目的应用管理宏定义。宿主文件中其它会话的 native proxy 改动保留。
- 安装编排移至 `Integrations/ApplicationManagement`，Launchpad 通过原有 `--api-listen`
  和 HTTP PUT 上传、socket RPC `apps.install` 安装。没有新增 CLI/guest/helper 协议或改固件。
- Launchpad 启动参数只监听 `127.0.0.1:0`，每次启动沿用 Core 生成的令牌。
  原 Core 的 stdout 缓冲导致首次上传前找不到连接信息；首次未发起上传或安装。
  修复只在 Launchpad 的 spawn 环境设置 `NSUnbufferedIO=YES`，然后重启目标。
  每实例日志在启动前设为 0600；凭据不进入本记录。日志缺少端点时明确要求重新启动，不升级 Core。
- 最终 `/Applications/vphone-launchpad.app` 已签名部署，`codesign --verify --strict --deep` 通过。
  debug dylib SHA-256：`7c92888921b5ab561581145cd5087b7d64d0fda306d52e03ab9ff15367406c38`。
  最终保留系统已安装 Helper 对应的随包二进制，SHA-256 与系统文件一致；未更新系统 Helper。
  完整签名启用产物保存在验收目录 `final-enabled.app`。
  原 app 与第一版 app 的备份均位于 `.build/validation/app-management-deploy-20261023/`。
- 真实目标 `~/.vphone/machines/1-20261023`，宿主与 guest 环境仍为 `2.8.0-local.199abaf3`；
  `launchpad.json` 与部署前备份一致。其它四台实例均停止且保留原绑定。
- 本次验收通过临时 Swift 验收程序调用与 Launchpad 相同的实际 `VPhoneApplicationInstallation`、
  `VPhoneApplicationConnection` 和原 socket 适配代码，不使用 mock，也未新增产品命令或验收入口。
  UI 的按钮连接经实际 Launchpad 构建验证；真实 UI 完成了读取已安装并显示状态，未声称通过 UI 点击执行安装。
- 使用本记录上方刚从 ARM Store 下载的 IPA（320124612 bytes），真实顺序为
  apps.list → files.mkdir → HTTP 上传 → apps.install → files.remove → apps.list。
  `install-original-core.log` 记录 `Installed and verified: true`。原目标已有同版本 Instagram，
  本次是确实上传并重新安装新下载包，不是仅发现已有应用后报成功。完成后客体暂存目录为空。
- apps.launch 返回 PID 440、frontmost_verified=true；每 5 秒读取一次运行列表，共 4 次／20 秒，
  均读到 `com.burbn.instagram`、452.0.1、PID 440、running。
  apps.foreground 返回该 bundle ID、verified=true。截图确认实际 Instagram 欢迎页。
- 应用管理窗口选中完整目标路径并读取客体，显示新下载 IPA 和“目标机已安装”。
  截图：`launchpad-installed-final.png`；guest 截图：`instagram-original-core.jpg`，均在上述验收目录。
  没有进行账号登录或登录后联网功能测试。目标保持运行供用户查看，其它机器未启停。
- Package 4 个测试通过；最终代码的功能开启／关闭两种 Launchpad 构建均通过，`git diff --check` 通过。
  已安装的是开启功能的最终签名产物；`.build/LaunchpadDecodo` 最后用于关闭开关验证，
  后续部署前应按默认开启配置重新构建并签名，不能直接复制该关闭功能的缓存产物。
- 开发约束已写入根 `AGENTS.md` 和 `Documents/Guides/architecture-boundaries.md`：业务优先在
  Launchpad，尽量不修改 CLI/底层；确需修改时先解释原因、最小范围及影响，取得用户明确确认。

所有产物均为本地 test，未声明正式发布。

最终 Helper 匹配修复后再次核对：helper=`ready (15)`、hostReady=true、canInstallBundles=true；
原 Core 启动后再次成功启动 Instagram。该修复只恢复 app 内原有 Helper 副本并重签外层 app，
没有安装／升级系统 Helper。目标仍保持原绑定运行。

## 应用来源切换修复部署

用户确认允许停止并恢复当前实例后，部署 `.build/validation/app-tab-switch-20261023/vphone-launchpad.app`。
仅停止并恢复 `1-20261023`，保留原 Core 与 Helper。构建、签名及 Helper 一致性检查通过。
真实界面发起在线搜索后立即切回本地列表成功；本地筛选不沿用在线查询。
顶部未选择目标时安装按钮禁用；选中 `1-20261023` 且无任务执行时按钮正常可用。
请求中的安装／下载等动作仍串行，页签切换和本地浏览筛选不受限制；本次未触发任何新下载安装。
恢复实例时首次 guest 控制连接未就绪；使用原 Core 正常停止并重启一次后，vphoned 在 7 秒响应，
原 socket ping 返回 ok=true，随后执行原有解锁操作。未修改 Core、guest 或固件。
