# NFProductIsVM 与客体 nfcd 身份：最小只读实测

2026-10-23，北京时间。承接 [nfcd 58 静态分析](nfcd58_vm_guard_analysis_20261023.md)。用户授权在 `5-20261023` 安装临时诊断 App，读取 VM 判断及实际 nfcd 的哈希／UUID，完成后清理。不改系统、不绑卡。

## 结果

**本实例的 `NFProductIsVM()` 实测返回 1，满足已分析的 nfcd VM 拦截条件。** 运行进程指向的 `/usr/libexec/nfcd` 完整文件与此前从 iOS 26.6.2 / 23G90 IPSW 提取、分析的原始文件完全同摘要、同 UUID、同大小。

| 读取项 | 结果 |
| --- | --- |
| `NFProductIsVM()` | 原始整数返回值 1；nfcd 检查的低 32 位也为 1 |
| `dladdr` 符号来源 | `/usr/lib/libnfshared.dylib`，`NFProductIsVM` |
| nfcd 路径 | `/usr/libexec/nfcd`；进程查询及 launchd service 均指向该路径 |
| nfcd SHA-256 | `ccefd478ec4a3777128118a3c46ffb8a212df98fbf25303c72f272ebb9e5ea62` |
| Mach-O UUID | `7A5CE169-EF6D-3DA1-B82F-9C7872E2C83B` |
| 文件大小 | 3,022,240 字节，ARM64e |
| 同版 IPSW 原始文件对照 | 三项全部相同；宿主 shasum／dwarfdump 独立对照断言通过 |

结合上一轮同文件的静态控制流：

```text
NFProductIsVM != 0
  → 跳过正常 openDriverSession 分支
  → internal state = 3
  → public state = 4（NFC/SE unsupported）
  → controllerInfo readiness gate 返回 nfcd / 58
```

此前真实客户端日志的 `1 → 4` 与这一路径一致。因此，不应再把此处的 58 当成“已经访问 SE 但硬件无响应”的证据，也不支持仅凭该错误认定设备树或驱动初始化故障。

**证据边界**：函数在临时 App 进程内执行；未附加 nfcd、读取其寄存器／内存或逐指令跟踪其分支。文件哈希不是进程内存完整性证明。结论是“本实例 VM predicate 为真，实际 nfcd 文件存在匹配分支，既有状态相符”，对 VM gate 解释构成强证据；不能宣称拿到了 daemon 的分支 PC 轨迹或排除了所有其他问题。

这也没有补齐 [原始设备树／IORegistry](nfcd58_vm_guard_analysis_20261023.md) 中缺少的 NFC/Stockholm 控制器与支付 SE 后端。改 predicate 不等于获得 SE、可信 applet 或真实绑卡能力，本轮未改变任何返回值。

## 方法与环境

- 实例：`5-20261023`，资料库 `/Users/tubao/.vphone/init-test-20261022`，UDID `0000FE01-83B6A5C3FA526E16`；iOS 26.6.2 / 23G90、cloudOS 26.4 / 23E5207q。
- 复用原绑定宿主和 guest 环境 `2.8.0-local.199abaf3`。历史 boot-chain 名称 `2.10.0-local.36ee25a1` 保留原样，不作为当前官方基线声明；未重新绑定或更新组件。
- 开始时五台 VM 均停止，仅正常启动指定实例。nfcd PID 60；服务 `user/501/com.apple.nfcd` 正常运行，program 为 `/usr/libexec/nfcd`。
- 临时 App `com.tb.vphone.vmguardprobe.temp20261023`，PID 478、UID/EUID 501，安装前确认不存在，启动及前台身份均验证。
- 沿用既有探针的独立 UIKit App／容器内 JSON 报告方式，精简为两项读取。`dlopen`／`dlsym` 获取当前库函数；读取文件后以 CommonCrypto SHA-256 和边界检查的 `LC_UUID` 解析取得身份。
- 源码 SHA-256：`f8453e09e5551770211f6419d814ff3e6096cc1accd26f4e6c39d4f2a8877ccd`；运行报告中的源码摘要与本地一致。iPhoneOS clang 编译无诊断，原有签名与容器安装路径通过；不代表零售真机安装／沙箱等价性。
- 只带安装器既有的容器／研究 trust 属性，没有声明 NearField hardware-manager、SE、支付权限；不加载 NearField manager、不发 XPC 硬件查询、不创建支付／绑卡／SE 会话。未读取卡、SE 标识、证书或密钥。
- App 在进入 UIApplicationMain 前执行解析断言：拒绝短文件、解析已知 UUID fixture、拒绝越界 load command。实际报告 `finished=true`；宿主另以完整 SHA、UUID、大小、符号来源、返回值和源码摘要作 jq 断言，全部通过。

按项目要求通过 MCP 搜索并抓取 [Apple 官方 NFC & SE Platform 说明](https://developer.apple.com/support/nfc-se-platform/)，其说明该平台涉及 SE、SEP 与 Apple 服务器。这是平台背景，不是本文私有函数或错误 58 的官方 API 依据；VM 分支依据本机同版二进制与实测，未假称为 Apple 开源源码。

## 清理与保留证据

完成后通过现有 Launchpad RPC 卸载临时 App。卸载返回移除 bundle/data 两个容器，随后分别检查：

- App 搜索为空，`TBVMGuardProbe` 进程数为 0。
- 实际 bundle 容器和 data 容器路径均返回 Cocoa 260 / POSIX 2（不存在）。
- 上传的 `/private/var/tmp/tb-vmguard-probe-20261023.ipa` 返回 Cocoa 4 / POSIX 2（不存在）。
- `5-20261023` 正常停止；最终 `vm list` 五台均 `stopped`。

宿主证据位于 Git 忽略的 `.build/validation/nfcd-vmguard-runtime-20261023/`，目录 0700、文本／JSON 0600。保留源码、运行报告、原始文件身份对照、编译记录与安装／卸载／停机结果；删除宿主临时 Payload、IPA 和上传编码中间文件。不修改产品代码、系统文件、设备树、固件、签名策略或账号配置。
