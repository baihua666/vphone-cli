# Stockholm 实体驱动移植到 vphone600：SPMI／AOP 与最小后端

2026-10-23。只读分析本地 23G90 实体机固件、此前取得的目标启动内核副本和原始设备树；没有连接实体 iPhone、启动或挂载 VM、修改系统、加载驱动、绕过 NFProductIsVM 或绑卡。

后续已恢复实际导入归属、控制分发表及 socket／通知契约，见 [最小前端接口清单](stockholm_hal_frontend_contract_20261023.md)。其中 `stockholm-spmi-data-socket` 已确认为布尔属性，不是 socket 名称字符串。

## 结论

**目前没有“复制实体 Stockholm 驱动即可使用”的可验证路径；也没有证据证明所有二进制接口必然不兼容。** 声明依赖在 target 都存在，部分基础类布局相似；真正未闭环的是 KC 重链接／认证 fixup、实际 C++ 调用契约，以及具体 SPMI 控制器与 NFC／SE 后端。

对“不需要 RF”的研究目标，较小的候选方案是独立实现 Apple HAL 所需的控制／数据前端，接宿主协议后端。这样可能避免模拟整个 T8140 SPMI 硬件，但它属于新前端实现，不是现成 donor 驱动移植；目前只完成边界分析，没有可运行 Demo。普通 APDU 后端不能独自满足这些接口，更不能证明支付 SE 或 Wallet 绑卡可用。

## 版本与内核兼容性

本轮从已有 `iPhone17_3_26.6.2_23G90_Restore-be187396844b.ipsw` 定向提取正常实体版 `kernelcache.release.iphone17`，没有把 research.iphone17 当作实体运行内核。

| 项目 | 实体固件 donor | 5-20261023 实际 target |
| --- | --- | --- |
| 用户态 | iOS 26.6.2 / 23G90 | iOS 26.6.2 / 23G90 |
| 内核来源 | 同一 IPSW 的 release.iphone17 | cloudOS 26.4 / 23E5207q research.vphone600 |
| Darwin／XNU | 25.6.0 / 12377.162.14~4 | 25.4.0 / 12377.100.591.502.1~2 |
| 平台 | T8140 | VRESEARCH1 |
| Mach-O | MH_FILESET、arm64e | MH_FILESET、arm64e |

Stockholm、AppleSPMI、AppleSSE 的全部 OSBundleLibraries 在目标存在且声明版本范围满足。IOService、IOUserClient、AppleARMIODevice、AppleARMSPMIController／Device 等已发现 metaclass Size 相同；两端 AppleARMPlatform source version 同为 1103.100.17。**不能据内核版本差异直接宣布 ABI 必然不兼容，也不能据这些相似性宣布可用。**

donor Stockholm source version 为 366.9.1，与当前用户态 Stockholm_Base-366.9.1 对应；但其 entry 已剥离符号、预链接进 KC，auth GOT 引用 donor collection 的地址／认证上下文。提取工具重组文件不等于恢复可重链接的原始 kext。公开 XNU 另有限制 ARM／MH_FILESET 非预链接动态加载的逻辑，尚未逐指令核验目标私有内核相应分支。身份、依赖表、PAC 样例和公开源码引用见 [内核兼容性报告](stockholm_kernel_compatibility_20261023.md)。

当前仓库可见的 kernel patcher 是读取／原地修改既有 collection 的流程；本次定向检索没有发现可复用的新增 kext 链接器。没有尝试组装或加载新 KC，也没有用整体实体内核替换研究内核。

## 实体驱动的真实匹配链

`ipsw kernel kexts --json` 给出的实体人格与原始 D47 树可以逐层对应：

| 层 | 实体实现／匹配要求 | 目标当前证据 |
| --- | --- | --- |
| SPMI 控制器 | bundle AppleSPMI；class AppleSPMIController；provider AppleARMIODevice；IONameMatch `aapl,spmi` | 通用 AppleARMSPMIController 基类存在，具体 AppleSPMIController／bundle 未在启动集合发现 |
| SPMI NFC 数据层 | bundle AppleStockholmControl 内的 class AppleStockholmSPMI；provider AppleARMSPMIDevice；`nfc,primary,spmi` | 具体类／人格未发现，原始树没有该子设备链 |
| NFC 控制层 | 同一 bundle 的 AppleStockholmControl；provider IOService；`nfc,primary,gpio`；UserClient AppleStockholmControlUserClient | 具体类／人格／对应 provider 未发现 |
| 用户态 | 当前 libNFC_HAL 查找上述服务；控制走 IOServiceOpen，SPMI 数据走 kernel-control socket | 两库版本已核对；本轮未执行原生初始化 |

