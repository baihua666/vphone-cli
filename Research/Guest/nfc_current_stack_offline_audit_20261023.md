# 5-20261023：同版 NFC 库与实际启动驱动的离线核对

2026-10-23。范围：读取指定停机实例的 System／Preboot 与对应本地 IPSW，核对 `libPN548_API`、`libNFC_HAL`、活动启动 kernel collection；不启动 VM、不改系统、不绕过 `NFProductIsVM`、不绑卡。

后续已核对实体驱动、内核兼容性及 SPMI／AOP 链路，见 [Stockholm 移植分析](stockholm_driver_portability_20261023.md) 与 [KC／ABI 兼容性](stockholm_kernel_compatibility_20261023.md)。

## 结论

**本实例具备同版用户态 NFC 库，但实际启动内核集合缺少具体 Stockholm 驱动及其匹配人格；原始设备树、既有 live registry 和宿主组装也没有提供对应控制器／eSE 后端的证据。** 不能把问题缩减为“具体 NFC 驱动已经在，只是 provider 没匹配”。

| 要区分的情况 | 本轮核对结果 |
| --- | --- |
| 具体 NFC 驱动未在启动集合中提供 | 活动 research.vphone600 的完整 bundle、791 个人格及 1,921 个已发现 C++ 类中，均未发现 AppleStockholmControl／SPMI／ControlUserClient 对应项 |
| 驱动存在但没有匹配 provider | 通用 SPMI／AOP 软件确实存在；这不能替代具体 Stockholm 驱动。当前可见设备链也不具备 HAL 所查找的 NFC provider；不能将全部故障归入此类 |
| 缺虚拟硬件后端 | 原始 vphone600 树缺 Stockholm NFC 子设备链，既有运行 registry 未见服务，宿主代码只组装 SEP；本实例没有可见的控制器／支付 eSE 组装。未审计闭源 hypervisor 的全部私有实现，不作绝对不存在断言 |

用户态库、内核驱动、provider／硬件后端是独立层次。即使以后补驱动，仍需提供可运行的控制器／SE 后端；仅改设备树名称或 VM gate 不能补齐这些职责。本轮没有实施任何修复或验证绕过后的实际错误码。

## 来源闭环与只读方法

- 实例：`/Users/tubao/.vphone/init-test-20261022/5-20261023`，绑定 Core Bundle 与 guest 环境 `2.8.0-local.199abaf3`；未重新绑定、更新或部署。历史 boot-chain 名称保持原记录，不用它推断官方版本。
- 开始时五台 VM 均 stopped。`Disk.img` 以 `-readonly -nomount -noautofsck` 附加，底层虚拟介质 `Writable=false`；仅把 System、Preboot 以 `diskutil mount readOnly` 挂载到研究目录，两个卷分别验证 `Writable=false`。未挂载 Data、xART、Hardware 或读取 SEPStorage。
- 用户态来自实际 System 的 `System/Cryptexes/OS`；其中 `SystemVersion.plist` 确认为 iPhone OS `26.6.2 / 23G90`。正常 `System/Library/Caches/com.apple.dyld` 是指向该 cryptex 目录的相对链接；本轮使用显式实际路径分析。
- 用户态原版对照：既有 `iPhone17_3_26.6.2_23G90_Restore-be187396844b.ipsw`。通过 ipsw 定向提取 arm64e 共享缓存，再分别从原版与部署缓存提取两库；不提取整个文件系统。
- 内核不是同版本的实体 iPhone 内核，而是 cloudOS `26.4 / 23E5207q` 的 `kernelcache.research.vphone600`。Preboot `active` 指向的目录已读取，其中实际 kernelcache 源／副本 SHA 相同；详细版本与完整清单见 [实际启动内核报告](nfc_kernel_inventory_20261023.md)。

完成取证后已卸载两个只读卷并弹出本轮附加的整块镜像设备。Disk.img 的大小、mtime、ctime 前后相同；这是结合只读介质的验证，不冒充对 64 GB 文件做了前后完整哈希。没有卸载或干预原有 Simulator 镜像。

## 同版库的身份与原版比较

实际与原版共享缓存均为 arm64e，cache UUID `F216D3F4-7064-3359-8840-41C1D1A2A72E`，含 4,315 个 image。相同 cache UUID 不代表整套缓存逐字相同；本轮针对两库单独比较。

