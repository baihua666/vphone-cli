# nfcd 错误 58：VM gate、设备树与硬件后端

2026-10-23，只读分析。承接 [临时 App 实测](wallet_native_probe_20261023.md)。用户要求先查源码与日志，不改系统、不绑卡。本轮没有启动 VM、安装 App、修改配置或打补丁。

后续补充已完成：[VM predicate 与实际 nfcd 身份实测](nfcd_vm_guard_runtime_probe_20261023.md)。`NFProductIsVM()` 返回 1，客体 nfcd 完整 SHA-256／UUID／大小与本文分析文件相同。下文“运行值／guest 哈希未核对”保留为本轮历史范围，后续结果已补齐这两项；未对 daemon 逐指令跟踪。

进一步只读分析见 [VM gate 之后的依赖链](nfcd_after_vm_gate_dependencies_20261023.md)：当前 nfcd 导入 libPN548_API；旧版具体实现还需要 Stockholm provider／control、串行／SPMI transport、控制器初始化及 eSE wired mode。开源 APDU／NFC HAL 参考不等于现成支付 SE 后端。

后续 [实际部署库与启动内核离线核对](nfc_current_stack_offline_audit_20261023.md) 进一步确认当前同版 HAL 的匹配契约，且活动 kernel collection 缺具体 Stockholm 驱动项；通用 SPMI／AOP 类存在，不能与 NFC 控制器混为一谈。

## 结论

**不能将本次 `nfcd / 58: Unresponsive hardware` 直接解释为驱动已访问硬件但通信超时。** 当前 iOS 26.6.2 原始 nfcd 静态分析确认：VM 判断命中时会跳过正常驱动会话打开，设置“不支持”状态；控制器信息接口对该状态统一返回 58。

有两个彼此独立的限制：

1. **软件资格门槛**：`NFProductIsVM()` → 内部状态 3 → 对外状态 4 → 控制器查询返回 58。上一轮 guest 日志恰为 `NFHWManagerCore ... 1 -> 4`，与此链条相符。
2. **研究虚拟平台的设备缺项**：从官方 cloudOS IPSW 提取的原始 vphone600 设备树没有 NFC／Stockholm 控制器或其 SPMI 链路，宿主 vphone 源码也没有配置支付 SE 后端；实体 D47 树则有完整节点。

因此现有证据最支持“当前研究平台本来不提供这一支付设备栈，并被 nfcd 判定为不支持”，没有证据支持“某个本地设备树补丁误删节点，修一下驱动就可绑卡”。即使移除软件判断，也不能由此制造 transport、寄存器、IRQ、驱动用户客户端或可信 SE；本轮未尝试移除判断。

## 错误 58 从哪里来

### 公开反编译线索

EthanArbuckle 的资料是作者发布的 Hex-Rays 反编译产物，不是 Apple 开源源码；版本为 iPhone18,3 / iOS 26.1 (23B85)，固定 commit `90aa0cfe59d9682b4265e1354c8b19ec3c7823ab`。

