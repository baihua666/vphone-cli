# 23G90 Stockholm：HAL 与最小兼容前端接口清单

2026-10-23。继续对 `5-20261023` 对应的 23G90 用户态与实体固件进行离线恢复。没有启动／挂载 VM、安装 App、加载驱动、修改系统、绕过 NFProductIsVM 或绑卡；没有调用实际 HAL／SE API。提取器仅处理本地 IPSW 的固件中间镜像，不接触实例文件系统。

后续已恢复基础NCI／DNLD帧、Comet CRC及初始化阶段，见 [无RF最小协议闭环分析](nfcc_no_rf_minimum_protocol_20261023.md)。本文下述“帧／CRC尚未闭环”是此前阶段的缺口；完整厂商初始化与原生运行验证仍未完成。

## 本轮结论

**已把最小前端从“需要驱动”收敛成服务匹配、12 项同步 scalar 控制、stream kernel-control 数据、4 个 socket options、独立 IOKit 错误通知这五组契约。** 控制 selector 不传 APDU／NCI 数据；普通宿主 APDU socket 仍不足以承接原库。

实际导入的 100 个 GOT 槽已恢复地址与 owner，83 个认证函数槽中只有 1 个可高置信识别语义名称，原始 mangled 名／完整签名仍未恢复。相关基类的 vtable 槽数／PAC schema 与 target 相符，提高了 ABI 相似证据；不能据此宣布可直接移植。下列是静态恢复的契约，不是可运行前端，也没有通过原生 nfcd 验收。

配套证据：[driver 导入／vtable／分发表](stockholm_driver_imports_vtables_20261023.md)、[kernel-control 服务端](stockholm_kernel_control_contract_20261023.md)、[前轮内核移植边界](stockholm_driver_portability_20261023.md)。

## 固定版本及恢复方法

- HAL：当前实例此前取得的 `libNFC_HAL`，UUID `B1924DF9-CE33-3CEC-98EB-AC9B11841E0B`；与原版 23G90 的原始 `__text` 曾逐字比较，本轮又从同一本地 IPSW 提取 DSC，导出 103,028 字节并与该部署代码段逐字比较通过，SHA-256 `c1cb789f8a3881f127ed9d795dc552c6ecf6de7a2ca9519f5e75aa428b6415b4`。
- 新提取 DSC UUID 仍为 `F216D3F4-7064-3359-8840-41C1D1A2A72E`；当前 PN548／Stockholm build 为 366.9.1。没有用旧 26.1 反编译填入 selector 常量。
- driver：同版实体 `kernelcache.release.iphone17`，UUID `F1D7B76F-7A81-F693-00D2-B4D68F27BA08`。target 是实际部署的 `kernelcache.research.vphone600`，Darwin25.4／VRESEARCH1；donor 是25.6／T8140。没有将实体地址当成 target 地址。
- 重建 Mach-O 的部分 otool import 标签不正确。本轮先移除这些标签，再以原 DSC 的岛代码和库内 auth stub 的相同指针槽／相同直接目标，映射 88 个已识别调用岛；还有 1 个非空岛未命名。关键 IOConnectCallScalarMethod、IOServiceOpen、socket、connect、setsockopt 已独立对应。
- CFString 由原缓存对象及 v5 slide 元数据解码；对应字符串再与实际 `__cstring` 核对。工具为 ipsw 3.1.714、otool／LLVM、Ruby，无 Python、远程反编译或固件上传。

以下地址均为未滑动分析地址。HAL 为用户态 VA；driver 完整地址详见配套报告，不能把这些数值直接用作补丁或跨版本常量。

## 1. 服务匹配与能力属性

