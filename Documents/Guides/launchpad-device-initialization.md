# Launchpad 创建后的设备初始化（2026-10-22）

## 范围与完成条件

原创建流水线的 `firstBoot` 只等待 vphoned ping，不证明自动化可用。
本业务版本在 `VPhoneLaunchpadModel` 组装处默认注入设备初始化闭包，
`VPhoneLaunchpadMachineLibrary` 将闭包传给创建流水线。流水线仅保存可选
`DeviceInitializer`，不知道 Never、观察时长或具体 guest 调用顺序。
有注入时追加 `initializeDevice`，通过后才算业务就绪；没有注入时，步骤列表、
UI、CLI 状态报告都以 firstBoot 结束，基础创建不调用业务策略。
现有 `failedStep` / `start(from:)` 保留先前状态，初始化失败后不重跑
prepare、restore、CFW 或 firstBoot。显式重试未启用的扩展会报错。

策略和薄适配器位于 `VPhoneLaunchpad/Business/DeviceInitialization/`。
这是当前只被 Launchpad 使用的隔离业务目录，没有新增通用插件框架或 SwiftPM
app target；有真实跨 target 复用需求时再提取 library。CoreKit 与原生 CLI
不再承载此业务策略，先前新增的 `vm initialize` 命令已移除。

适配器使用所选实例的 `vphone.sock` 和绑定 bundle，不使用全局默认运行时。
业务策略通过注入的异步 RPC、时钟和等待操作调用底层原子能力。
先读取 `display.auto_lock.set_supported`，不支持则在修改前失败；然后：

1. 调用已有 `screen.unlock`，确认 unlocked / screen on。
2. 调用 `display.auto_lock`，参数 `{"never":true}`。
3. 读回 `auto_lock_seconds == 2147483647`、`never == true` 和
   `lock_screen_minimum_seconds == 2147483647`。
4. 调用已有 `system.respring(force:true)`，再调用 `screen.unlock`。
5. 每 5 秒只读 `device.screen`，用单调时钟观察至少 120 秒；任一锁定、
   黑屏、缺字段或通信错误均失败，最后再次读回自动锁定设置。

不删除密码，不跳过 Setup Assistant，不通过周期输入伪造常亮。
用户或其它自动化在观察期操作设备会影响结论，日志提示保持设备空闲。
设置写入后验证失败会保留已提交的 Never，不回滚其它用户设置。
通过所有验证后，适配器才调用绑定 CLI 的 `vm config --unlock-at-startup on`。
等待使用可取消的异步计时器，不在主线程 sleep。取消后不继续后续设置动作；
已发出的 guest 请求可能执行到结束，适配器在返回后再次检查取消。

## 系统设置写入

`vp_auto_lock_never` 运行时加载 ManagedConfiguration，解析导出的
`MCFeatureAutoLockTime`，调用 `MCProfileConnection.sharedConnection` 的
`setValue:forSetting:` 和 `flush`。Swift 最多等待 10 秒，从已有的
EffectiveUserSettings.plist 读取系统生成的有效值；不直接修改此生成文件。
随后复用 `GuestLockScreenIdle` 写入锁屏页偏好；重启生效规则见
[锁屏空闲计时研究](../../Research/Guest/lock_screen_idle_timer.md)。

真实新建虚拟机测试发现，daemon 必须带
`com.apple.managedconfiguration.feature-setting.maxInactivity` 才能让 profiled
接受写入；仅调用 setter 不会抛错，必须保留写后读回检查。随后调用的现有
`IcliKit.respring` 在 FrontBoard 未完成重启时通过 launchd stop 回退，按固定
依赖的 `Docs/entitlements.md` 还需要 `com.apple.private.xpc.service-configure`。
这两项均在 daemon 自己的 entitlements 声明，由原生测试检查，并须核对最终
签名的 guest 二进制；宿主 app 的签名权限不能替代它们。

同次实测还发现 SpringBoard 的 PID 更新后，锁屏通知可能短暂保留旧的
unlocked 值。通用 `system.respring` 成功后通知 `GuestScreenUnlock`：下一次
解锁在原 RPC 超时内等待新锁屏出现，再复用原有解锁按键逻辑；超时仍未出现
则使用最终状态。该标记由现有互斥锁保护，只消费一次。业务策略不增加按键
保活，也不在 120 秒观察期自动重解锁。`run-screen-unlock-tests.sh` 编译实际
解锁代码，覆盖立即出现和延迟出现锁屏的回归。

接口签名依据 MCP 读取的
[运行时导出头](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/ManagedConfiguration.framework/MCProfileConnection.h)。
这是私有 API 的逆向声明，不是 Apple 的公开支持承诺；缺符号、缺方法、异常
和写后未生效均报错，不冒充完成。仍需用目标 guest 实测 profiled 是否接受
该 daemon 的设置请求，以及 Settings 页面、重启持久性和真实空闲状态。

## 版本与验证

源码产品版本沿用实际合入的官方基线 2.8.0，本地构建以 `2.8.0-local.<构建标识>` 区分；此前本地自行标为 2.9/2.10 的产物属于历史错误命名，不代表已同步相应官方基线。下文保留真实验收时的包名供追溯，不重命名已安装包或实例绑定。移除业务 CLI 接口后，不以本地扩展扩大基础操作的版本下限。
Launchpad 全局最低 Core Bundle 为 2.8.0；原生代理按实际能力独立检查，
不随本业务初始化扩大。新 guest 通过读响应的 `set_supported` 明示写能力。
绑定 2.9 宿主且缺少 guest 写能力时，只会在初始化步骤失败；原有机器操作仍
使用原来的兼容判断和 pinned bundle，不自动重新绑定、更新 guest 或升级已有实例。

- 独立业务策略测试覆盖成功顺序、120 秒无输入观察、旧 guest、写入未生效、
  锁屏/缺字段、断连、respring 失败、重复执行、失败后重试、最终设置变化和取消。
- native 测试编译真实 setter，只替换 framework 加载和 MC 连接，覆盖设置值、
  flush、缺符号/方法和系统拒绝。
- 流水线测试编译真实 pipeline 与适配器，替换业务执行和外部传输，使用真实 Unix
  socket 响应 firstBoot ping：验证注入/停用、firstBoot 状态保留、独立重试、
  2.9 pinned bundle/library、响应格式错误和成功后启用开机解锁。
- 版本/绑定测试覆盖 2.9.x 仍兼容、2.10.x 兼容，以及既有 2.8 下限拒绝。
- 构建与签名结果见研究日志的“初始化策略隔离”条目。
- 2026-10-22 已部署到本机真实 Launchpad，新建 `init-check-01` 完成真实 guest
  初始化、120 秒无输入观察、Settings Never 勾选和失败后独立重试。冷启动不发
  手动解锁输入，宿主自动解锁后实际显示桌面，连续约 156 秒保持 unlocked/lit。
  最终核心为 `2.10.0-local.199abaf3`；测试机已正常停止并保留。
- 旧机绑定和配置哈希保持不变，但部署期间发生运行中断并按原运行时恢复，
  不得把本次结果称为“完全不影响现有运行态”。详细失败、修正和证据见
  [研究日志](../../Research/debug_journal.md#j-2026-10-22--初始化部署实测中的权限和迟到锁屏)。
