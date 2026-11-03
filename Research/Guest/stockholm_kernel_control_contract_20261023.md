# Stockholm SPMI kernel-control 服务端契约

2026-10-23；离线恢复实体 iPhone17,3 / 26.6.2 / 23G90 的 AppleStockholmControl 366.9.1。只读本地 KC 与提取产物；没有连接设备、启动／挂载 VM、加载驱动、改系统、绕过 NFProductIsVM 或绑卡。本文地址均为 donor 未滑动 VA，不能当 target 地址或补丁常量。

配套：[HAL 与最小前端总清单](stockholm_hal_frontend_contract_20261023.md)、[driver 导入／控制分发表](stockholm_driver_imports_vtables_20261023.md)。

## 结果与证据等级

**数据端是 Darwin kernel-control 的 SOCK_STREAM 服务，至少需要连接生命周期、双向字节流、四个 options 和独立 IOKit 错误通知。** 单纯监听同名 VSOCK／TCP 服务不能匹配原 HAL；普通 APDU 后端也没有覆盖控制器数据协议。

基于 `.build/validation/stockholm-portability-20261023/iphone/` 的原 KC、`kexts/com.apple.driver.AppleStockholmControl`、元数据／类表，以及本轮 `driver/disass.txt`、`imports.json`、`spmi-methods.json`。KC 身份与 SHA 见 [移植报告](stockholm_driver_portability_20261023.md)。驱动符号表为空，以下区分二进制可直接读出的常量／参数／分支，与按公开 KPI 签名和日志确定的语义名称；不能把推断的函数名冒充恢复出的导出符号。

本轮经 GitHub MCP 读取 [Apple XNU kern_control.h](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/kern_control.h)。其结构字段、回调签名、stream flag 与 mbuf 所有权用于解释下表；并非 Stockholm 私有源码。HAL 客户端由父研究并行核对，本文服务端数值已与其四个 options 和 notification 对齐。

## 注册及回调

注册结构不是静态完整表：在 `0xfffffff00933b778–0xfffffff00933b8cc` 的 start 路径中于栈上组装。`0xfffffff007670c90` 的 16 字节常量按 LE u32 解码为 `[0,0,4,0]`，另写 `65536` 与五个 PAC 签名回调指针。

| kern_ctl_reg 字段 | 恢复结果 |
| --- | --- |
| ctl_name[96] | primary：`com.apple.spmi.nfc`；secondary：`com.apple.spmi.nfc.hammerfest`；由对象 `+0xf1` bit 0 选择 |
| ctl_id／ctl_unit | 均初始化 0；没有 REG_ID_UNIT flag，使用内核动态 ID／连接 unit |
| ctl_flags | 4，即 CTL_FLAG_REG_SOCK_STREAM；此表未设置 PRIVILEGED，不据此推断整个 NFC 接口无权限限制 |
| ctl_sendsize | 0，使用 XNU 默认值；不是 64 KiB |
| ctl_recvsize | 65536 字节 |
| 注册调用 | `0xfffffff00933b8cc → 0xfffffff00ab8bddc`；结构、返回引用和后续用途符合 ctl_register，后者无可见符号名 |
| 保存引用 | 输出指向 `this + 0x118`；连接 unit 保存于 `this + 0x120` |