| 对象／入口 | 当前 HAL 的要求 | 最小前端要保留什么 |
| --- | --- | --- |
| 默认接口选择 `0x2a30118f0` | 匹配 AppleStockholmControl／`nfc,primary,gpio`，再匹配 AppleStockholmSPMI／`nfc,primary,spmi`；helper 使用 IOPropertyMatch／IONameMatched | 可被这些实际匹配条件找到的服务；单改显示名或 IOClass 字符串不能证明 metaclass／provider 匹配 |
| SPMI socket 选择 | 读取属性字典的 `stockholm-spmi-data-socket`，经 CFBooleanGetValue；false／缺失得到类型2，true得到类型3 | **OSBoolean true**；不是 socket 名字字符串。实体 driver 也实际 setProperty(key,true) |
| 控制打开 `0x2a3010d98` | primary 用 IOServiceMatching("AppleStockholmControl")；IOServiceOpen(service,mach_task_self,0,&connection) | client type **0**、有效连接句柄、原有授权／生命周期；不能假定空 per-method entitlement 就代表打开无权限要求 |
| secondary | 可选 AppleHammerfestControl／AppleHammerfestSPMI | 单 primary 实验可暂不承诺 secondary；不能让库误选已声明但未实现的服务 |
| HostWake 能力 `0x2a30113c4` | 以名称 stockholm 查服务，将 required-gpios 的 CFData 转为字符串，查 support_wake_stockholm_soc 或 support_wake_stockholm | 属性类型和真实能力一致；这不是 SPMI required-functions 中的 support_host_wake_spmi，不能混用 |

IONameMatched 的完整私有注册传播尚未追完；公开 IOKit 的人格匹配可以生成该提示，但不能据此宣称随意 set 同名属性就足够。对于关闭，HAL `0x2a301119c` 经 IOConnectRelease 释放连接、IOObjectRelease 释放服务并清本地句柄；前端还需处理客户端退出／资源释放，不只实现 open。

driver 正常初始化路径 `0xfffffff009336dd4–0xfffffff009336e10` 实际设置 IOUserClientEntitlements，使用 `com.apple.stockholm.kext.entitlement` 或 Hammerfest 对应字符串。公开 XNU 在打开阶段核对调用任务的授权；当前私有内核的通用失败分支尚未逐指令复核。前端必须保留这项边界，不能以分发表的 per-method entitlement=NULL 推断免授权。确切引用见 driver 报告。

## 2. UserClient：12 项固定同步 scalar ABI

当前公用 helper `0x2a30100b8` 在 `0x2a301011c` 调用 IOConnectCallScalarMethod：connection 从本地上下文读取，selector 透传，inputCnt=1、output=NULL、outputCnt=NULL。它先把输入低32位零扩为一个 uint64。validate／Hammerfest 两个入口另以 inputCnt=0 调用。同版 driver 的 40 字节步长 IOExternalMethodDispatch2022 表独立确认了下表。

| selector | 输入数量 | HAL 对应功能／call site | driver 实际行为 |
| --- | ---: | --- | --- |
| 0 | 1 | SetPower；`0x2a301007c` | setEnable；非零转 bool |
| 1 | 1 | SetDownloadRequest；`0x2a30105d4` | setDownloadRequest；非零转 bool |
| 2 | 1 | SetPMUStandbyPowerEnabled；`0x2a30106f8` | setPMUStandbyPowerEnable；非零转 bool |
| 3 | 1 | SetDeviceWake；`0x2a30053a0` | setStandbyEnable；保留与 HAL 命名差异，不推断电平相同 |
| 4 | 1 | 所核对 HAL wrapper 未见使用 | 返回 Unsupported `0xe00002c7` |
| 5 | 1 | SetVBAT；`0x2a30104b0` | setVBATEnable；非零转 bool |
| 6 | 0 | ValidateSPMIConfig；`0x2a30108d8` | validateSPMIConfig |
| 7 | 0 | ConfigureHammerfestSPMI；`0x2a3010bb0` | configureHammerfestSPMI，secondary 路径 |
| 8 | 1 | SPMIFollowerReset；`0x2a3010790` 尾调用 helper，值1 | sendFollowerReset；wrapper 不读取 scalar，但 dispatch 仍检查数量1 |
| 9、10 | 各1 | 所核对 HAL wrapper 未见使用 | 共用 action，返回 `0xe0000001` |
| 11 | 1 | SPMIvGPIO；`0x2a30107d4` | sendvGPIO，只取输入低8位 |

