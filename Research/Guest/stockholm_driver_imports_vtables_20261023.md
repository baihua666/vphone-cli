# 23G90 Stockholm 的实际导入、vtable 与控制 selector

2026-10-23。只分析既有离线内核副本，不启动／挂载 VM、不加载驱动、不改系统或 VM gate、不绑卡；不生成补丁。本文负责 driver 控制面，HAL 与 kernel-control 数据面另见配套报告。

配套：[HAL 与最小前端总清单](stockholm_hal_frontend_contract_20261023.md)、[kernel-control 服务端](stockholm_kernel_control_contract_20261023.md)。

## 结果

**控制面已恢复成 12 项、参数固定的同步 scalar selector 表；它本身不传 APDU／NCI 数据。** 比移植实体 SPMI 控制器更窄的候选前端是实现 HAL 所需的控制服务／UserClient 和独立数据接口，但不能只让 selector 返回成功：电源、复位、唤醒和底层后端状态仍须真实一致。

实际导入可归属到 kernel 和 AppleARMPlatform。基础 vtable 的 PAC 元数据与目标高度一致，改善了 ABI 的相似证据；尚未恢复全部私有函数符号、所有间接调用身份和平台执行语义，不能宣布二进制移植已通过。

## 固定对象与方法

- donor：`.build/validation/stockholm-portability-20261023/iphone/macho/kernelcache.release.iphone17.im4p.decompressed`，Darwin 25.6.0 / xnu-12377.162.14~4，UUID `F1D7B76F-7A81-F693-00D2-B4D68F27BA08`，SHA-256 `306b2588429739eb3c6b9d9a7633c260840729cdaa29532bf448ba957f258aac`。
- target：`.build/validation/nfcd-current-kernel-20261023/deployed/deployed-kernelcache.img4.decompressed`，Darwin 25.4.0 / research.vphone600，UUID `BCD06230-CCBE-8E48-50FF-D9C166D83CD5`。用户态同为 23G90，但两端内核并非同版，见 [兼容性报告](stockholm_kernel_compatibility_20261023.md)。
- 先前已按 kernel-analysis-vphone600 skill 查询旧数据库；其 JSON 不在本 checkout，所有本轮地址来自当前 donor／target。以下都是离线未滑动地址，仅作身份核对。
- donor Stockholm entry 已剥离 nlist 符号。采用实际 LC_FILESET_ENTRY／各 section 地址区间、chained fixup 解码、LC_FUNCTION_STARTS、`ipsw kernel cpp --methods` 与 LLVM 反汇编组合；不把工具生成的 `fn_0x...` 当作原始函数名。

## 实际导入归属

| 范围 | kernel | AppleARMPlatform | 其它 bundle |
| --- | ---: | ---: | ---: |
| `__auth_got` 认证槽 | 82 | 1 | 0 |
| `__got` 非认证槽 | 16 | 1 | 0 |
| text 中直接外部 `b`／`bl` 的不同目标 | 82 | 1 | 0 |
| 上行对应调用／尾调用 site | 904 | 7 | 0 |

恢复数量分开记录：**100/100 个 GOT 槽的实际目标地址与所属 bundle 已恢复；83 个认证函数槽的原始 mangled 符号名／完整签名恢复为 0/83**。可精确匹配的 3 个 kernel metaclass 身份，以及 1 个 ARMPlatform 间接元类布局身份属于数据项，不冒充函数导入名。直接 branch 的 83 个不同外部目标中，`00ae278b0` 可由表校验函数体与公开源码高置信识别为 IOUserClient2022::dispatchExternalMethod；该目标也在 GOT 的 `0xfffffff007fec498`，所以按函数语义名统计为 1/83，按原始 mangled 名／完整签名统计仍为 0/83。这是语义识别，原始符号表仍不存在。其余 kernel 函数不凭近邻或 PAC 值命名。

全部 100 个 GOT 槽和 911 个外部 branch site 均映射到唯一 owner；不含本 entry 内部调用。数字是静态 site 数，不是运行次数，且没有包括间接调用。因此不能据此排除运行时经 provider、平台函数或其它对象触达额外依赖。

AppleARMPlatform 的直接函数目标唯一为 `0xfffffff008417460`，GOT 槽在 `0xfffffff007fec490`。7 个调用点会把 `function-wake_stockholm_soc`、`function-enable`、`function-download_request` 等属性名传给它；返回对象随后被保留并通过虚方法执行。callee 先将字符串转换为对象、调用另一个本 bundle helper，再释放临时对象。**可确认其平台功能查找作用，尚无原始符号，本文不把它虚构命名成确切 C++ API。**

另一 ARMPlatform 数据槽 `0xfffffff007fec660` 指向 `0xfffffff007da0388`；该处首项 chained target 为 `0xfffffff00b3786e0`，与 `cpp.json` 的 **AppleARMSPMIDevice MetaPtr** 完全一致，下一项为 IOService 元类。故它是相应元类布局引用，不能把 GOT 目标本身误写成 MetaPtr。

