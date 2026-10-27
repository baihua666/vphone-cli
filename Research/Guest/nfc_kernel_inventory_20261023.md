# 5-20261023 的实际启动内核与 NFC 驱动清单

2026-10-23。仅离线读副本；不启动实例、不改系统、不绕过 NFProductIsVM、不绑卡。本文负责内核部分；同版用户态库及总判断见 [离线核对主报告](nfc_current_stack_offline_audit_20261023.md)。

## 结论

**实际活动 Preboot 内核中，没有发现 Apple Stockholm／AppleSSE 的驱动 bundle、IOKit personality 或已发现 C++ 类。** 这比“驱动已经存在，只是没有匹配 provider”更早缺一层。

不过，不能笼统说 SPMI 或 AOP 全部没有编入：`AppleARMPlatform` 含通用 `AppleARMSPMIController`／Device 基类及 UserClient；`AppleSMC`／`AppleSPU` 含 AOP 相关类。这些通用类不是 NFC 控制器、Stockholm transport 或支付 SE。

此结论限定于已核验的启动 kernel collection；没有把“字符串不存在”当作唯一依据，也没有据此证明磁盘上绝无可另外加载的软件包。现有 IORegistry／设备树和宿主 VM 组装未提供 NFC／eSE 后端，是另一组独立证据。

## 实例、来源与版本闭环

- 实例：`/Users/tubao/.vphone/init-test-20261022/5-20261023`；用户态 iOS 26.6.2 / 23G90。
- 当前机器绑定 Core Bundle `2.8.0-local.199abaf3`。历史 bootChain 身份 `2.10.0-local.36ee25a1` 保留真实记录，不视为当前官方基线。
- 内核来源是 cloudOS 26.4 / 23E5207q 的 `kernelcache.research.vphone600`，不是 23G90 实体机内核。
- 原始 ZIP：`/Users/tubao/.vphone/ipsws/c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ad-b80d96a0b616.ipsw`；本轮直接读取其 BuildManifest，核对 ProductVersion=26.4、ProductBuildVersion=23E5207q。
- 实例 `FirmwareOriginals/iPhone17,3_26.6.2_23G90_Restore/kernelcache.research.vphone600` 与上述 ZIP 中同名 IM4P 完整 SHA-256 相同。目录名描述混合固件目标，不表示内核来自 iOS 23G90。
- PatchReceipt 记录 kernelcache 由 `restore` 在 `2026-10-22T10:16:48Z` 写入；receipt 无文件摘要，单靠它不能证明现存字节。
- 主任务将停机 Disk.img 只读附加，System 与 Preboot 均 Writable=false；Preboot `/active` 内容为 `98810CA1EA152D8E4D3D8C6DD4850EFE23B810937E33A54F0826B3CED3228883D408B4070D15C83C9460A3E882BD998F`。
- 本文分析的是该 active 目录下 `System/Library/Caches/com.apple.kernelcaches/kernelcache` 的副本。源与副本摘要相同，来源记录在 `.build/validation/nfc-current-libraries-20261023/deployed-kernel-source-sha256.txt`；不读取 SEPStorage 等私密存储。

### 身份摘要

| 文件 | 字节数 | SHA-256 | Mach-O UUID |
| --- | ---: | --- | --- |
| 官方 research IM4P／实例 FirmwareOriginals | 14,447,937 | `c853504319f27bfb3283253d8a5f36c3d0166ea7f4b178fca26fe6352b4de951` | 解压后见下行 |
| 官方 research 解压 payload | 43,368,448 | `86895a2eebeb7fcfb68bcd60f2d7e685687faea07ee31166fb58c872b38e0d92` | `BCD06230-CCBE-8E48-50FF-D9C166D83CD5` |
| 实际 active Preboot IMG4 | 43,374,643 | `32b1c4512f73cf748b7191e07132c35e0dc8c3f33ec79c97ecd16bf778ad3f74` | 解压后见下行 |
| 实际 active Preboot 解压 payload | 43,368,448 | `efd82d78596f1d96db6a23a5cea05b4b85d5fbc8fec02d556265db606003b086` | `BCD06230-CCBE-8E48-50FF-D9C166D83CD5` |
| 官方 release IM4P 对照 | 14,124,537 | `29b0d67ca805679a705e1558e126cedc64d17ab50f7b48cf9a77847dbe59b338` | 解压后见下行 |
| 官方 release 解压 payload | 42,254,336 | `681801fe328b00ff8ec2e94a3d84bf9f9a7a1b954640d0c40f8dd02434270935` | `281F97D7-1F00-0870-DDA8-1578B18B73D0` |