**AppleStockholmSPMI 是 AppleStockholmControl bundle 中的类和人格，不是应另找的独立 kext。** 同一 bundle 还有 secondary／Hammerfest 人格；最小单控制器研究无需先复制 secondary 路径。

实体树位置：`/arm-io/aop-spmi0/stockholm-spmi/stockholm`。`aop-spmi0` compatible 为 `aapl,spmi`，描述三个各 16 KiB 的 MMIO 区域、控制器中断及错误／fatal／other 分类、queue-depth、irq-behavior-map。其 NFC 子节点 interrupt-parent 指回控制器，并列出七个 SPMI 中断。

`stockholm-spmi` 明列 `support_host_wake_spmi`、`support_data_over_spmi`、spmiFollowerReset；GPIO 子节点列出 `support_venable`、`support_virtual_gpio` 和 function-enable。现有 JSON 对部分原始属性以字符串／base64 展示；本轮没有把 queue-depth、reg 或 function-enable 的未完整解码值臆造成寄存器／回调 ABI。

驱动字符串也出现 required-functions／required-gpios 缺失或类型错误、function-enable、SPMI 接收和虚拟 GPIO 错误、`com.apple.spmi.nfc`。AppleSPMI 则包含内存映射失败、队列复位寄存器、read/write command、完成中断、超时及总线错误路径。这与 MMIO／IRQ 元数据相互支持，足以排除“只补名称即可”；**尚未还原完整 start／运行状态机，字符串不是全部路径必经的证明。**

目标原始 vphone600 树中定向查找 `aapl,spmi` 和 `smc-pmu` 的结果为空；此前 live registry 也没有具体 Stockholm 服务。本轮不重新启动 guest，历史 registry 不能冒充新快照。目标内核完整缺项与原始树出处见 [上轮离线核对](nfc_current_stack_offline_audit_20261023.md)。

## AOP／SPU：已确认与尚未确认

| 判断 | 证据及边界 |
| --- | --- |
| 实体路径位于名为 aop-spmi0 的节点下 | 设备树直接证据；说明该硬件资源所处路径，不自动说明传输都经 AOP mailbox |
| Stockholm／AppleSPMI 没有声明链接 AppleAOP2、RTBuddy 或 AppleSPU | OSBundleLibraries 直接证据；AppleSPMI 人格匹配 AppleARMIODevice，而非 RTBuddyEndpointService／AppleSPUAppInterface |
| 存在具体 SPMI MMIO／中断依赖 | 控制器人格、设备树和驱动错误路径支持；仅保留 target 通用 AOPSMC／SPU 类不能补齐 |
| 是否必须运行整套实体 AOP 固件 | **未证明**。还需恢复实际平台函数、时钟／电源所有权、wake／GPIO provider 与可能的协处理器调用；不能从节点名称或依赖列表缺项推断有／无间接依赖 |

因此不能将方案概括为“把 AOP2、SPU 一起搬过去就行”。若保留实体 AppleSPMIController，必须满足其实际 MMIO／IRQ／电源行为；若实现较高层兼容前端，可能绕开物理总线模型，但仍需用接口核对证明，而不是伪造设备树属性。

另发现同版实体内核也有 **AppleSSE**：provider AppleSEPDeviceService、IONameMatch `sep-endpoint,sse`、UserClient AppleSSEUserClient。这不是只属于旧 Mac T1 的类；但也不能把它列为所有 Stockholm 路径的必需项。移植 AppleSSE 仍需要真实提供相应 SEP endpoint／固件协议，现有虚拟 SEP 的配置或 SEPStorage 文件不证明已经具备该端点。

## 三种后端方案的最小职责

| 方案 | 必须补齐 | 当前判断 |
| --- | --- | --- |
| 保留实体 Stockholm + AppleSPMIController | KC 重链接／fixup、ABI 核对、具体 SPMI provider、MMIO／队列／IRQ、GPIO／wake／power，以及 NFCC／SE 协议后端 | 最接近原硬件，也承担最多平台细节；本仓库未发现可直接复用的任意 SPMI 虚拟设备组装入口 |
| 保留 Stockholm，只替换底层 SPMI provider | KC／ABI 问题仍在；实现它实际调用的 AppleARMSPMIDevice 方法、寄存器／中断与虚拟 GPIO 语义 | 可能减少 SoC 寄存器模拟，需先逐项恢复调用契约；尚无实现证据 |
| 自写 HAL 兼容前端 → 宿主协议后端 | 控制 UserClient ABI、服务属性、kernel-control socket 行为、reset／power／wake、异步数据／取消／错误，再桥接宿主 | 对无 RF 研究更窄的候选边界；能否承接原库仍未验证，guest 驱动准入／部署也未解决 |

