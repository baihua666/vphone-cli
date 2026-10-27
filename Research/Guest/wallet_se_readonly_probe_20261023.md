# 现有 vphone 的 Wallet／SE 无卡只读检查

时间：2026-10-23 11:28–11:33，北京时间。用户授权检查现有机器，不改系统、不尝试绑卡。

## 结论与边界

后续用户授权临时 App 后，已取得原生返回值和 nfcd 错误 58；见 [原生探针实测](wallet_native_probe_20261023.md)。本文“未执行”仅描述前一阶段，不代表后续仍未执行。

Wallet 主程序和支付后台服务都存在并能运行；现有 IORegistry 的名称／类枚举中没有找到 Stockholm、NFC controller、支付 Secure Element 或 AppleSSE 节点，只看到虚拟 SEP。**当前最靠前的可见缺口是支付设备／驱动注册层**，而不是 Wallet 被删除或 nfcd 没启动。

这不是取得原生 SE 查询错误后的精确诊断：现有 RPC 不暴露 PassKit／NearField 调用，USB 调试枚举返回 `escrowFailure`，所以 `canMakePayments`、`canAddPaymentPass`、`getSecureElementInfo` **没有执行，结果未知**。不能把调试通道失败当作 SE 不存在的证明，也不能把名称检索当作对全部私有实现的穷尽证明。

本轮未进入 Apple Account 登录、绑卡、交易或 applet 管理；未修改固件、系统文件、设置、权限、配对、版本绑定，也未安装 App、bootstrap、Frida server 或调试组件。普通开机、打开 Wallet 和关机会产生正常运行状态／日志写入，不声称整个磁盘逐字节不变。

## 实例与运行环境

- 选用现有测试库实例 `5-20261023`，目录 `/Users/tubao/.vphone/init-test-20261022/5-20261023`；其它四台保持停止，不新建或克隆。
- 开始时所有实例均停止；使用已安装的 `/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli`，`vm start 5-20261023 --headless --wait --timeout 180`；14 秒后 vphoned 连通。
- 宿主与 guest environment 均绑定 `2.8.0-local.199abaf3`；历史 bootChainBundle 为错误命名的 `2.10.0-local.36ee25a1`，本轮原样记录，不改写历史。
- Launchpad 报告 iOS `26.6.2 (23G90)`、cloudOS `26.4 (23E5207q)`；guest 报告 kernel `25.4.0`、model `iPhone99,11`。
- vphoned 报告摘要 `93863283706957ecf7e0dc1309548340b187a28be6fd5f89245b19716dd26501`；未另读 daemon 全文件核验。
- Developer Mode 已启用；未检测到 bootstrap／jbroot。开机早期一次状态采样为 locked，后续 UI 报告已解锁；两次 USB 调试枚举都失败，因此不能仅按首次锁定解释失败。

## 实际检查

| 层次 | 检查 | 实测 |
| --- | --- | --- |
| 管理通道 | Launchpad 状态、绑定与 guest RPC | 正常 |
| Wallet 程序 | `apps.search`，按确认过的 `com.apple.Passbook` 启动，读取前台和 UI | 主程序存在，启动后 PID 482，前台身份验证为 Wallet |
| Wallet 界面 | 读取 accessibility 与截图 | 显示 Passes and Tickets、Get，以及 add/search/more；主页面没有银行卡／Apple Pay 引导，未点击任何入口。这个显示也可能受地区／账号等影响，不能独立用作硬件结论 |
| 后台服务 | `processes.list`、`services.list/print/status` | `nfcd` PID 60、`passd` PID 85；`nfcd` 运行，runs=1，没有退出记录 |
| 服务端点 | `services.print com.apple.nfcd` | `com.apple.nfcd.hwmanager`、`service.corenfc`、`wallet.presentation` 活跃；端点活跃不等于 SE 硬件初始化成功 |
| 软件资源 | 只读列举 `NearField.framework` 目录 | 有 Info.plist、模型资源和签名目录；目录不见独立 Mach-O 不能当作缺框架，代码可能在 dyld shared cache |
| IOService | `device.ioreg` | 返回 287 条，count 与数组长度一致；命中 `AppleARMIODevice / sep`，没有 NFC／Stockholm／SecureElement／AppleSSE 类名或节点名匹配 |
| IODeviceTree | `device.ioreg` | 返回 115 条，count 与数组长度一致；有 sep、iop-sep-nub，无 NFC／Stockholm／支付 SE 名称匹配 |
| SEP 启动日志 | `vm log --lines 2000` | `isSEPAvailable = YES`、`AppleSEPKeyStore _sep_enabled = 1`、IPC header 协商成功；这是 SEP 证据，不是支付 SE 证据 |
| 实时日志 | `logs.syslog`，nfcd 2 秒、passd 3 秒 | 两次 count=0；只代表采样窗口没有记录，不能当作初始化或支付无错误 |
| 现有调试通道 | host 既有 `frida-ps -D <精确目标 UDID> -a` | 两次均 `Failed to enumerate applications: escrowFailure`；未 attach、未注入、未修配对或挂载开发镜像 |
| 现成探针 | `apps.search Probe`、只读检查 `/usr/local/bin` | 无已注册 Probe App，目录不存在；不代表穷尽全部可执行文件 |
| 原生公共 API | 三个 PassKit 布尔值 | 未执行，未知；不能用 UI／服务状态替代其返回值 |
| 原生私有 API | SE 元数据枚举 | 未执行，未知；未取得原生错误域或错误码 |

IORegistry RPC 只返回名称、类和层级，不提供 SE 属性、SEID 或证书；本报告不声称已读取这些数据。早期 host `frida-ls-devices` 因非 TTY UI 报错退出，随后用精确设备的 `frida-ps` 取得上述独立通道错误，没有启动调试服务器。

## 后续值得做什么

本轮范围内的现有只读路径已完成。要直接取得那三个 PassKit 布尔值，需要一个实际可执行上下文：可用的现有调试连接，或独立、签名的临时诊断 App；当前两者均未可用／未部署。本轮不为此改系统或配对。

下一阶段即使允许临时诊断 App，也应先只读调用公开 API，独立报告运行上下文；NearField 私有查询必须先核对当前系统 ABI 和调用权限，并设超时。不能先 hook API 返回 true，也不能把服务可连接等同于真实 SE 可用。

有关 SE 模拟、透传、Demo 和 Apple 官方流程，见 [前期可行性研究](apple_pay_secure_element_feasibility_20261023.md)。当前结果支持优先查虚拟支付设备接口，而不是改 Wallet UI、账号或尝试绑卡。

## 证据与恢复

本地证据：`.build/validation/wallet-se-readonly-20261023/`（目录 0700，文件 0600），包含设备信息、IORegistry、服务与进程清单、Wallet UI／截图、日志及调试通道错误。该目录已被 Git 忽略；截图含空钱包，无银行卡信息。

检查结束后通过 Launchpad 正常关闭本轮启动的实例，最终状态以 `stop.json`、`final-machines.json` 为准；没有留下新服务器或采集器。