三者版本字符串均为：`Darwin Kernel Version 25.4.0: Wed Feb 4 23:04:24 PST 2026; root:xnu-12377.100.591.502.1~2/RELEASE_ARM64_VRESEARCH1`。文件名的 research/release 与版本字符串末段不可混为一谈。

部署 payload 与原版完整哈希不同，符合已有内核补丁的事实；相同 UUID 不代表逐字相同。本轮只证明驱动清单和类发现结果未发生变化，没有逐条重新审计全部历史补丁。

## 完整清单，而非只搜关键词

工具 `ipsw 3.1.714 (Homebrew)`：`kernel dec`、`kernel kexts --json`、`macho info --loads`、`kernel cpp --json`；另用 Xcode `dwarfdump --uuid` 独立读取 UUID。

| 对象 | kext／KPI 元数据项 | LC_FILESET_ENTRY | C++ 类发现 |
| --- | ---: | ---: | ---: |
| 实际部署 research | 162 | 146，含 com.apple.kernel | 1,921 |
| 官方 research | 162 | 146 | 1,921 |
| 官方 release 对照 | 160 | 144 | 本轮未全量扫描 |

元数据项数多于可执行 fileset 项数，因为清单也包含无独立可执行体的人格包和 KPI 声明。部署与原版 research 的完整 kext JSON **逐字一致**，完整 C++ JSON 也逐字一致。两份 kext JSON SHA-256 均为 `c75e0c465b1c5f86e119948a95eade704fb8a5f436a5dc1da7e7121a3a7bbd33`。

release 与 research 的 bundle ID 差异只有 research 多 `com.apple.driver.AppleFirmwareKit`、`com.apple.iokit.EndpointSecurity`；并没有 research 独有的 NFC／Stockholm 驱动。

部署内核共有 791 个 personality；对每个 personality 的名称、IOClass、IOProviderClass、IONameMatch、IOUserClientClass 进行定向检查：

| HAL 所需／相关对象 | bundle／人格 | C++ 类发现 | 判断 |
| --- | --- | --- | --- |
| AppleStockholmControl | 无对应项 | 无 | 不支持“已编入，仅 provider 未匹配” |
| AppleStockholmControlUserClient | 无对应项 | 无 | 缺少 HAL 所期待的用户客户端实现证据 |
| AppleStockholmSPMI | 无对应项 | 无 | 通用 SPMI 基类不能替代它 |
| AppleSSE／AppleSSEUserClient | 无对应项 | 无 | 不存在可由这份集合确认的 AppleSSE 后端 |
| KernelRelayHost | 无对应项 | 无 | 没有此内核端实现的证据；不能将用户态 relay 字面量当作可用服务 |
| AppleARMSPMIController／Device 及两个 UserClient | 无直接对应 personality | 4 个类，属于 AppleARMPlatform | 通用基类确实编入，不能扩大为 Stockholm 已存在 |
| AOPSMC／SPU 通用功能 | 有 | 有 | AOP 相关软件存在，不证明 AOP NFC 通道存在 |
| 虚拟 SEP | AppleSEPManager／KeyStore／CredentialManager 有人格 | 有 | SEP 与独立支付 eSE 不等价 |

