# 实体 23G90 Stockholm 与 vphone600 的内核兼容性

2026-10-23。只读分析离线副本，不启动或挂载实例、不改系统、不绕过 VM 门槛、不加载驱动、不绑卡。本文只负责 ABI／kernel collection 部分；provider 与硬件路径由配套报告分析。

配套见 [SPMI／AOP 与最小虚拟后端](stockholm_driver_portability_20261023.md)。

## 判断

**不能把实体机 fileset 中的 Stockholm 条目抽出后直接加载到 vphone600。** 声明依赖没有发现缺项，多个基础类布局也有相似证据；但实际内核版本不同，驱动已经绑定实体机 collection 的地址和认证 fixup，真实 C++ ABI 与硬件契约尚未证明。当前证据支持“值得继续离线还原接口”，不支持“移植已可行”，也不支持武断断言 arm64e 天生不能兼容。

## 两端身份

| 项 | 实体 donor | 当前 target |
| --- | --- | --- |
| 来源 | iPhone17,3 iOS 26.6.2 / 23G90 | 5-20261023 活动 Preboot 副本；cloudOS 26.4 / 23E5207q |
| 内核 | kernelcache.release.iphone17 | kernelcache.research.vphone600（已有部署补丁） |
| Darwin | 25.6.0 | 25.4.0 |
| XNU | 12377.162.14~4 | 12377.100.591.502.1~2 |
| 构建平台 | RELEASE_ARM64_T8140 | RELEASE_ARM64_VRESEARCH1 |
| Mach-O | MH_FILESET / ARM64e / KER00 | MH_FILESET / ARM64e / KER00 |
| UUID | F1D7B76F-7A81-F693-00D2-B4D68F27BA08 | BCD06230-CCBE-8E48-50FF-D9C166D83CD5 |
| payload SHA-256 | 306b2588429739eb3c6b9d9a7633c260840729cdaa29532bf448ba957f258aac | efd82d78596f1d96db6a23a5cea05b4b85d5fbc8fec02d556265db606003b086 |

因此“同版 23G90 用户态”不能写成“两端同版内核”。实体 IM4P SHA-256 为 `249ae2bc880f526a7020da62c63e4d6d29882da2a6b404a3f749910e8f819edc`；vphone 原版／部署差异见 [现有内核清单](nfc_kernel_inventory_20261023.md)。

## 声明依赖核对：存在且版本范围满足

实体 `com.apple.driver.AppleStockholmControl` 版本 1.0.0，LC_SOURCE_VERSION 366.9.1，UUID `65D38FB3-A051-340C-BAFB-68ED04AF4DDF`。其声明不直接列 AppleSPMI／AOP；不能仅按业务名称推断链接依赖，SPMI 运行时 provider 另议。

| Stockholm 声明依赖 | 请求版本 | vphone 已有版本／兼容下界 |
| --- | --- | --- |
| AppleARMPlatform | 1.0.0 | 1.0.2 / 1.0.0 |
| AppleOnboardSerial | 1.0 | 1.0 / 1.0 |
| kpi.bsd | 8.0 | 25.4.0 / 8.0.0b1 |
| kpi.iokit | 8.0 | 25.4.0 / 7.0 |
| kpi.libkern | 8.0 | 25.4.0 / 8.0.0d0 |
| kpi.mach | 8.0 | 25.4.0 / 8.0.0d0 |
| kpi.private | 22.0 | 25.4.0 / 8.0.0b1 |
| kpi.unsupported | 8.0 | 25.4.0 / 8.0.0b1 |

同样核对了实体 AppleSPMI（1.0.1，source 113.100.6，UUID `CE1C32C8-75DC-3E84-ADE0-AA686CBD33D9`）和 AppleSSE（1.0，source 320，UUID `4556D862-273E-3EF5-A109-C33F69E2F364`）的全部 OSBundleLibraries。所有声明项均在 target 中，数值兼容范围满足；SSE 另外要求 AppleSEPManager 1.0.0、IOSlaveProcessor 1.0.0，目标分别为 1.0.1／兼容 1.0.0 与 1／兼容 1.0.0。