全部 selector 均为 scalarOut=0、structIn=0、structOut=0、allowAsync=false。对应标准 API 签名见 [Apple IOConnectCallScalarMethod](https://developer.apple.com/documentation/iokit/1514793-ioconnectcallscalarmethod)；driver 计数、action 地址及授权边界见配套分发表报告。

公用 HAL helper 返回原始 IOReturn，大部分 bool wrapper 以 `ret==0` 转为成功；FollowerReset／vGPIO 保留原始调用结果。`0xe00002ed` 还会设置 HAL 的 SPMI NACK 标志，供 GPIOWasItSPMINack 读取。前端须保留失败语义，不能所有 selector 都返回0。电源／唤醒与数据通道状态需要一致，控制表本身没有数据 buffer 或 async completion。

## 3. kernel-control：连接与数据生命周期

`NFHardwareSerialOpen` `0x2a30141b8` 以路径是否 `/dev/` 区分设备节点，以包含 spmi 区分 SPMI 模式。SPMI socket 路径恢复如下：

| 步骤 | 确切契约／证据 |
| --- | --- |
| 创建 | `0x2a3014304–4310`：socket(PF_SYSTEM=32, SOCK_STREAM=1, SYSPROTO_CONTROL=2) |
| 查 ID | `0x2a3014338–435c`：ctl_info 共100字节；ctl_name[96]；ioctl **0xc0644e03 / CTLIOCGINFO** |
| 连接 | `0x2a3014854–4874`：sockaddr_ctl 32字节；len32、family32、sysaddr2、ID为查询返回值、unit0、reserved清零 |
| 名称 | 当前 PN548 在 `0x2a30710a0`／`0x2a30711c0` 使用 **com.apple.spmi.nfc**；secondary 名为 com.apple.spmi.nfc.hammerfest；与 driver 注册结构吻合 |
| 非阻塞 | 正常路径 `0x2a3014da0` 调用内部 SetNonBlock；`0x2a3013444/3470` 为 F_GETFL=3／F_SETFL=4，设置 O_NONBLOCK=4；另有 relay 参数分支，不能把该字面量当成 TCP relay 实现 |
| 异步 I/O | 正常创建 dispatch read／write source；读回调 `0x2a3003490` 调 read，写回调 `0x2a3006108` 调 write；写后更新指针／剩余长度，支持部分完成 |
| Flush／关闭 | Flush `0x2a301307c` 循环 read 1字节至空，区分 EINTR=4、EAGAIN=35；关闭需取消 source、清通知和 fd，并与 pending I/O 同步 |

公开 [Apple kern_control.h](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/kern_control.h#L90) 用于核对 ctl_info／sockaddr_ctl 与动态 ID／unit 语义。原服务端注册 stream flag4、发送容量用内核默认、接收64 KiB，只允许一个活动客户端；unit由内核分配。kernel callback 的 size_t 长度与用户 getsockopt 的32位 socklen_t 不应混用。

**最小 SPMI 路径不必先实现 UART termios options**：SerialOpen 在 SPMI flag为真时跳过 socket 的 TIOCGETA/TIOCSETA；SetBaudRate 对 SPMI 也直接成功。`0x40487413`／`0x80487414`、72字节 termios 属所见 non-SPMI 分支，不能误列为 SPMI 初始化必需项。真正的 reset／供电仍由控制面承担。

## 4. 四个 options 与独立错误通知

全部 socket options 使用 level **2 / SYSPROTO_CONTROL**。名称来自当前日志，数值／长度来自实际寄存器赋值和 driver 分支。

| 功能 | option | 客户端参数与 call site | 服务端约束 |
| --- | --- | --- | --- |
| CRC | `0x80047301` | setsockopt，int32，len4；`0x2a3015d98` | 规范为 bool，影响接收长度／CRC路径 |
| OnDemand | `0x80047302` | setsockopt，int32，len4；`0x2a301602c` | 规范为 bool，影响实际接收策略 |
| SPMI errors | `0x40407303` | getsockopt；`0x2a3016374`；HAL将caller uint64容量低32位转socklen_t，再将返回len零扩写回 | **输入容量必须精确64**；并非返回固定64字节，成功最多15字节TLV |
| Clear errors | `0x80047304` | setsockopt，int32，len4；`0x2a30165c4` | 低8位为mask；实体实现写 SPMI register9 |

error TLV 为 `[type:u8,len:u8,value...]`：types4–8分别对应 Error status0/1、Parity status0/1/2，每项 len1。读取全部五项最多15字节；各寄存器读取失败可能返回较短内容。bit含义仍未还原。

**HAL 的 QuerySPMIError 不是只读查询函数**：get成功后立即按第四个参数发送 Clear errors；本轮没有调用它。不能在今后的“只读探针”里因 Query 命名而直接执行。

另一路通知：`0x2a30166b0` 创建 IONotificationPort、绑定 dispatch queue，向 AppleStockholmSPMI 订阅 **IOGeneralInterest**。回调 `0x2a3016bec` 仅处理 **0xe3ff8001**，逐项按2+len累加至type0或边界64，把有效数据及长度交上层 callback。driver 端独立确认发送相同消息，最多15字节TLV后追加零终止，通知长度最多16。它不是 socket 消息，不能塞进普通数据流替代。

## 对最小兼容前端的具体判断

| 必须实现的组 | 最小职责 | 尚未闭环 |
| --- | --- | --- |
| 服务与打开 | primary Control／SPMI 可匹配服务、正确布尔属性、type0 UserClient、原有授权与释放语义 | 完整服务注册／provider策略与 guest 准入 |
| 同步控制 | 上述12项的数量检查、真实控制状态与错误；保留4/9/10失败 | 所有平台功能、硬件状态迁移及二进制 ABI |
| 数据 stream | connect／disconnect、动态unit、单客户端、异步收发、partial I/O、背压／取消／断连 | 原 NFCC 数据模式／完整帧边界、CRC责任与算法、各恢复分支 |
| options／通知 | 四项精确方向和长度、合法TLV、清错副作用、独立IOKit通知 | 错误寄存器各bit的后端映射、完整errno转换 |
| 协议后端 | 与上述控制状态一致的控制器初始化、厂商命令、SE枚举／wired-mode、普通APDU | 尚无已验证的 Apple NFCC emulator 或支付可信SE |

自写这层前端可能避免移植实体 AppleSPMIController／T8140 MMIO／完整AOP栈；不能直接绕开 guest 的驱动加载、服务权限或 VM gate。VSOCK最多作为前端到宿主的内部桥接，原 HAL 仍看见 Darwin kernel-control／IOKit 接口。

当前证据足以编写独立协议模型的接口验收用例：严格校验scalar数量和错误、socket连接生命周期、四项长度／方向、partial I/O与背压、IOKit错误通知与清错状态。但本轮没有编写或运行模型。先继续恢复 NFCC 帧／CRC及初始化序列，才能判断最小后端是否真的能承接原 PN548 stack；仅做 SELECT APDU→9000 不能作为该验收。

## 导入与 ABI 结论的边界

Stockholm 的100个GOT槽归属为98个kernel、2个ARMPlatform；直接外部branch目标83个。83个认证函数槽中语义识别1个，原始完整符号恢复0个；其余保留精确地址及owner。已恢复的平台功能lookup还需执行取得的对象，而不是查到属性即完成。

IOService168槽、donor StockholmUserClient／target IOUserClient2022各187槽、AppleARMSPMIDevice各188槽，相同offset的PAC diversity／key／addrDiv都相符。但16位认证schema可能碰撞，也不说明对象字段、锁、电源、硬件协议相同；仍不是可直接搬驱动的证明。详细地址、方法名证据与未知项见 driver 报告。

## 证据与清理

本轮资料在 Git 忽略的 `.build/validation/stockholm-interface-20261023/`：`hal/hal-contract.json`、`interface-call-sites.json`、`island-to-symbol.json`、原始岛与stub反汇编、原始代码段／CFString对象、`cfstring-properties.json`；driver 与 kernel-control 子目录保存各自完整定向映射。只读解析的静态常量断言、跨端dispatch／option对照及文档链接／空白检查完成；没有运行guest测试。

提取用的约5.8 GiB原版共享缓存为可再生成中间件，收尾删除；保留上述小型证据。提取工具的固件中间镜像挂载已退出，目标 Disk.img 大小／mtime／ctime与前轮一致。未改变产品代码、驱动、固件补丁、版本或实例绑定；原有临时诊断App已在前轮清理，本轮未安装任何App。
