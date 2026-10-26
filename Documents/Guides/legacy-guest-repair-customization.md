# 旧实例修复的静态 Hook 隔离

本地修复不再混入上游补丁选择器。使用编译期启用的静态 Hook，原入口保留少量调用点；不使用运行时方法替换、动态注入或通用插件框架。上游没有覆盖这些步骤的现成扩展接口，因此这里是最小接入修改，不宣称零源码侵入。

## 文件归属

| 位置 | 职责 |
| --- | --- |
| `VPhoneExecutable/VPhoneCommand/FirmwarePatcher/Customizations/LegacyGuestRepair/` | 无计划实例的补丁策略、实际内核 OID 识别、配对校验、标记路径 |
| `VPhoneExecutable/VPhoneCommand/VPhoneCommand/Customizations/LegacyGuestRepair/` | 静态 Hook、只读 Preboot 检查、通过既有受限写入接口安排缓存失效 |
| `VPhoneDaemon/Daemon/Customizations/LegacyGuestRepair/` | 只读判断修复标记是否比能力缓存更新 |

上游 `FirmwareGuestPatchResolution.swift` 已恢复原样。安装器仍拥有挂载生命周期、受限目录、实际写入与撤销流程；Hook 通过闭包使用其现有内核读取和标记写入能力，不创建第二套安装器。仅将 `WorkDirectory`、`openGuestVolume`、`tool` 从类型私有改为同模块可见，以便独立 extension 复用，检查逻辑不变。

guest 原入口只增加一个判断调用，仍由原 `GuestMobileGestaltCache` 删除缓存、记录 boot session 和报告 restart_pending。Hook 自身不删除文件、不重启客体。

## 编译开关

实际 Swift 条件为 **`VPHONE_CUSTOM_LEGACY_GUEST_REPAIR`**。CLI 项目中 VPhoneCommand、FirmwarePatcher、FirmwarePatcherTests，以及 Daemon 项目的 vphoned，在各自既有 Debug / Release 构建配置中集中声明：

```text
VPHONE_LEGACY_GUEST_REPAIR = VPHONE_CUSTOM_LEGACY_GUEST_REPAIR
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) $(VPHONE_LEGACY_GUEST_REPAIR)
```

默认开启，保留已修复的行为。VPhone bundle target 的 Debug / Release 配置也声明相同默认值，并用 `VPHONE_LEGACY_GUEST_REPAIR_FORWARD = condition:$(VPHONE_LEGACY_GUEST_REPAIR)` 保留显式空值（Xcode 不导出空构建设置）。整包构建的 `StageBundle.sh` 去掉此前缀，将实际设置传给嵌套 xcodebuild，确保宿主、补丁模块和 guest 一致。关闭时使用空值，而不是 `0`：

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/legacy-guest-repair/DerivedData \
  VPHONE_LEGACY_GUEST_REPAIR= build
```

关闭后修复策略不进入 FirmwarePatcher；宿主 Hook 返回无覆盖结果，不调用内核读取或 guest 标记写入闭包；guest Hook 返回 false，不读取标记。无计划实例恢复上游原有策略，**包括原来的实验补丁默认开启问题**，因此关闭包仅用于验证基础路径和后续移除，不用于尚未处理的旧实例。

`patch-dsc-revert` 的两个通用完整性修正仍保留在原文件：读取失败不能当作没有日志；完成全部签名页校验后才清理 undo 记录。它们不是本地策略 Hook，不受该开关控制，应单独向上游提交。

## 验证与维护

- `FirmwareLegacyGuestPatchTests` 验证开启时的实际内核识别、实验 opt-in 和配对策略；关闭时不注册此本地测试套件。上游选择器和 DSC undo 回归在两种状态都运行。
- `VPhoneExecutable/VPhoneCommand/Tests/run-legacy-guest-hooks-disabled-tests.sh` 编译真实关闭状态的宿主 Hook，验证内核读取次数和 guest 写入次数都是零。
- `VPhoneDaemon/Tests/run-mobilegestalt-cache-tests.sh` 分别编译开关两种状态，以真实临时文件验证时间判断、重建缓存保留、Hook 不删除缓存，以及 host / guest 标记路径契约。
- 完整 VPhone bundle 必须分别构建和验签；单独 Swift 测试不替代最终宿主和 iOS guest 构建。

合并上游时优先检查安装器 Hook 调用附近的挂载、撤销、提交次序和原缓存失效入口。上游提供等价修复后，删除三个具名目录、原入口的调用点、相应测试与编译配置，并移除 StageBundle 的开关传递；保留或合并通用签名完整性修正。不要把策略重新散回上游选择器。

关闭宏或删除源码不能撤销已经写入的 guest 文件和缓存。本次结构整理不安装新 Core、不修改实例绑定、不重启 VM。已部署修复包仍为 `2.13.4-local.1da558c7`；数据回退须单独使用已保留快照，见 [实际修复记录](../../Research/Host/black_screen_legacy_guests_20261026.md)。