成功注册后的 `0xfffffff00933bd38–0xfffffff00933bd5c` 以 key `0xfffffff00766d86f = stockholm-spmi-data-socket`、`w2=1` 调用 IORegistryEntry vtable `+0xd8`（target `0xfffffff00ad86c5c`）。结合同版类槽位及 [公开 bool setProperty 实现](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IORegistryEntry.cpp#L899)，这是 **OSBoolean true 标志，不是 socket 名称字符串**。名字来自注册结构；兼容前端必须保持属性类型。

驱动 cstring 中未发现 IONameMatched；人格已声明 IONameMatch `nfc,primary,spmi`，匹配 provider 为 AppleARMSPMIDevice。公开 [IOService 匹配实现](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/iokit/Kernel/IOService.cpp#L7840) 在名称匹配成功且允许修改时，将 IONameMatched 提示写入人格字典。这解释该属性可能由正常匹配链产生；本轮没有完整跟踪私有内核从人格字典到实例注册的每一步，不能声称单独 set 同名属性即可取代 provider／metaclass 匹配。

| 回调角色 | 注册入口 | 经 command gate 调用的目标 |
| --- | --- | --- |
| connect | `0xfffffff00933c210` | `0xfffffff00934402c`，日志 ctl_connectGated |
| disconnect | `0xfffffff00933c47c` | `0xfffffff0093445d8`，日志 ctl_disconnectGated |
| send | `0xfffffff00933c548` | `0xfffffff009344748`，再进入 mbuf 发送 helper |
| setopt | `0xfffffff00933c5fc` | `0xfffffff0093447b4`，日志 ctl_setoptGated |
| getopt | `0xfffffff00933c64c` | `0xfffffff0093448dc`，日志 ctl_getoptGated |

connect 根据 kctlref 遍历已注册对象，匹配 `this+0x118`；找不到返回 2（Darwin ENOENT）。匹配后把对象写入 `unitinfo`，串行进入 gate。gated 路径检查 `this+0xd0`：已有连接返回 16（EBUSY）；首次连接从 sockaddr_ctl 的 `+8` 取实际分配 unit，记录计数及 socket-client 状态，并启用接收／相应 wake 行为。HAL 请求 unit 0 不意味着实现可以把所有连接固定成 unit 0 或 1。

disconnect 的空 unitinfo 路径返回 2；正常路径按 unit 比较，清 unit／连接计数，并在相应状态下禁用接收。实际电源／平台分支不能简化成永远成功。connect/disconnect/send 的 IOReturn 经 `this vtable+0x478` 转换；目标 `0xfffffff00ad8aab8` 为继承 IOService 方法，按槽位／调用形式解释为 errnoFromReturn，未恢复完整内部映射表。不能直接把 `0xe00002xx` 返回给 POSIX socket 客户端。

## 四个 socket options

统一 handler `0xfffffff00934363c`：set 传 direction=1，get 传 2；先检查 option 编码中的方向，再抽取 bits 16..28 为编码长度。get 要求传入 `*size_t len` **精确等于**编码长度；set 在 wrapper 中把按值长度取址后，同样核对。下表是 binary 分支直接证据；level 2 和用户态 len 宽度转换见 HAL 研究。

| option | 方向／输入 | 驱动动作与确切分支 |
| --- | --- | --- |
| `0x80047301` | set；int32，4 字节 | `0xfffffff00934380c` 起；非零规范化为 bool，保存 `this+0xf3`，日志 CRC enabled/disabled |
| `0x80047302` | set；int32，4 字节 | `0xfffffff009343c7c` 起；非零转 bool，保存 `this+0xf4`，日志 On demand read |
| `0x40407303` | get；输入容量必须 64 | `0xfffffff009343bd0` 起；调用 `0xfffffff00933ead0` 读取错误 TLV，实际输出长度回写；可小于 64 |
| `0x80047304` | set；int32，4 字节 | `0xfffffff00934396c` 起；低 8 位传 clear helper `0xfffffff009342238` |

错误方向、错误长度与未知 option 有独立失败路径；bad argument 的 IOReturn 为 `0xe00002c2`，未知 option 路径为 `0xe00002c7`，再经上述 mapper 转 errno。不要用“一律成功”实现未支持的 command，也不要把接收缓冲容量误作固定返回 64 字节。

CRC 与 OnDemand 是运行状态：CRC flag 在接收长度计算路径 `0xfffffff0093405e8` 使用；OnDemand 在实际读取路径 `0xfffffff009340ec4` 使用。其完整 NFCC／固件模式分支尚未全部还原，不能承诺在所有模式简单附加或删除固定两字节即可。

## 错误 TLV、通知和副作用

error helper `0xfffffff00933ead0` 从 provider `this+0x90` 的 vtable `+0x598` 读 SPMI register 4、5、6、7、8，各一字节；每次读成功才追加一个 TLV。可用缓冲不足 15 字节时失败并报告所需长度 15。socket get 的外层先要求 64，故最小兼容实现应保留这两层规则的区别。

| TLV type | len | value 含义（对应实际日志） |
| --- | --- | --- |
| 4 | 1 | Error status 0 |
| 5 | 1 | Error status 1 |
| 6 | 1 | Parity status 0 |
| 7 | 1 | Parity status 1 |
| 8 | 1 | Parity status 2 |

追加证据在 `0xfffffff00933f020/f278/f4d4/f730/f990`：LE halfword `0x0104..0x0108` 后跟一字节，成功全读最多 15 字节；部分寄存器失败可形成较短返回。各 value 的 bit 意义及具体控制器错误映射尚未闭环，不能臆造枚举。

clear helper `0xfffffff009342238` 通过 provider vtable `+0x590` 向 SPMI register 9 写一字节 mask。这是硬件状态写入语义，不能称为只读查询。helper 的 clear 参数 false 时不自动清除；socket get 传 false。但是 HAL 的 QuerySPMIError 外层在 get 后另发 clear option，因此**运行 HAL QuerySPMIError 不等于只读**。本轮没有执行它或任何原生初始化。

独立错误中断处理入口是 SPMI vtable `+0x570 → 0xfffffff00933e724`（日志 `_spmiErrorInterruptHandler`）：建立清零的 64 字节缓冲，查询错误（初始容量 63、clear=false），经 `this vtable+0x430` 发消息 `0xe3ff8001`，参数长度 `min(outlen+1,16)`。因此正常五项后有一个零终止字节。HAL 的 IOGeneralInterest 回调正按该消息读 byte type／byte length 的 TLV；这是 IOKit interest 通道，不能用 socket payload 冒充。

## 双向数据及背压

send 回调把 mbuf chain 交 gated helper，再进入 `0xfffffff009341b44`：逐 mbuf 取数据地址和长度，调用 `0xfffffff00933e050` 写数据；出错停止后续发送；结束释放原 mbuf chain。公开 KPI 也规定 ctl_send 回调拥有释放 mbuf 的职责。完整发送函数参数／SPMI 分片协议尚未恢复；现有证据不足以把一次 send、一个 mbuf 或一次 read 等同于一条 APDU／一条 NCI 消息。

接收链最终到 `0xfffffff0093418a4`，以 `this+0x118`、`this+0x120`、`this+0x108` mbuf chain、flags=0 调用 `0xfffffff00ab8b268`，形状及所有权符合 ctl_enqueuembuf。成功可交给 socket 接收队列；55（ENOBUFS）时调用 `0xfffffff00ab8bd24` 查询剩余可排队空间，必要时切分 chain、部分提交并保留余量。其他失败与余量不足走独立错误／保留路径，不能只把宿主写入成功当作 guest 已收到。

接收中断包括 `_rxInterruptHandler`（SPMI vtable `+0x560 → 0xfffffff00933fb64`）及 `_rxMbufInterruptHandler`（`+0x568 → 0xfffffff009340b94`）；其 socket-client 检查、无客户端丢弃、排队失败保留／丢弃由状态决定。原实现有实际 mbuf／长度／header 模式和 CRC 处理，尚未把所有状态迁移完整恢复。

## 最小兼容前端与未闭环项

可以从物理 SPMI／AOP 下方提升实现边界，但对原 HAL 至少还要提供：

1. `AppleStockholmSPMI` 服务及真实 `stockholm-spmi-data-socket` 属性，注册 primary stream 名称；正确的动态 ID／unit、单客户端、断开清理与 gate 串行语义。
2. 双向数据、partial read／write、背压、取消／断连、缓冲所有权及错误传播；明确恢复固件数据模式、长度与 CRC 责任边界。
3. 四个 options 的方向、精确输入长度、状态和查询／清除副作用；输出合法实际 TLV，不能把“全零硬件永远正常”当作已支持。
4. IOKit interest 的 `0xe3ff8001` 异步错误通知及零终止；控制 UserClient／reset／power 接口由配套 HAL／驱动研究列出。
5. 真正的 NFCC 初始化、厂商命令与 SE 枚举后端。VSOCK 只可作自定义桥接载体；宿主 APDU round-trip 不能证明本契约或原生初始化兼容。

尚未完成：完整 errno 转换表、HAL 全部读写调用的帧／超时语义、NFCC 模式与 CRC 算法、错误寄存器 bit 定义、所有电源／wake 分支及 guest 驱动加载路径。本文足以给未来独立宿主模型制定接口测试，未证明二进制移植可用，也没有生成 guest 实现。

证据摘录和静态常量核验保存在 `.build/validation/stockholm-interface-20261023/kernel-control/`：`contract.json`、registration／callbacks／options／gated／rx_enqueue／tx／error_tlv／error_notification／error_clear.txt。只运行 ipsw 只读反汇编和 Ruby 本地读取；scratch 目录 0700、文件 0600。没有 App、服务器或挂载需要清理。