第三种的逻辑链可写成 `libNFC_HAL → 控制 UserClient + 数据 kernel-control → guest 适配 → VSOCK → 宿主 NFCC／SE 后端`。这是架构候选，不是现有可用接口：VSOCK 只是桥接载体，不能直接替代 HAL 所开的 Darwin 内核控制 socket。当前既有 vphoned 通道没有 NFC 协议。准确 selector、参数布局、socket options／帧边界、关闭和并发语义仍需恢复。

当前 HAL 另有 `/dev/*` 串行路径，选择单一路径也许可以省去 SPMI 服务；但尚未证明默认接口选择、控制 provider 与固件加载在此环境全部可满足，不能把改路径当成已验证捷径，更不需要同时实现所有接口。

即使不用 NFC 射频，复用当前 PN548 stack 通常仍需控制器 reset／初始化、异步控制消息与 SE 枚举／wired-mode，再进入 APDU。应以当前二进制恢复实际协议／vendor 扩展，不能仅实现通用 NCI 核心就宣称兼容。射频发现／天线收发可以作为无 RF 实验的非目标；内部控制器职责仍在。

QEMU CCID、vsmartcard、jCardSim 可参考宿主 APDU／卡生命周期，NXP 官方 HAL 可参考控制器／SE 状态机；它们没有提供这里缺的 Darwin 前端或完整 Apple 控制器 emulator。固定源码与 Demo 边界见 [开源核对](se_backend_open_source_references_20261023.md)。没有新增“已走通 Stockholm 移植”的开源证据。

## 当前约束下可继续的最小验证

1. **离线导入／ABI 表**：逐项定位 donor Stockholm auth GOT／直接调用所属 bundle，映射 target 中的方法身份；对实际使用的 vtable 槽位、参数、字段核对。成功标准是调用契约可解释，不能只比较类大小。
2. **离线前端契约表**：将当前 HAL 的每个控制 selector、标量／结构大小、数据 socket 调用、异步事件、超时和电源状态对应到 driver。依赖到未知平台函数即记录阻塞，不填猜测常量。
3. **未来独立宿主 PoC**：不接 vphone，先复用 jCardSim 已有 HelloWorld 测试验证普通 APDU；再针对已还原控制器协议测试 reset／初始化、异步响应、SE 枚举、wired-mode、APDU、断连及超时。软件控制器只能明确标作实验模型，不能进入产品冒充真实硬件。
4. **停止边界**：当前 NFProductIsVM 仍为 1。保持不改系统／不绕过门槛时，宿主协议通过也不能验证原生 nfcd 进入后端、驱动加载或 Wallet。支付可信端点／个性化也是独立缺口，不属于普通 APDU 验收。

本轮只完成前两项所需的首轮清单，未完成全接口恢复，未运行第 3 项，也未实施任何 guest PoC。下一步最有价值的是第 1、2 项，而不是直接制作替换内核。

## 证据与复核

donor IM4P 为 22,077,582 字节，SHA-256 `249ae2bc880f526a7020da62c63e4d6d29882da2a6b404a3f749910e8f819edc`；解压 payload 为 72,581,120 字节，SHA-256 `306b2588429739eb3c6b9d9a7633c260840729cdaa29532bf448ba957f258aac`。UUID、目标来源及声明依赖详见配套兼容性报告。

Git 忽略证据目录 `.build/validation/stockholm-portability-20261023/` 保留定向提取的实体内核、320 项 kext／KPI 元数据、3,238 个已发现类、Stockholm／AppleSPMI 提取产物、反汇编与字符串、D47 相关子树和 vphone 定向匹配结果；ABI 证据另在 `.build/validation/stockholm-compat-20261023/`。只读工具 ipsw 3.1.714、otool／dwarfdump、Ruby JSON 查询；没有 Python、远程反编译或固件上传。

公开实现经 MCP 读取：[ipsw 官方 kernel 指南](https://blacktop.github.io/ipsw/docs/guides/kernel/) 说明从 KC 提取及解析 imports 的分析流程；[Apple XNU fixup 源码](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/dyld_kernel_fixups.h#L59) 展示 collection base／target 与认证位置的关系。这些公开资料用于解释工具与链接机制，不冒充当前私有驱动源代码。

收尾核对两个库仍列出原五台实例，未发现 vphone-vm／VM launcher 进程；没有本轮研究路径的挂载，Disk.img 大小／mtime／ctime 与前轮收尾相同。CLI `vm list` 只列元数据，没有 state 字段，未用缺省字段推断运行状态。断言和权限检查见证据目录 final-validation.json；研究目录 0700、文件 0600。

没有新增挂载／App／服务器。本轮仅更新研究记录，未改产品代码、系统、驱动、固件补丁或版本。
