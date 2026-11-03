# Stockholm SPMI 数据帧与 CRC 责任边界

2026-10-23；仅离线恢复 iPhone17,3 / iOS 26.6.2 / 23G90 实体内核中的 AppleStockholmControl 366.9.1；没有启动／挂载 VM、调用 HAL、改系统、加载驱动、绕过门槛或绑卡。

**在已恢复的 SPMI socket 数据路径中，CRC 开关控制 NCI 接收额外读取两字节；没有发现这些函数生成、校验或剥离 CRC。** DNLD 模式无条件额外读取两字节。算法及生成／校验已在配套用户态 Comet 分析中恢复，不能由驱动 option 名字推断多项式。

配套：[socket 契约](stockholm_kernel_control_contract_20261023.md)、[导入／vtable](stockholm_driver_imports_vtables_20261023.md)、[移植边界与 donor 身份](stockholm_driver_portability_20261023.md)。本文 VA 均是 donor 未滑动地址，不适用于 target 补丁／调用。

并行 [PN548 用户态帧／CRC 恢复](pn548_user_frames_crc_20261023.md) 已在 Comet 路径定位 TX append、RX 验长前减 2 及尾部 CRC 校验。这与本报告“内核原样保留尾部”相互支持；具体算法、覆盖范围与向量以该报告的用户态证据为准，不能推广为所有控制器分支相同。

## 数据路径与状态

| 功能 | VA／字段 | 恢复出的职责 |
| --- | --- | --- |
| socket TX chain | `0xfffffff009341b44` | 逐 mbuf 取 data／len，调用 raw TX；失败终止，释放原 chain |
| `_txSPMIData` | `0xfffffff00933e050` | 对 provider 的 `+0x590` 写接口传现有 bytes／length；地址 `0x1000`、末参 `0xe` |
| raw `_rxSPMIData` | `0xfffffff00933e3d8` | 对 provider `+0x588` 读接口传现有 buffer／length；地址 `0x80`、末参 `0xe` |
| `_rxInterruptHandler` | `0xfffffff00933fb64` | 根据 socket-client／电源等状态触发实际数据读取；另含 secondary notification 分支 |
| `_dataReadMbuf` | `0xfffffff0093401d0` | 分两次读 header／payload，解释 DNLD／NCI 长度，扩展 mbuf，交付数据 |
| mbuf `_rxSPMIData` | `0xfffffff0093413ac` | 按各 mbuf 剩余容量附加读取，更新长度，容量不足／读失败返回错误 |
| `_rxMbufInterruptHandler` | `0xfffffff009340b94` | socket-client 时调用 `_dataPushMbuf`，用于继续排出积压；不是另一种 NCI 帧格式 |
| `_dataPushMbuf` | `0xfffffff009340d70` | 推入 socket、处理背压／积压／无客户端分支 |
| `_dataMode` | `this+0xd4`，u32 | 0=DNLD；1=NCI；其他值进入错误模式路径 |
| `_pendingSPMIData` | `this+0xd8`，bit 0 | 接收 IRQ 置位；读取完成清零 |
| socket-client | `this+0xd9`，bit 0 | 控制是否进入 socket 数据处理路径 |
| powered／CRC／OnDemand | `this+0xf2 / +0xf3 / +0xf4`，bool | 分别控制总线读写可用、NCI 额外读长、积压保留策略 |
| NFCC model | `this+0xe0`，u32 | 影响 DNLD 长度高位 mask；实际 D47 属性 nfccModel=211（0xd3） |

关键分支：`0xfffffff00933fc3c–fc50` 先检查 `+0xd9`，置 `+0xd8=1` 再调用 `_dataReadMbuf`；`0xfffffff009340bb0–c58` 的 mbuf IRQ 同样检查 socket-client，但调用的是 `_dataPushMbuf`。`_freeMbufCluster` 在 `0xfffffff009341318–1398` 检查积压 chain／interrupt source，并触发后者，使释放缓冲后可继续排队。