可复核的实际内核地址示例：`AppleARMSPMIController` 的 C++ 初始化函数 `0xfffffe0007b43e14`、metaclass `0xfffffe000983cdb0`、vtable `0xfffffe00077f3420`，所属 `com.apple.driver.AppleARMPlatform`。这些是离线未滑动地址，不用于补丁。

AOP 现有人格示例：`AppleSMCAOP` 以 `AppleSMCInterface` 为 provider，匹配 `smc-aop`；`AppleSPUFirmwareService-AOP` 以 `RTBuddyService` 为 provider，匹配 property `role=AOP`；`AppleSPU` 依赖 `RTBuddyEndpointService` 的 AOPEndpoint；均未声明 Stockholm NFC 类或 `nfc,primary,gpio/spmi`。

### 为什么字符串会误导

全内核 `strings` 仍能找到 `AppleStockholmControl`、`AppleStockholmControlUserClient`、`AppleSSE`、`AppleSSEUserClient`。抽出 `com.apple.security.sandbox` 后，这些目标字符串均在 sandbox 策略数据中重现：权限规则可以引用不存在于当前机型的驱动名，不能据此证明驱动代码已编入。

共 22 个宽松关键词命中中 20 个出自 sandbox；其余包括 NFStorageServer 和 AppleSPMIBacklight，也不是 Stockholm 类实现证据。判断依赖完整 fileset、kext 元数据、personality 和 C++ metaclass 的组合；C++ 扫描本身也不是所有可能代码形态的形式证明。

## 区分三个层次

1. **驱动未在集合中提供**：本实例的活动启动集合缺少上表具体 Stockholm／SSE 驱动及其人格，证据强于过去仅凭 IORegistry 未出现服务的推断。
2. **驱动存在但 provider 没匹配**：通用 SPMI／AOP 类存在；不过既有 vphone600 原始设备树和历史 live registry 缺少 Stockholm 链路。不能将此泛化为具体 NFC 驱动只是等待 provider。
3. **虚拟硬件后端**：既有原始 VM 设备树无 Stockholm 控制器、SPMI NFC 子节点，宿主虚拟机配置也没有相应控制器／eSE 配置。即使以后添加驱动或人格，仍须独立提供 transport、寄存器／中断或完整虚拟接口、控制器响应与 eSE 后端。本轮没有证明 Apple 私有 hypervisor 内部绝无未公开实现，只确认本实例可见组装链没有这些证据。

IOKit 的一般匹配语义参考当前 Apple XNU [IOCatalogue::findDrivers](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOCatalogue.cpp#L215) 和 [IOService::probeCandidates](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOService.cpp#L3853)：先有服务与匹配候选，再 probe/start。此公开源码用于解释结构，不冒充该私有内核构建的逐行源码。

## 可追溯性与下一步

- 已按 kernel-analysis-vphone600 skill 先查询 `Research/KernelSymbols/kernel_symbols.db` 的 release/research 两行。数据库链接到另一台机器旧绝对路径；本 checkout 无对应 JSON。没有拿旧数据库计数或地址作为当前内核证明，全部结果来自上述同版副本。
- 工具官方说明：[解析 kernelcache 与提取 kext](https://blacktop.github.io/ipsw/docs/guides/kernel/)。MCP Web 工具本轮返回 isError，随后使用 Web fallback 读取官方文档；未将第三方反编译的 26.1 内核当作本轮当前内核。
- 原始证据目录：`.build/validation/nfcd-current-kernel-20261023/`。包括三套完整清单、实际／原版 C++ 发现、791 个人格的精简匹配字段、原版 IM4P 与实际部署解压副本、sandbox 字符串对照。父目录 0700，证据文件 0600。
- 下一步适合继续离线对照同版 HAL 的精确 class／name／控制 socket ABI 与本表缺项；不需要启动 VM、绕过 gate、注入 provider 或加载驱动即可完成接口缺口说明。
