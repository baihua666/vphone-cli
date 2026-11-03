# 临时 App 实测 PassKit 与 SE 查询

时间：2026-10-23 11:35–11:43，北京时间。用户明确授权在现有 `5-20261023` 安装临时诊断 App，读取原生能力与 SE 信息，检查完卸载；不改系统、不绑卡。

## 结论

后续 [错误 58 分析](nfcd58_vm_guard_analysis_20261023.md) 已确认同版原始 nfcd 的显式 VM unsupported 分支。下文“控制器／硬件后端层”只描述接口返回层次，不能解释为已经尝试硬件通信后超时；58 也会由 readiness gate 统一生成。

进一步的 [最小运行验证](nfcd_vm_guard_runtime_probe_20261023.md) 已测得 `NFProductIsVM() = 1`，并确认客体 nfcd 完整哈希／UUID 与分析文件一致，强力支持 VM gate 解释；临时 App 已卸载、实例已停止。

公开 PassKit API 确认：票券库可用，支付与银行卡添加能力不可用。普通 App 的 NearField 直接查询先被沙箱拒绝；只给临时 App 添加 hardware manager 查询权限后，nfcd 接受连接，但控制器查询返回 **`nfcd / 58: Unresponsive hardware`**，SE 列表为 nil。

因此，当前已实测到的最深失败在 nfcd 的控制器／硬件后端层，尚未进入 SE 个性化、账号／发行方绑卡或支付流程。结合 [此前 IORegistry 检查](wallet_se_readonly_probe_20261023.md) 的设备缺项，支持继续研究虚拟控制器／SE 后端；**不能仅由此区分未提供硬件、驱动不匹配、设备树未注册或硬件初始化失败**。

## 环境和方法

- 实例：`5-20261023`，资料库 `/Users/tubao/.vphone/init-test-20261022`，原绑定 `2.8.0-local.199abaf3`；未重新绑定或更新 guest。
- App：`com.tb.vphone.walletprobe.temp20261023`，首次查询已确认不存在；独立 User 应用，以 UID/EUID 501 运行，iOS 26.6.2。研究环境的签名／沙箱不宣称与零售真机等价。
- 沿用 `tests/guest_probe/main.m` 的独立 UIKit App、容器内报告模式；在 Git 忽略的 `.build/validation/wallet-native-probe-20261023/` 编译新探针，不修改产品代码或原测试探针。
- 使用 Xcode iPhoneOS SDK 编译 Objective-C，依赖 UIKit、Foundation、CoreGraphics、PassKit；无需 Python、新运行时或后台服务器。源码 SHA-256：`2c50c18a4f17ccb169edf8ea2ff6478fb6ac5f6704d448bad11ba247444623dd`。
- 通过 Launchpad `files.write` 上传约 19 KiB IPA，使用既有 `apps.install` 签名／容器安装路径，`apps.launch` 启动。不是 installd 路径验证。
- 报告仅写 App 自身 Documents；SE 返回值仅保留是否存在、类型、数量、字段名，不保存 SEID、证书、密钥或银行卡数据。
- 私有接口在当前 guest 运行时核对方法签名后调用，使用 8 秒超时状态记录；没有开始任何支付、读卡、SE 管理或写入会话，也未关闭沙箱。

## 实测结果

| 查询 | 普通 App 基线 | 仅添加硬件管理查询权限 |
| --- | --- | --- |
| `PKPassLibrary.isPassLibraryAvailable` | true，两次一致 | true |
| `PKPaymentAuthorizationController.canMakePayments` | false，两次一致 | false |
| `canMakePaymentsUsingNetworks: [Visa, MasterCard]` | false | false |
| `PKAddPaymentPassViewController.canAddPaymentPass` | false，两次一致 | false |
| dlopen NearField | 成功 | 成功 |
| `NFHardwareManager.sharedHardwareManager` | 对象存在 | 对象存在 |
| `controllerInfo` | nil | nil |
| `controllerInfoWithError:` | `nf.fwk / 7: No connection to nfcd` | **`nfcd / 58: Unresponsive hardware`** |
| `secureElements` | nil，受沙箱拒绝影响 | nil；不能标为空数组或设备数量 0 |
| 旧 `getSecureElementInfo` | 当前运行时无此 selector，未调用 | 同左；不是硬件不存在的证据 |

基线 PID 490，重启复测 PID 524，权限对照 PID 576；三次报告均 `finished=true`，没有超时或异常。报告源 SHA 与本地编译源码一致。

无卡时支付网络查询 false 本身可属正常；这里结合一般支付能力、添加能力及底层错误解释，不单独把网络查询 false 视为故障。添加能力也受账号、用户限制和授权上下文等影响，不能由单个布尔值断言硬件根因。

## 权限对照与根因边界

普通 App 安装后仅带既有安装器添加的容器／研究 trust 属性，没有 NearField 权限。客户端日志明确记录：

```
com.apple.nfcd.hwmanager
Connection init failed at lookup with error 159 - Sandbox restriction.
NSCocoaErrorDomain Code=4099
```

只读核对现有 Wallet 的签名声明后，临时 App 第二个包仅新增：

```xml
<key>com.apple.nfcd.hwmanager</key><true/>
<key>com.apple.security.exception.mach-lookup.global-name</key>
<array><string>com.apple.nfcd.hwmanager</string></array>
```

没有添加 no-sandbox、payment provisioning、ecommerce、reader、SE session 或任何写卡权限；通过项目现有签名安装流程更新同一个临时 App。签名声明仅用于此研究 guest，不代表获 Apple 正式分发资格。

第二次 daemon 日志有 `Added connection from TBWalletProbe`、`registered callback`，客户端控制器查询错误改为来自 `nfcd` 的 58。说明查询已越过第一次的 sandbox lookup 失败，不应再把第二次结果归为同一个权限错误。daemon 另有 application-identifier 缺失的 `ignoring` 提示，保留该上下文；不能宣称临时 App 具备正常发行方资格或系统 Wallet 全部权限。

日志的 guest 时间是 2026-10-22T15:25:59Z 附近，与宿主检查时钟不同；本轮未改 guest 时间。以 PID 524/576、重新启动记录和阶段归档对应，不将 guest 日志时间冒充北京时间执行时间。

## 验证与清理

- clang 编译、签名、ZIP 校验通过；App 启动时 nil／数组脱敏和 JSON 结构的 assert 自检通过，否则不能进入报告流程。
- 对基线、重启复测、权限对照报告执行 jq 断言，验证 finished、UID、关键布尔值及 nfcd 错误 58；均通过。未在真机或官方 Simulator 做对照，不推广为所有 vphone 版本结果。
- 卸载使用用户已授权的 `apps.uninstall force=true`；返回已删除 App bundle 容器与数据容器。复查 App 列表无该应用、进程数量 0、上传 IPA 路径无残留，并单独确认两个容器路径不存在。
- 最后通过 Launchpad 正常停止本轮启动的实例，恢复开始时停止状态。未修改任何系统／host 安全配置、配对记录、账号、固件或其它实例；未尝试绑卡或交易。
- 主机保留源码、构建物、报告、实际 entitlements、日志、卸载与最终状态证据在 `.build/validation/wallet-native-probe-20261023/`；目录 0700，报告／日志 0600。临时 App 在 guest 已清理，正常系统日志和历史不做删除。

下一步若继续研究，应围绕 nfcd 的控制器初始化与当前虚拟硬件接口取证；增加 merchant ID、伪造 SEID 或尝试银行卡不能修复已观测的这一层错误。
