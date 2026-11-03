# 无RF原型：guest前端、原库harness与首个可运行边界

日期：2026-10-23。本轮仅方案与离线接口核对，不部署、不执行Apple库/VM/HAL/后端、不改系统/gate、不绑卡、不写hook/补丁/产品代码。
**建议先做独立自有原生协议harness；原Comet作为被测库的harness是第二个独立里程碑，接入方式尚未验证。保留stock nfcd的内核兼容前端目前更重，不应当作首个Demo的前提。**

## 对象、现有代码与证据

- 用户态固定23G90：Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`；HAL UUID `B1924DF9-CE33-3CEC-98EB-AC9B11841E0B`；PN548 UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`。均沿用已校验副本；本轮不重新提DSC/挂载guest。
- target仍是实际部署 `kernelcache.research.vphone600`，UUID `BCD06230-CCBE-8E48-50FF-D9C166D83CD5`，Darwin25.4/VRESEARCH1；实体donor是Darwin25.6/T8140，不能称同版内核。
- 按kernel skill先查询旧符号DB的release/research行；记录指向旧机器路径，本轮不使用旧地址。当前内核依据[兼容性报告](stockholm_kernel_compatibility_20261023.md)及其同版KC证据，不重跑加载实验。
- CodeGraph MCP首次排队繁忙后，使用其CLI完成当前源码定位：[VM配置249行](../../VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachine.swift#L249)有Virtio socket；295行配置虚拟SEP，**这些入口没有Stockholm/NFCC设备组装**。不把这一定向范围扩大成私有框架穷尽审计。
- 独占证据 `.build/validation/nfc-no-rf-prototype-20261023/guest/`：本版ConfigureDriver、TML Init/Read/Write、NFHardwareInterface工厂/间接调用摘录；只作静态文本处理。

## 路线比较

| 路线 | 真正覆盖什么 | 当前缺口 / 能否做首个闭环 |
|---|---|---|
| 自有原生harness，自己拥有transport接口 | 协议状态、拆粘包/CRC/HCP/credit/模式/请求关联及宿主普通测试SE | 可最先实现与单元/进程间验证；**不执行原Comet，不是原生nfcd通过**。 |
| 独立guest harness，以原Comet为被测库 | 原Comet初始化/模式/数据及真实callback；避免走nfcd入口 | 导出存在，但替换TML绑定、完整私有ABI、进程准入未证明；目前不能承诺“dlsym后接socket就能跑”。 |
| 独立guest harness，以PN548为被测库 | 还覆盖NFDriverOpen/LoadStack、PN队列/等待/枚举/恢复 | 原PN Open继续选择原HAL服务；比直接Comet多一层产品策略，不能自动避开硬件缺项。 |
| 原HAL+新guest内核兼容前端 | 原nfcd下方IOKit、控制/stream及后端 | 接口恢复较充分，但KC/ABI/准入、服务匹配、VM gate均仍需独立解决；非首个无系统改动Demo。 |
| 抽实体Stockholm直接加载 | 试图保留原私有驱动 | fileset提取物不是原始可重链接kext；donor fixup/ABI/provider未闭环，不选作最小路线。 |

独立进程隔离的是nfcd入口与实验影响面，不是把系统 `NFProductIsVM` 改为0。它仍可能遇到PN/HAL的产品、provider、签名和沙箱检查。

## 若保留stock nfcd，guest必须补齐什么

原链为 `nfcd→PN548→Comet→HAL TML→IOKit控制 + kernel-control stream→NFCC/SE后端`。
[前次只读实测](nfcd_vm_guard_runtime_probe_20261023.md)的 `NFProductIsVM=1` 与同哈希nfcd分支相符；即使下方接口齐全，本轮未改变的stock入口仍有该门槛。前端完成与stock nfcd进入Open是两个验收项。

| 必需面 | 已恢复的实际契约 | 尚未证明 |
|---|---|---|
| 匹配/属性 | Control `AppleStockholmControl` / `nfc,primary,gpio`；SPMI `AppleStockholmSPMI` / `nfc,primary,spmi`；`stockholm-spmi-data-socket`为OSBoolean true | 新前端正常注册/provider策略；单改名字/设备树不能替代。 |
| UserClient | `IOServiceOpen(...,type0)`；同步scalar selector0..11；0/1/2/3/5/8/11输入1个uint64，6/7输入0，4/9/10也输入1并保留原失败；无scalar/struct输出 | 新实现准入、所有控制/错误状态及目标内核ABI。 |
| 数据 | `PF_SYSTEM32/SOCK_STREAM1/SYSPROTO_CONTROL2`，`com.apple.spmi.nfc`；CTLIOCGINFO动态ID，unit0请求、内核分配unit，单活动client | 生命周期/partial I/O/取消/断连/背压的真实运行。 |
| options | level2：CRC `80047301`、OnDemand `80047302`、errors get `40407303`、clear `80047304` | 错误寄存器bit与虚拟后端映射，不可全部假成功。 |
| 错误通知 | 独立IOKit IOGeneralInterest消息 `e3ff8001`，有界TLV/终止；不是stream payload | 新前端通知/清错副作用与后端一致。 |
| 协议后端 | controller初始化、vendor/FW/EEPROM、NFCEE、HCI、ModeSet、APDU与移除/超时 | 原生完整初始化/运行trace；普通APDU服务不能直接顶替整层。 |

上述详情见[HAL前端契约](stockholm_hal_frontend_contract_20261023.md)、[kernel-control契约](stockholm_kernel_control_contract_20261023.md)。VSOCK可承载**新适配器内部**guest↔host桥接，不能把同名用户态TCP/Unix/VSOCK服务直接当Darwin kernel-control。

服务级授权不能省：实体UC正常路径将 `IOUserClientEntitlements` 设为 `com.apple.stockholm.kext.entitlement`（secondary另名）；per-method entitlement=NULL不等于任意App可打开。
本轮经MCP读取[Apple XNU正常打开授权检查](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOUserClient.cpp#L4261)：缺所需task entitlement返回NotPrivileged并释放client；私有target同版通用函数尚未逐指令/运行核验，见[driver报告](stockholm_driver_imports_vtables_20261023.md)。
新独立程序的有效签名/entitlement、沙箱和IOKit访问必须实际验证；已有临时App可安装不证明拥有Stockholm权限，也不能通过伪写plist声明得出可用结论。

目标有通用KPI/若干SPMI基类，不表示已有具体Stockholm/AppleSPMIController/provider。保留实体driver还需MMIO/IRQ/GPIO/AOP运行契约；新建较高层前端可能减少这些硬件细节，仍不能省掉guest驱动准入。两端KC链接/PAC及非预链接加载限制见[内核兼容性](stockholm_kernel_compatibility_20261023.md)，本轮没有发现/验证可用新KC链接加载链。

## 原库harness的真实窄边界在哪里

### 1. Comet→TML：最有价值的候选，而非已可注入接口

Comet的当前导入表真实绑定 `/usr/lib/libNFC_HAL.dylib` 的14项TML符号：Init、Read/Write、ReadAbort/WriteAbort、IoCtl、FlushTxRxBuffers、Shutdown、ConfigureSpmi、ConfigHsuBaudRate、GetHsuMaxBaudRate、ConfigureTestParams、SetGetSpmiDrvConfigRegs、SpmiDrvErrorStatus。
这一层比重建IOKit/KC窄，覆盖的仍是**异步transport+控制生命周期**，不是只有read/write两个同步函数。

| 本版入口 | 直接证据/ABI边界 |
|---|---|
| Comet导出 `Mgt_ConfigureDriver 2a2f747b8` | 构造配置并驱动event1；内部ConfigDriverTrans `5cf7c` 在 `5d0d8–e0` 把配置子结构交 `phTmlNfc_Init`，不是传入自定义fd。 |
| HAL导出 `phTmlNfc_Init 2a3007440` | 输入配置和输出handle指针；读取路径、queue/上下文等；`77b4/77e4` 固定调用 `NFHardwareInterfaceOpen`，并非让调用者传transport factory。 |
| HAL导出 Read `2a3003e10` / Write `2a30053b8` | 入口观察到x0 handle、x1 buffer、x2长度、x3 callback、x4 context；异步分支组装block，`3ef0/546c` 调InterfaceReadBlock/WriteBlock。**长度的完整C声明、完成结果结构/所有生命周期尚未全证，不能据此直接写强转typedef调用。** |
| ReadAbort `2a30085a4` / WriteAbort `2a30083a8`、IoCtl `2a3001d68`、Flush `2a3008894`、Shutdown `2a3007e34` | 均有真实导出/调用；替换实现须覆盖取消/电源/复位/清理，不把pending0d当事务完成。 |

Comet的 `LC_REEXPORT_DYLIB` 与两级命名空间依赖固定HAL路径；`dlsym`能找到函数只证明可定位入口，**不证明原库的既有导入会转到harness提供的同名函数**。尚无本版可复现的合法transport注册、链接替换或运行绑定验证。本轮未写interpose、修改GOT、动态注入或补丁。

### 2. HAL内部硬件对象表：确有间接调用，但没有公开setter

`NFHardwareInterfaceOpen 2a3018afc` 分配8字节外句柄和110(hex)字节内部对象，自己按路径组装Serial/GPIO函数表。
`18ba4–bd0` 接受 `com.apple.*` 或 `/dev/*`；未知前缀报Unknown interface，不接受任意host/IP URI。SerialOpen随后仍按路径走kernel-control或设备节点，不能把环境变量改成IP当作桥接已经成立。

- ReadBlock wrapper `2a30018dc` 取内部表+18的函数，WriteBlock `2a3005990` 取+28，backend opaque对象在+90；均使用认证间接调用。
- 表/opaque对象是工厂内部布局，不是已证明可供外部注册的struct。普通callback（完成通知）与transport方法表是两回事；未发现可复用的factory/setter证据。
- `/dev/*`/UART路径是候选输入，但还有IsSupported、termios/ioctl、GPIO/reset和profile要求。**尚未证明PTY/fd能承接原PN/Comet**；不能把“能打开字节流”当兼容。

### 3. PN548导出API：适合后一级验收，不自动解决接入

`NFDriverOpen 2a30708ec→block2a308634c` 仍选择原接口并配置原Comet；`NFDriverLoadStack 2a3054d5c`还含产品flags/步骤和错误恢复。
独立程序可在未来以这些导出为被测入口，但仍需完整Open参数结构、driver/队列所有权、通知、等待和关闭ABI。现有研究没有一个已编译并执行的23G90原库harness。
直接从Comet开始可少测PN层；通过Comet不等于PN LoadStack通过，PN通过也不等于stock nfcd readiness或Wallet通过。

## 推荐的首个可运行闭环与升级门槛（后续实施方案）

1. **P0，自有协议harness**：独立原生可执行程序，transport接口由实验代码编译期注入；先本机memory/Unix双端测试，再独立guest↔host桥接。使用明确标记的普通测试applet/测试SE，只验证本实验模型，不能用固定`9000`冒充真实SE执行。
2. P0最小验收是有真实请求/应答关联、状态演进、分片、credit、取消和超时的一笔普通数据事务，并有失败/断连收尾；初始化未实现阶段明确返回不支持。只覆盖了子集就按子集命名，不能宣布LoadStack完整通过。
3. **P1，原Comet harness**：先补完整配置/回调ABI与binding证据，证实本版导入确实接入实验transport，并记录加载映像身份；然后逐级验证init callback、真实SE列表/模式、一次data callback。证据不满足就停在“未能接入原库”，不要补成功callback。
4. **P2，PN548 harness**：在同一后端上增加原Open/LoadStack/枚举/模式及PN等待/恢复验收，保留本版产品策略；“不做RF交易”不等于改 `NFProductHasNFCRadio` 或跳过必需静态配置。
5. **P3，stock集成**：只有需要验证原daemon时，才单独评估guest kernel前端、正常权限/准入、nfcd gate和部署；这是新阶段，不是P0/P1默认副作用。

原Comet/PN为iOS arm64e库，不能只因宿主也是arm64就假定macOS可加载运行。分析用重建Mach-O保留cache encoded data，text一致也**不保证它是可独立加载的dylib**；原库harness应以后使用guest系统原路径/共享缓存并核对身份，而非把研究提取物当运行包。
已有Virtio socket只是桥接基础设施；guest诊断进程的签名、sandbox/AF_VSOCK权限和生命周期仍待验证，不能从vphoned已有通道可用推断任意App都有相同权限。首轮不向vphoned、VM manifest、Launchpad或helper添加NFC业务字段/注册入口。

## 停用与删除边界

未来实现若获准，建议使用独立具名实验条件 `VPHONE_EXPERIMENTAL_NFC_NO_RF`，默认未定义；只编译实验target/适配组装，guest与host分别受控。名称是方案，本轮未增加空宏或target。
关闭时不注册实验命令/端口/后台任务，不调用原私有库、不改基础设备选择；移除实验实现/资源/定义后基础VM路径保持不变。若后续选择系统/固件改动，关闭宏不自动还原已部署产物，必须另有原始输入恢复与验收，不能伪称“宏关了就回到stock”。
本轮不生成App/IPA、驱动、服务器或部署包；没有新增运行态需要停用。只有本报告和小型取证摘录。

## 本轮结论的限度

目前已恢复足够多的接口与状态机来设计原型，但**没有可直接复用的原Comet transport注入API、已运行原库harness或已可加载Stockholm兼容前端证据**。最短可审查实现应先是独立实验模型，再逐层增加原库兼容性；支付SE身份、应用/密钥、SEP配对和Wallet仍是另一层未解决能力。