## 帧头、长度和 CRC flag

`_dataReadMbuf` 先分配通常 0x800 字节 mbuf，按模式读 header：`0xfffffff0093401f4–0200` 令 header 长度为 `mode==0 ? 2 : 3`，`0xfffffff0093402c4` 读入它。随后只有 mode 0／1 分支解释长度；其他值记录 wrong data mode 并走失败清理。

| 模式 | Header H | 从 header 得到的 payload 长度 P | 第二次读取 R | 总线合计读取 H+R |
| --- | --- | --- | --- | --- |
| DNLD，model 0xd1／d2／d3／0x60 | 2 | `((h[0] & 0x1f) << 8) \| h[1]` | `P+2`，与 CRC flag 无关 | `2+P+2` |
| DNLD，其他 model 分支 | 2 | `((h[0] & 0x03) << 8) \| h[1]` | `P+2` | `2+P+2` |
| NCI，CRC flag false | 3 | `h[2]` | `P` | `3+P` |
| NCI，CRC flag true | 3 | `h[2]` | `P+2` | `3+P+2` |

证据：mode 分派 `0xfffffff0093404f8–0508`；model 分支 `0xfffffff009340530–0544`；5-bit 高位 `0xfffffff00934057c–0588`；其他 model 的 2-bit 高位 `0xfffffff009340b08–b10`；NCI 取第 3 字节 `0xfffffff0093405b4–05e4`；是否加 2 的唯一 CRC 判定 `0xfffffff0093405e8–05fc`。NCI 的 P=0 且 CRC=false 时跳过第二次总线读取；并非无法接收零 payload 消息。

以下仅为离线公式复算例，不是伪造的控制器响应或运行测试：NCI header `40 00 01` 在 CRC=false 时总线读 4 字节，true 时读 6；DNLD header `00 01` 总线读 5 字节。收到的消息内容、opcode 和状态是否有效，属于 PN548／NFCC 协议层。

在 `0xfffffff009340704` 算出 H+R；若初始容量不足，则追加分配 chain（`0xfffffff009340708–0854`）；`0xfffffff00934085c–0868` 按 R 继续读取。chain helper `0xfffffff009341548–0598` 用 data+已有长度作为目的地址，按可用空间读取后增加各 `m_len`；这里没有跳过头、从尾部取 CRC 比对或缩短 `m_len` 两字节的分支。

## CRC 在这里没有做什么

1. **TX 不生成 CRC。** `_txSPMIData` 把 socket 提供的指针／长度原样传给 provider 写接口；首次失败时等待 `this+0xdc` 指定间隔，再以同一指针／长度重试一次（`0xfffffff00933e114–0190`）。没有按 `_dataMode` 或 `+0xf3` 构建尾部，也没有 CRC 算法调用／循环。下层 provider／控制器是否另有硬件校验不由此排除。
2. **RX 在这里不验证 CRC。** raw RX 只做 powered 检查和 provider 读取；mbuf helper 只搬运和记录长度。上层 `_dataReadMbuf` 对 CRC 的直接使用是多读 2 字节，没有检查这两字节是否匹配某计算值。SPMI 总线 parity／error register 与 NFCC 帧 CRC 是不同层，不能混用。
3. **没有恢复到 CRC 剥离。** 已追踪 header→chain→socket enqueue 的正常路径，没有看到删除末两字节或将 data 指针移过 header。应按包含原始 header／额外尾部的链解释，再由用户态协议恢复交叉验证；不能只凭额外读长就断言 CRC 在驱动里被消费。
4. **不推定算法。** 两字节长度本身不确定多项式、初始值、反射、覆盖范围或字节序。没有补写通用 CRC-16 作为“兼容实现”。

CRC 状态不是只靠 socket option 生命周期：`0xfffffff00933db84–db88` 更新 powered 标志同时清 `+0xf3`；follower-reset 路径在 `0xfffffff00933dd9c` 再清 CRC 标志。option `0x80047301` 才可重新置位。因此未来前端需要将 power／reset 和 CRC 状态一致处理；不能缓存一次 setsockopt 值直到进程退出。