- [`nfcd_08.mm:1108`](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/libexec/nfcd/nfcd_08.mm#L1108)：`_bootHardwareForSession:` 先调用 `NFProductIsVM()`；VM 分支直接设置内部状态 3，非 VM 才进入 driver session。
- [`nfcd.mm:857`](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/libexec/nfcd/nfcd.mm#L857)：内部状态 1..4 映射为对外 2..5，其余为 1。
- [`nfcd_07.mm:9180`](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/libexec/nfcd/nfcd_07.mm#L9180)：对外状态 4 明确走“不支持 NFC/SE”路径。
- [`nfcd_08.mm:8868`](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/libexec/nfcd/nfcd_08.mm#L8868)：controllerInfo callback 只接受状态 2 或 5，其余统一生成 domain nfcd、code 58，并不在该分支发硬件命令。
- [`libnfshared.mm:434`](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/lib/libnfshared/libnfshared.mm#L434)：`NFProductIsVM` 位于 libnfshared，缓存一个经 MGGetBoolAnswer 得到的值；反编译没有恢复参数，不能据此编造具体 MG key。

实际驱动开栈失败也可能返回同号错误。[`nfcd_18.mm`](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/libexec/nfcd/nfcd_18.mm#L1887) 的 `_openDriver:` 中，NFDriverOpen 失败走 Stack Error；NFDriverLoadStack 部分失败值（16/17）会转成 58。**相同错误号可以来自状态门槛或真实开栈失败，必须结合分支与状态区分。**

### 当前 26.6.2 原始 nfcd 的独立核对

从本机既有 `iPhone17_3_26.6.2_23G90_Restore-be187396844b.ipsw` 提取 `/usr/libexec/nfcd`，只在宿主临时目录解包、只读分析；工具已退出、临时挂载已清理。未使用反编译 LLM 服务。

二进制 SHA-256：`ccefd478ec4a3777128118a3c46ffb8a212df98fbf25303c72f272ebb9e5ea62`。这是同版 IPSW 原始文件的摘要，**本轮没有从运行 guest 读取 nfcd 全文件哈希**，不冒充运行二进制逐字节身份核验。

使用 `ipsw macho info --symbols/--objc` 及 Xcode `otool -tvV`：

| 静态位置（该二进制专用） | 所见控制流 |
| --- | --- |
| `0x1000b3adc` | 调用导入的 `_NFProductIsVM`，符号来自 libnfshared |
| `0x1000b3ae0` | 返回 0 才转到正常路径；非 0 将参数设为 3，调用状态 setter 后退出 |
| `0x1000b3af4` | 非 VM 正常 driver session 路径入口，VM 分支绕过 |
| `0x1000b3cbc` / `0x1000b3dd8` | 状态 setter 将传入值写到对象 `+0x120`；有 Hardware state 日志 |
| `0x1000047c8` / `0x1000047ec..4810` | getter 读取同一字段，内部 3 映射为对外 4 |
| `0x1000b0ba0` / `0x1000b0c0c` | 对外状态 4 对应“不支持 NFC/SE”的日志分支 |
| `0x10000b240..b258` / `0x10000b2b0..b348` | 控制器 callback 的 2/5 状态门槛；其它状态构造 nfcd + 58 + Unresponsive hardware |

上述地址仅为可追溯的离线研究定位，不是补丁偏移或运行时常量。分析产物保留符号、完整反汇编和四段关键摘录，可独立核对每一步，没有写入任何目标二进制。

## 设备树是否被本地改坏

直接从两个官方来源的既有 IPSW ZIP 读取并计算 SHA-256，与实例 `FirmwareOriginals` 的文件匹配：

| 原始设备树 | 来源 | 两端相同摘要 |
| --- | --- | --- |
| `DeviceTree.vphone600ap.im4p` | cloudOS 26.4 / 23E5207q | `987a9306d16a9047dc1b46fd1b3cec2aab7738aff6c5c86938ee3ada1a461e3c` |
| `DeviceTree.d47ap.im4p` | iOS 26.6.2 / 23G90 | `b1f6594ce30f669f585ce10eab1c9b736519db189daf52147b454a6fb49f2f54` |

用 `ipsw dtree --json` 对两个输入解码，按属性路径及值检索 NFC／Stockholm／Secure Element／PN 型号。VM 原树匹配 0，D47 树有 Stockholm 节点与 compatible。VM 的 arm-io 直接子节点只有 aes、uart、gic、时钟、pcie、显示／输入、bluetooth 和 sep 等，未包含 Stockholm 总线链路。

D47 具体 provider 描述位于 `/arm-io/aop-spmi0/stockholm-spmi/stockholm`；父节点 compatible 为 `nfc,primary,spmi`，子节点为 `nfc,primary,gpio`，并有 interrupts、reg、GPIO／host-wake 等硬件依赖。它不是一个独立的 UI 开关。

项目 [DeviceTreeGuestDevicePatches.swift](../../VPhoneExecutable/VPhoneCommand/FirmwarePatcher/DeviceTree/DeviceTreeGuestDevicePatches.swift) 的 iPhone product 白名单（约 335–408 行）明确不复制承诺 NFC 硬件的属性；[VM 配置](../../VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachine.swift) 仅配置虚拟 SEP，没有支付 SE／Stockholm 组装。本实例 PatchReceipt 中也没有 NFC 补丁。

这排除了“FirmwareOriginals 本地副本丢了原本存在的控制器节点”这一具体假设，不能证明 Apple 私有 hypervisor 内部绝无任何未公开设备实现。实际运行树仍以此前 115 条 IODeviceTree、287 条 IOService 只读记录为依据；未把原始树冒充运行树的逐字节副本。

## 驱动匹配路径

26.1 [libNFC_HAL 实现](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/lib/libNFC_HAL/libNFC_HAL_01.mm#L509) 查找 `AppleStockholmControl` + `IONameMatched=nfc,primary,gpio`，并有设备树递归回退；[接口类型判断](https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/90aa0cfe59d9682b4265e1354c8b19ec3c7823ab/usr/lib/libNFC_HAL/libNFC_HAL.mm#L9790) 还查 `AppleStockholmSPMI` + `nfc,primary,spmi`。

此前 live registry 没有这些节点／类。这里引用的是旧版 HAL，当前版 HAL 尚未独立提取核对，不能把旧版全部 provider 规则当作当前唯一匹配规则。但原始 VM 树没有任何对应链路、当前 nfcd 显式 VM gate、live unsupported state 三者是相互独立的证据。

## 最小可验证方案

**已完成的零客体改动验证**：同版 nfcd 原始二进制确认 VM gate／状态映射／58 门槛；对照官方原始设备树并核对摘要，确认缺项早于本地补丁。树比较 jq 断言通过（VM NFC 字段为 0、实体树非 0、VM SEP 存在）。

若下一步要把“静态分支存在”提升为“本实例确实走了该分支”，最小补充为：

1. 在授权的临时只读诊断 App 中仅调用当前 `libnfshared` 的 `NFProductIsVM()` 并记录 BOOL，不改其返回值；同时核验 guest nfcd UUID／哈希与本次原始文件。
2. 在正常冷启动时，从 host 在 vphoned 连通后立即采集 nfcd 初始化日志，关联 unsupported 状态与 driver-open／stack-failure 日志。可能错过更早日志，不能以“没抓到”证明未执行；静态控制流和 predicate 查询共同判断。
3. 只读精确查上述 controller providers、compatible、parent chain。若 VM 判定为真且没有 provider，可停止，无需更换驱动、复制 D47 节点或尝试支付。

本轮没有重新安装探针执行第 1 项，也没有为了抓早期日志启动 guest。实际 `NFProductIsVM()` 返回值和当前 HAL 精确 provider 条件仍待该最小补充验证，不能用静态分析冒充已测到的运行值。

当前**没有证据支持一个只改驱动／设备树即可恢复支付 SE 的最小修复**。最小验证方案可行，不等于最小修复已存在；在出现虚拟控制器／SE 后端的实际证据之前，不建议投入通用模拟平台或篡改 VM 判定。

证据目录 `.build/validation/nfcd58-analysis-20261023/`：原始树 JSON、来源摘要、树比较、原始 nfcd、ObjC／符号与反汇编、关键摘录和提取日志。目录 0700、报告与文本 0600；无 guest 系统改动，无 VM 运行、无绑卡。