Apple [OSBundleLibraries](https://developer.apple.com/documentation/bundleresources/information-property-list/osbundlelibraries) 与 [OSBundleCompatibleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/osbundlecompatibleversion) 说明这些字段表达驱动依赖和兼容范围。**通过声明检查只排除这一种失败，不能证明入口、虚方法、结构布局和执行语义兼容。**

## C++ ABI：有相似证据，尚未闭环

双方 AppleARMPlatform 的 bundle version 都是 1.0.2，source version 都是 `1103.100.17.0.0`，UUID 分别 `14BF8028-6C7B-3625-975E-39CE638C9609`（donor）、`DFA5DC62-7198-3297-9195-9993731D0486`（target）；SDK 分别 iphoneos26.6.internal / 23G73 与 iphoneos26.4.internal / 23E5207h。相同源版本比只看 1.0.2 更有参考价值，仍不表示字节或所有构建条件一致。

`ipsw kernel cpp --json` 发现的类实例 Size 对照：

| 类 | donor / target 字节数 |
| --- | ---: |
| IOService | 136 / 136 |
| IOUserClient | 216 / 216 |
| AppleARMIODevice | 264 / 264 |
| AppleARMSPMIController | 264 / 264 |
| AppleARMSPMIDevice | 168 / 168 |
| AppleOnboardSerialBusInterface | 152 / 152 |
| AppleSEPDeviceService | 152 / 152 |
| IOSlaveProcessor、RTBuddyService | 均 168 / 168 |

这只能证明已发现 metaclass 的实例大小相同；没有逐槽比对 vtable、逐函数恢复参数契约、全部字段语义与平台调用。尤其 stripped entry 不能根据 undefined symbol 数量为零推断“没有外部依赖”。

## 为什么抽取产物不是原始可加载 kext

实体 Stockholm entry 本身标记 `MH_KEXT_BUNDLE`、`NoUndefs, DyldLink, TwoLevel, DylibInCache`；LC_SYMTAB `nsyms=0`，LC_DYSYMTAB undefined=0、无传统 external/local reloc，保留 183 个 indirect entries。这是已合并 collection 的形态，不是带完整未解析符号／重定位的原始构建产物。

其各段分散于 donor KC：`__TEXT` 文件偏移 `0x667d40`、`__TEXT_EXEC` 为 `0x2332440`、`__DATA_CONST` 为 `0xfe83b8`、`__DATA` 为 `0x43da598`；简单连续切片本身就不能代表完整映像。专用提取器可以重组文件布局，但不自动恢复跨 KC 链接契约。

本轮直接读取 Stockholm `__DATA_CONST.__auth_got` 首项：原始文件偏移 `0xfe83b8`，链字 `0x8011000003d7637c`。按公开 kernel-cache chained-pointer 位域解码，cacheLevel=0、target offset=`0x3d7637c`、isAuth=1、key=IA、addrDiv=1、diversity=0；donor 基址 `0xfffffff007004000` 加 offset 得到 donor 目标 `0xfffffff00ad7a37c`。这是离线未滑动地址，只用于辨识链接上下文，不是补丁地址。

Apple XNU [dyld_kernel_fixups.h L59–132](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/dyld_kernel_fixups.h#L59) 从 collection base 和 target 计算目标；认证项结合 key、diversity 与 pointer location 签名。[arm_init.c L213–258](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/arm/arm_init.c#L213) 在启动期间处理 collection 的 slide、fixup 和签名。故不能保留 donor 原始目标／偏移后期待自动指向 target；也不能把磁盘编码当成可跨环境复制的已签名运行时指针。

公开 XNU [OSKext.cpp L3338](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/libkern/c%2B%2B/OSKext.cpp#L3338) 拒绝在 MH_FILESET 启动状态动态加载新非预链接 executable kext；[L6152](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/libkern/c%2B%2B/OSKext.cpp#L6152) 对 ARM 路径同样要求已在 collection。此处引用是公开实现的约束说明，**尚未逐指令核验当前私有内核包含完全相同的拒绝分支**；不能把它夸大成此次实测加载失败。整个流程未尝试加载或绕过限制。

## 可继续的离线验证与不可越过的结论

1. 逐项将 donor auth GOT、直接调用目标和类 metaclass 归属到 kernel／各依赖 bundle；先恢复符号身份，再映射到 target。仅对齐地址或同名 bundle 不足够。
2. 对 Stockholm 实际调用到的 AppleARMPlatform／OnboardSerial／IOKit 方法逐槽核对 vtable、参数与对象布局。当前无完整私有 SDK、原始可重链接 object 或符号，不能声称完整 ABI 认证。
3. 最小虚拟方案应选择稳定的用户客户端／transport 契约，以独立普通控制器/APDU 后端验证协议；是否必须复用实体驱动，要等 provider、寄存器、中断、AOP 固件路径的具体证据。补人格或移植 driver 不会生成硬件。
4. 不把整体实体 T8140 内核换进 vphone 当作兼容捷径；其平台、启动和硬件环境与 VRESEARCH1 不同，本轮没有该方案的可运行证据。

## 可追溯性

已先按 kernel-analysis-vphone600 skill 查询 `Research/KernelSymbols/kernel_symbols.db` 的 release/research 行；指向旧机器绝对路径，本 checkout 无相应 JSON，未采用旧地址。当前副本路径分别为 `.build/validation/stockholm-portability-20261023/iphone/macho/kernelcache.release.iphone17.im4p.decompressed`、`.build/validation/nfcd-current-kernel-20261023/deployed/deployed-kernelcache.img4.decompressed`。

ABI 比较与链字证据放在 `.build/validation/stockholm-compat-20261023/`：dependency-comparison.json、base-class-sizes.json、stockholm-info.txt、stockholm-auth-got.txt。完整 fixup 文本打印在工具中耗时较大，已终止自己的只读工具进程，改为固定目标字段读取；保留样例而不声称全链审计。工具为 ipsw 3.1.714、Xcode dwarfdump、Swift Data 只读位域检查。官方来源通过 MCP search_service 检索／读取；公开 XNU 固定 commit 为 `f6217f891ac0bb64f3d375211650a4c1ff8ca1ea`，不是这两份私有构建的逐行源代码。