kernel GOT 可直接与 metaclass 匹配的例子：`0xfffffff007fec658 → 0xfffffff00b23e3f8` 为 IOUserClient2022，`...c670 → ...b23e7e8` 为 OSObject，`...c678 → ...b23e888` 为 IOService。其余 stripped 函数只保留地址／owner；没有用邻近地址代替精确身份，也没有把全部 GOT 项都叫作函数导入。

## UserClient 入口与 40 字节 dispatch 表

AppleStockholmControlUserClient vtable `0xfffffff007fecd48`，187 槽；继承 IOUserClient2022。

- 新 externalMethod override 在 vtable `+0x5d0` → `0xfffffff009336e6c`，PAC diversity `0x5d9d`。
- 该入口取对象 `+0xd8` 的控制服务，传 `dispatch=0xfffffff007fed3b0`、`count=12`、reference=0，尾调用 kernel `0xfffffff00ae278b0`。
- callee 实际在 `...278d8` 比较 selector 与 count，`...278e0/e4` 计算 `selector × 5 × 8`；之后检查 scalar／struct 长度、async 与 entitlement。此二进制行为和公开 `IOUserClient2022::dispatchExternalMethod` 对应，识别不只依赖函数相邻位置。
- 表布局与 Apple [IOExternalMethodDispatch2022 定义](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/IOKit/IOUserClient.h#L155) 一致：函数指针、4 个 uint32 参数计数、allowAsync、对齐后的 entitlement 指针，共 40 字节；[公开校验流程](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOUserClient.cpp#L6205) 用来解释语义，不冒充这份私有构建逐行源码。

全部 12 项均为 `scalarOut=0, structIn=0, structOut=0, allowAsync=0, checkEntitlement=NULL`。**最后一项只表示没有 per-selector entitlement；UserClient 打开授权、sandbox 和服务级 entitlement 仍独立生效。**

| selector | scalarIn | action 地址（统一前缀 `0xfffffff`） | 实际转发／行为 | driver 自身日志名称 |
| --- | ---: | --- | --- | --- |
| 0 | 1 | 009336e88 | 非零转 bool → Control `+0x540` / 0093484f4 | setEnable |
| 1 | 1 | 009336f20 | 非零转 bool → `+0x550` / 009348734 | setDownloadRequest |
| 2 | 1 | 009336fb8 | 非零转 bool → `+0x558` / 009348844 | setPMUStandbyPowerEnable |
| 3 | 1 | 009337050 | 非零转 bool → `+0x560` / 009348950 | setStandbyEnable；HAL 称 device wake |
| 4 | 1 | 0093370e8 | 直接返回 `0xe00002c7`（Unsupported） | 无恢复名称 |
| 5 | 1 | 0093370f8 | 非零转 bool → `+0x548` / 009348634 | setVBATEnable |
| 6 | 0 | 009337190 | direct → 009348b88 | validateSPMIConfig |
| 7 | 0 | 0093371dc | direct → 009348ce0 | configureHammerfestSPMI |
| 8 | 1 | 009337228 | direct → 009348e38；wrapper 不读 scalar，但表仍要求 1 个 | sendFollowerReset |
| 9 | 1 | 009337274 | 直接返回 `0xe0000001` | 无恢复名称 |
| 10 | 1 | 009337274 | 同 selector 9 | 无恢复名称 |
| 11 | 1 | 009337280 | 只读 scalarInput[0] 的低字节 → 009348f90 | sendvGPIO |

driver 名称取自 **实际 LC_FUNCTION_STARTS 区间内 ADRP+ADD 的字符串交叉引用**；并与父任务恢复的 HAL selector 对照。例：Control `setEnable` 日志引用 site `0xfffffff009348588` → 字符串 `0xfffffff00767045b`。这保留了 HAL 的 device-wake 命名和驱动 setStandbyEnable 命名的差别，没有擅自合并为硬件相同信号。

## 打开 UserClient 的授权与 selector 授权不同

已核对 donor UC 初始化／start 函数 `0xfffffff009336c30` 的正常授权路径：`...336dd4–...336e10` 读取关联控制对象的状态位，向 UC 的 `IOUserClientEntitlements` 属性写入 `com.apple.stockholm.kext.entitlement` 或 `com.apple.hammerfest.kext.entitlement`；两字符串的实际 ADRP+ADD 引用分别在 `...336dfc`、`...336e08`。因此 `checkEntitlement=NULL` 绝不表示普通 App 可无权打开。本文只核对正常声明路径，不研究停用条件。

Apple 公开 [is_io_service_open_extended 正常授权检查](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOUserClient.cpp#L4261) 会取上述属性，检查 owning task 是否具有该名称的 entitlement；缺失时在 L4291–4293 返回 `kIOReturnNotPrivileged`，随后关闭／释放 client，不交付连接。该失败返回目前有公开源码佐证，**尚未对 donor／target 通用内核打开函数完成同版逐指令定位，也没有实际打开测试**。这一区分足够确认候选前端需要保留正常服务级授权，不能因逐方法表无 entitlement 而省掉它。

## Control／SPMI 的私有 vtable 与执行契约

Control vtable 为 `0xfffffff007fee2f0`，173 槽；前 168 槽对应 IOService 前缀，尾部 5 项即上表 0／5／1／2／3 的 bool 控制。setEnable 先通过字段 `+0x90` 的平台功能对象 `vtable+0x80` 执行，再在已取得 SPMI 对象时调用其 `+0x550`。其它控制也有缺失功能／缺失 SPMI 的显式错误路径，不能替换成无条件成功。

AppleStockholmSPMI vtable 为 `0xfffffff007feddc0`，175 槽。以下名称有所在函数的直接日志证明；`fn_...` 私有占位名仍不用作真实符号：

| slot | target（前缀同上） | 已恢复身份／证据 |
| --- | --- | --- |
| +0x540 | 00933cb88 | enable；日志 Rx interrupts enabled |
| +0x548 | 00933cc78 | disable；日志 Rx interrupts disabled |
| +0x550 | 00933dc34 | 包装器，经对象 `+0xa0` 的 `+0xe8` 虚调用传 gated callback 00933db80 与状态参数；未恢复原始名字 |
| +0x558 | 00933e714 | 包装器，传 `w0=0x20, x1=this+0xf8` 到 kernel 00ad0dd60；尚不命名其原子／位操作语义 |
| +0x560 | 00933fb64 | _rxInterruptHandler |
| +0x568 | 009340b94 | _rxMbufInterruptHandler |
| +0x570 | 00933e724 | _spmiErrorInterruptHandler |

SPMI 还调用继承的 IOService `+0x478 → 0xfffffff00ad8aab8`，PAC `0xa4c7`，作为 IOReturn→errno 转换；精确 C++ 名字需结合公开类顺序／函数体继续核对。kernel-control 五回调、socket option 与帧协议由配套数据面报告负责。

## 与 target ABI 的更细比较

| 比较 | donor／target 槽数 | 按相同 offset 比较 PAC diversity／key／addrDiv |
| --- | --- | --- |
| IOService | 168 / 168 | 全部一致，0 mismatch |
| donor StockholmUserClient 对 target IOUserClient2022 | 187 / 187 | 全部一致，含 overridden 槽位，0 mismatch |
| AppleARMSPMIDevice | 188 / 188 | 全部一致，0 mismatch |

这比只有实例大小相同更强：被调用的相关槽位在认证 schema 和数量上没有发现不一致。但 16 位 diversity 可能碰撞，且不包含参数语义、字段行为、锁、电源／中断模型。**不是完整 ABI 证明，更不意味着可复制 donor 地址或 PAC。** 目标没有 Stockholm 的私有尾部方法，仍需真实驱动或新实现。ARMPlatform 的平台功能 lookup helper 尚未完整映射到 target 精确符号。

## 对最小前端的含义与未知边界

1. 控制服务需要匹配 HAL 的服务／UserClient 打开路径，保留同步 scalar ABI、参数校验和错误；实验模型必须明确标识，不能作为产品假硬件。
2. 可先缩到 primary 控制器实际会调用的电源、download、PMU、wake、VBAT、validate、reset、vGPIO；Hammerfest 路径按当前 HAL 的选择核对。selector 4／9／10 的失败行为也属于契约，不应全部返回成功。
3. 此表明确没有数据 buffer／async completion。数据面仍要满足另一路 kernel-control 或合法选中的串行接口，并和控制状态、接收唤醒、断连同步；普通 APDU socket 不能独自承接。
4. 替换底层 SPMI provider 仍要提供 AppleARMSPMIDevice 的实际方法及平台功能对象。自写更高层 HAL 前端可避免复制这些私有 C++ 实现，但 guest 驱动准入与部署仍是独立未解决问题。
5. 未恢复每个 kernel import 的原始 mangled 名、全部虚调用字段类型、所有 gated 函数与硬件状态机；未进行加载／执行验证。无 RF 控制器模型也不等于支付 eSE、个性化或 Wallet 绑卡能力。

## 证据

`.build/validation/stockholm-interface-20261023/driver/`：imports.json（100 槽及 911 site）、dispatch2022.json、各 donor／target methods JSON、functions-strings.json、string-xrefs.json、donor-dispatch-helper.txt、armplatform-helper.txt；Ruby 只读解析脚本 map.rb 和原始定向反汇编供重现。工具 ipsw 3.1.714、Xcode LLVM、Ruby，无 Python。目录 0700／文件 0600。仅修改本报告，没有更改旧报告、journal 或产品代码。