| 库 | 原版与部署共同 Mach-O UUID | 同工具提取产物共同 SHA-256 |
| --- | --- | --- |
| `libPN548_API.dylib` | `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9` | `4960bb6a3c44fabd86c6b045aa6049b2047eca2dbb53ba3ab13026522e1ed220` |
| `libNFC_HAL.dylib` | `B1924DF9-CE33-3CEC-98EB-AC9B11841E0B` | `c7df2979ca22a8b21208cff8047a390b8faede85d81d66f82545491fa3d50d10` |

两对重建产物 `cmp` 均逐字相同。上表是 ipsw 从 DSC 重建的独立 Mach-O 分析产物摘要，不称作 guest 上独立 dylib 文件的完整哈希，因为实际库存在于共享缓存中。

另直接从两套原始 DSC 按 image／section 导出 `__TEXT.__text`，不依赖重建 Mach-O，结果也逐字相同：

| 原始代码段 | 字节数 | 两端共同 SHA-256 |
| --- | ---: | --- |
| libPN548_API `__text` | 274,720 | `3cdef11de07715817aa33a3ca91cc16220df2761b2b729d3c78246fcc3542270` |
| libNFC_HAL `__text` | 103,028 | `c1cb789f8a3881f127ed9d795dc552c6ecf6de7a2ca9519f5e75aa428b6415b4` |

由此确认当前两库代码与对应 23G90 原版一致，没有用 26.1 反编译替代当前实现。PN548 的当前字符串标识为 `Stockholm_Base-366.9.1`，与之前参考的 26.1 `361.6` 有别。

## 当前 HAL 实际要求什么

以下地址均为当前缓存的离线未滑动地址，只用于追溯，不是补丁偏移。

| 当前符号／位置 | 直接核对结果 |
| --- | --- |
| `NFHardwareSerialGetDefaultInterfaceType` `0x2a30118f0` | 查询 `AppleStockholmControl` 与 `nfc,primary,gpio`，失败时有设备树慢路径／等待；再查询 `AppleStockholmSPMI` 与 `nfc,primary,spmi` |
| provider helper `0x2a3011ca8` | 组装匹配字典；实际缓存 CFString 核对键为 `IONameMatched`、`IOPropertyMatch`，与服务类／设备名称共同匹配 |
| 默认接口的 CFString `0x2b2412750` | 当前缓存解析到 `stockholm-spmi-data-socket`；这描述 SPMI 数据传输接口选择，不是远程 IP 配置 |
| `NFHardwareGPIOOpen` `0x2a3010d98` | 选择 `AppleStockholmControl`／可选 `AppleHammerfestControl` 服务，并经 `IOServiceOpen` 打开控制用户客户端 |
| `NFHardwareInterfaceIsSupported` `0x2a301a7ac` | 接受空默认值、`com.apple.*`、`/dev/*` 后转到 `NFHardwareSerialIsSupported`；其它接口返回不支持 |
| `NFHardwareSerialIsSupported` `0x2a3012be8` | 检查 Stockholm 的 primary／可选 secondary GPIO provider，并有设备树回退 |
| `NFHardwareInterfaceGetType` `0x2a301a930` | 尾调用当前 `NFHardwareSerialGetDefaultInterfaceType` |
| `NFDriverOpen` `0x2a30708ec` | 正常默认接口经 stub island 转到上述 GetType；接口为 0 的路径构造 `HW is not supported`，并有 UART／SPMI 路径选择 |
| `NFDriverGetSecureElementInfo` `0x2a307c2a4` | 检查 SE 类型、wired-mode 状态及已枚举的 SE 对象；存在 `eSE not in wired mode`、`No SE of type` 失败分支 |

`NFDriverOpen` 至 GetType 的岛代码 `0x2a351eae0` 直接计算目标 `0x2a301a930` 并跳转；这次已把之前反编译里未解析的接口类型调用补齐。

当前 `NFHardwareSerialOpen` 仍出现 `socket(32,1,2)`、CTLIOCGINFO 路径，配合当前 native stub 映射确认 `_socket`／`_ioctl`，符合 Darwin kernel-control transport。GPIO 的调用岛 `0x2a351d420` 与当前 `_IOServiceOpen` 自有 stub `0x2a301addc` 使用同一目标指针槽，也已独立对应；没有把一个普通 TCP APDU 服务当成此接口。