## 下载模式与普通模式转换

`_setDownloadRequestGated` 位于 `0xfffffff0093420a4`：执行 `w8=w1 XOR 1` 后写入 `this+0xd4`。日志在 `0xfffffff009342134–216c` 将 0 标为 DNLD、非零标为 NCI。对正常 bool 参数，download=true→DNLD、false→NCI。这里改变的是接收解析模式，不会替上层生成固件命令或选择固件映像。

DNLD 的附加 2 字节不受 CRC flag 关闭影响；普通 NCI 才由该开关决定。因此“关闭 CRC option”不能把下载响应变成只有两字节头+payload。接收解析由当前模式决定，切换时机必须与控制 UserClient／PN548 状态机一致。

## mbuf 记账的边界

有一处不能忽略但也不能直接定性为截断：完整读取后，`0xfffffff009340aa8–aab0` 对新 chain 调用 `0xfffffff00abe092c`，传的是 R；已有积压时 `0xfffffff009340a98–a9c` 也按 R 增加 packet-header 长度。各 mbuf 的 `m_len` 则由 helper 累计 H+R。

本轮定向反汇编 donor kernel `0xfffffff00abe090c–0954`，确认 `+092c` 设置 packet-header 长度、`+0944` 相加；其结构与 [Apple kpi_mbuf.c](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kpi_mbuf.c) 的相应实现一致。公开 [ctl_enqueuembuf](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_control.c) 用 packet-header 长度作容量判断，再送入 socket；[sbcompress](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_socket2.c#L1652) 按各 `m_len` 追加数据。

所以 packet-header 长度值本身不能证明 header／CRC 从 stream 中消失。这里保留为静态记账观察，尚未逐指令恢复 donor 整条 socket 公共实现，也没有运行捕获确认边界；不据此修改内核或宣布原驱动存在数据截断 bug。

## 对无 RF 最小闭环的影响

| 候选边界 | 仍需 guest 前端负责 | 需协议后端／上层负责 |
| --- | --- | --- |
| 复用实体 Stockholm 并替换 provider | 真实 provider 读写 ABI、地址／中断、power、mode、CRC flag、mbuf／socket背压 | 在原总线契约下提供合法 DNLD／NCI header、payload、应有尾部及异步时序 |
| 自写 HAL 兼容前端，桥接宿主 | UserClient 控制与 mode 同步、四个 options、动态 socket、字节流和错误／取消；明确桥接发送完整帧还是流片段 | NFCC reset／初始化及合法 NCI／厂商响应；需要 DNLD 时还要相应下载协议与 CRC，不能只提供 APDU |

后一方案可以不实现物理 0x80／0x1000 SPMI 寄存器，但不能把相关模式和帧责任都丢掉。最小实验不应先模拟 RF 发现／天线；应先解释 ordinary NCI reset／init 的双向帧，再核实是否可以合法跳过实际固件下载。是否允许跳过由 PN548 分支和状态决定，不是本报告中 CRC=false 就成立。

尚未闭环：厂商下载命令、provider flags=0xe 的完整含义、总线分片／部分成功语义、同版 socket实际帧捕获。CRC算法／覆盖及用户态生成方见配套报告，未扩大为所有未分析分支。没有构造 NFCC 成功响应、实现 guest 驱动或运行虚拟后端。

证据目录 `.build/validation/nfcc-protocol-20261023/kernel/` 保留 tx／rx_raw／irq／read_mbuf／read_chain／mbuf_irq／push_mbuf／mode／CRC reset 摘录及 static-frame-analysis.json。提取驱动 SHA-256 为 `d3807c5c2c7eb0a208121afc5021d4f870b2805652b2a06151f5c251e217f7f5`；scratch 0700／0600。只使用 ipsw／Ruby 和 MCP 读取 Apple XNU 官方源码，没有 Python、固件上传或远程反编译。