**工具边界**：Xcode otool 对从 DSC 重建的独立库，部分外部 stub 标签错误地重复显示同名符号，部分跨 image CFString 无法解析；这些注释未作为调用依据。本轮另使用原始 DSC 的 `dyld macho --stubs`、按 VMA 的 bounded `dyld disass --quiet`、CFString 对象／字符串直接读取交叉核对。带全局符号标注的 disass 长时间停在解析 public symbols，已停止本轮该进程；`--stubs` 的无关 libobjc protocol 解析警告也保留，未用该 ObjC 结果得出结论。

工具行为参考本轮经 MCP 抓取的 [ipsw 官方 dyld 文档](https://blacktop.github.io/ipsw/docs/guides/dyld/)；分析未调用远程 LLM 反编译或上传固件内容。

## 启动内核的具体缺项

实际 active Preboot 的 IMG4 SHA 为 `32b1c4512f73cf748b7191e07132c35e0dc8c3f33ec79c97ecd16bf778ad3f74`。解压 payload UUID 为 `BCD06230-CCBE-8E48-50FF-D9C166D83CD5`，SHA 为 `efd82d78596f1d96db6a23a5cea05b4b85d5fbc8fec02d556265db606003b086`。

部署 payload 与官方 research 的完整摘要不同，符合已有内核补丁；**相同 UUID 不能代替哈希比较**。本轮比较到完整 kext JSON 与 C++ 类发现 JSON 均逐字相同，清单为 162 个 kext／KPI 元数据项、146 个 fileset 项、791 个人格、1,921 个已发现 C++ 类。

- 具体 `AppleStockholmControl`、`AppleStockholmSPMI`、`AppleStockholmControlUserClient`：无对应 bundle／人格／类发现。
- `AppleSSE`／UserClient、`KernelRelayHost`：也无对应实现证据；它们是其它 SE／relay 路径的相关对象，不把它们都列为 iPhone Stockholm 路径的必需驱动。
- `AppleARMSPMIController`、`AppleARMSPMIDevice` 及其 UserClient：通用基类存在；AOPSMC／SPU 通用能力也存在。这些不是 Stockholm NFC 控制器。
- 内核里可以搜到 Stockholm／SSE 字符串，但对应名字出现在 sandbox 权限策略中。完整 bundle／人格／类核对没有支持“具体驱动已编入”；不能用字符串搜索推翻清单。

完整身份、release 对照、人格字段与地址见 [内核清单报告](nfc_kernel_inventory_20261023.md)。结论限定于当前启动集合，不将其扩大为磁盘上不存在任何另行加载的软件包，也不把 C++ 类恢复当成覆盖全部代码形态的形式证明。

## 对照 provider 与虚拟硬件

当前 HAL 已确认仍查询此前分析中的具体 Stockholm 类／名字。此前 [原始设备树及运行 registry](nfcd58_vm_guard_analysis_20261023.md) 证据与本轮结果可以对应起来：

1. 原始 vphone600 树不含 NFC／Stockholm 子设备链，实体 D47 原树则有 SPMI parent、GPIO 子节点及相应 reg／IRQ／唤醒描述；其原始摘要此前已核对。
2. 同实例此前采集的 IOService／IODeviceTree 没有具体 Stockholm provider；这是历史运行快照，本轮没有启动 guest 重新采集。
3. 现有宿主代码只配置虚拟 SEP，没有支付 SE／Stockholm 控制器的组装；本轮没有修改宿主或尝试探测未公开 hypervisor 接口。

因此，通用总线代码存在不足以归类为“支付硬件已在，只等匹配”。具体驱动和匹配链缺项已经确认，虚拟设备后端仍须独立提供，不能通过补一个库或属性解决。

## 验证、清理与保留

已完成：版本与 active 路径核对、原版／部署两库 UUID、重建产物 cmp、原始代码段 cmp、当前函数／匹配键确认、实际内核清单与类发现对照；全部在宿主离线进行。没有重新执行原生能力探针或改变任何返回值，也未验证假设中的替代后端。

证据分别在 Git 忽略的 `.build/validation/nfc-current-libraries-20261023/` 与 `.build/validation/nfcd-current-kernel-20261023/`。保留小型库、原始代码段、内核与完整清单、关键反汇编、身份／挂载／卸载／断言记录；提取用的约 5.8 GiB 原版共享缓存中间件在本轮分析后删除。研究目录 0700、证据文件 0600。

最终核对：本轮只读挂载全部退出，五台 VM 仍 stopped；只更新研究记录，不新增产品代码、驱动、固件补丁或版本变更。
