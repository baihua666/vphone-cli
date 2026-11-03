# 23G90 PN548／Comet：用户态帧与 CRC

2026-10-23，离线恢复。本轮没有启动／挂载 VM、修改系统、绕过 NFProductIsVM、调用 HAL／SE API 或绑卡。宿主只执行二进制解析及纯算法向量，没有运行协议服务器或模拟设备。

## 结论

**普通 NCI 与 download 使用不同帧头，但当前实现复用同一个 CRC16 函数；CRC 的追加和校验在用户态 Comet，实体 Stockholm SPMI 驱动主要按模式决定接收长度并搬运字节。** 最小兼容前端不能再次追加／移除 CRC。宿主 NFCC 后端需要按协商状态消费／产生含 CRC 的完整帧，并实现命令、异步通知、逻辑连接及 credit 状态。

这可以收敛为不需要 RF 收发器的协议模型；不等于原生 nfcd 已通过初始化，更不等于存在支付 SE。初始化命令及 SE 会话依赖由配套研究记录展开。

## 版本、边界与证据

- 当前部署 PN548／HAL 来自 23G90，PN548 UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`，HAL UUID `B1924DF9-CE33-3CEC-98EB-AC9B11841E0B`，build 366.9.1；前轮已经核对部署与原版代码段。
- PN548 导入的 `phLibNfc_*` 实际来自 **libNFC_Comet.dylib**，因此帧处理不能只在 PN548 wrapper 或 HAL 寻找。本轮由同一 23G90 本地 IPSW 的 DSC 提取 Comet。
- Comet `__text` 为 `0x2a2f00930–0x2a2fc3210`，长度 `0xc28e0`。下列地址是该实体用户态库的未滑动分析 VA，不是 vphone 内核地址或补丁常量。
- 函数名主要由库内日志锚点结合函数边界／直接调用恢复；重建 Mach-O 的外部 stub 标签可能错误。本报告的 CRC 与 NCI 字段结论均来自库内指令／常量，不依赖这些错误标签。
- 原始定向证据在 `.build/validation/nfcc-protocol-20261023/user-frames/`：`comet-{symbols,strings,disass}.txt`、`crc-table.bin`、`crc-check.json`。HAL 使用前轮 `stockholm-interface-20261023/hal/hal-annotated-disass.txt`。

## 普通 NCI 帧

`phNciNfc_CoreUtilsUpdatePktInfo` (`0x2a2f04ac4`) 的实际校验是 `buffer[2] + 3 == length`，随后解释下表；若启用接收 CRC，调用方先从逻辑长度减去2，再进入这一校验。因此 header 的 payload length **不包含3字节头，也不包含尾CRC**。

| 字节 | 位域 | 23G90 实际证据 |
| --- | --- | --- |
| h0 | bits7:5 = MT | `0x2a2f04770–4784` 右移5；接收允许 MT=0(data)、2(response)、3(notification)，MT=1(command) 从 NFCC 发来会被丢弃 |
| h0 | bit4 = PBF | `phNciNfc_CoreRecvChkPbfAndUpdate` `0x2a2f0536c` 在 `0x2a2f05420` 检查 bit4；1进入分片累积，0进入结束／完整包流程 |
| h0 | bits3:0 | control 为 GID；data 为 connection ID。`0x2a2f04b44`、`0x2a2f04c18` 均取 mask0xf |
| h1 | control bits5:0 = OID | `0x2a2f04b8c` mask0x3f；GID当前接收集合为0、1、2、15（实际mask0x8007）且另有各组OID白名单 |
| h1 | data | 当前 data 构造路径先清3字节头，所见正常分支未赋其他字段；不能将此字节当APDU长度或自定义消息类型 |
| h2 | payload length，u8 | `0x2a2f04b20–4b2c`；payload从h3开始，单个帧表示范围0–255；实际允许长度还受 CORE_INIT／连接协商值限制 |
| 尾部 | 可选 CRC16，2字节 | 在3+payload后追加；由发送append、接收check状态分别控制，不是任何NCI包固定自带 |

发送 control：`phNciNfc_CoreBuildCmdPkt` (`0x2a2f0cc94`) 接受 GID0/1/2/15；`0x2a2f0ce0c–ce30` 组成 `h0=0x20|GID`、`h1=OID&0x3f`、`h2=payloadLen`，之后复制payload。长度大于已协商最大control payload时失败，日志明确指出不允许command segmentation，不能因PBF位存在就假设此库支持分片命令发送。

发送 data：`phNciMuxNfc_BuildDataPktNci` (`0x2a2f42cc0`) 使用 connection ID低4位，超过连接最大payload时置PBF并分片；`0x2a2f42fd8–43008` 写h2、复制payload并设长度为payload+3。逻辑连接credit不足时另走等待／超时分支，普通字节echo不满足这个协议。

接收分两阶段：`phNciNfc_CoreRecvNciHeaderCb` (`0x2a2f01a50`) 要求先读到精确3字节header，再请求 `h2+(checkCRC?2:0)` 字节；没有payload且未启CRC时可直接处理3字节包。`phNciNfc_CoreReqNciPkt` (`0x2a2f01c90`) 分别选择header／payload buffer，继续依赖异步TML完成。stream拆包／粘包不能直接当成一次read一帧。

## CRC 算法及覆盖范围

同版 `phNciNfc_CalcCrc16` (`0x2a2f03bc8`) 的参数为日志context、字节指针、长度；算法关键在 `0x2a2f03c0c–3c38`：

- 初值 `0xffff`；每字节以 `(crc>>8)^byte` 索引256项u16表；更新为 `(crc<<8)^table[index]`；返回低16位，无终值异或，无反射。
- 表地址 `0x2a2fc37c0`。本轮导出全部512字节，与poly `0x1021` 的非反射逐位生成表 **256项全部相等**，不是仅凭前两项命名CRC族。
- `phNciNfc_CoreUtilsAppendCrc` (`0x2a2f0d944`) 对传入的完整NCI header+payload计算；`rev16` 后 `strh`，产生**高字节在前**的2字节尾CRC。
- `phNciNfc_CoreUtilsVerifyCrc` (`0x2a2f0523c`) 对传入长度减2计算，再从最后2字节读取BE值比较；不相等返回 `0x22`。不是对包含CRC的全部帧计算固定residue。
- CRC失败在receive packet checker中转为错误通知／失败流程；不能由前端把错误帧修正后冒充NFCC原始输入。

宿主纯算法复核：ASCII `123456789` → `0x29b1`；任意示例header+payload `20 00 01 00` → 尾部 `80 bf`。这些仅验证算法和字节序，**不是捕获的控制器会话或原生栈通过证据**。

四个不同软件状态必须区分：

| 状态／函数 | 实际存储或行为 |
| --- | --- |
| `phNciNfc_UpdateCrcAppendFlag` `0x2a2fba014` | main context `+0x1850`；发送 `0x2a2f0d3e0–d3f8` 非零时计算并把write长度加2 |
| `phNciNfc_UpdateCrcChkFlag` `0x2a2fb9f78` | `+0x1851`；决定接收多读2字节、逻辑包长减2 |
| `phNciNfc_UpdateCrcSkpFlag` `0x2a2fba080` | `+0x1852`；值1暂跳过比较，但check状态仍决定是否接收／扣除尾2字节 |
| `phNciNfc_StoreReqCrcCfg` `0x2a2fba11c` | `+0x1853`；保存请求配置，不能视为上述3个flag的别名 |

接收核心 `0x2a2f04788–480c` 先按check flag把逻辑长度减2，校验NCI长度／字段，再在check非零且skip不为1时检查原帧最后2字节。**CRC的存在、是否验证、TX是否追加是分开的状态**。后端与用户态的切换时点需遵守CRC配置响应流程，不能开连接就永远强制on/off。

## Download／bootloader 帧

这条路径的2字节头不是NCI MT/GID/OID：一般为BE payload长度，payload首字节是下载命令／响应状态；尾部仍是BE CRC16。

`phDnldNfc_BuildHdllPkt` 的 `0x2a2fbeb80–bebc4` 对完整下载header+payload调用**同一** `0x2a2f03bc8`，先写CRC高字节再低字节。接收 `phDnldNfc_DnldValidateRxdPkt` (`0x2a2fbef00`) 内部的日志名 `DnldVldtCrcRcvd` 分支在 `0x2a2fbf000–bf040`：

1. 以总长度减2作为CRC覆盖范围，读取最后两字节的BE CRC。
2. CRC相等后，要求 `BE16(h0,h1) == totalLength-4`。
3. payload从offset2开始；所见更新响应路径另读取offset2状态。

下载接收有一个专门失败识别：若CRC不匹配但前4字节是 `60 00 02 a5`，记录 RESET NTF／NO UART message并返回 `0x84`，不是把这种NCI形态当成合法普通下载帧。不能向DNLD通道统一回普通NCI成功包。

实体driver的DNLD接收长度另按model取头高位mask0x1f或0x03，见[内核帧研究](stockholm_spmi_frame_crc_20261023.md)。这是总线收帧长度策略；上面所核对普通下载响应validator仍直接比较完整BE头，不能未经恢复就宣称所有flags位可原样交给该validator。eSE download／HCI multiplex还有单独入口，不能将普通固件download协议直接代替SE wired APDU协议。

作为独立参考，[AOSP所存NXP下载CRC源代码](https://android.googlesource.com/platform/system/nfc/+/30545c7bc987336854d040a9be2442b037da7e79/halimpl/pn54x/dnld/phDnldNfc_Utils.c)也使用同样table递推与代码初值ffff；其注释提到1d0f，不能取代实际代码。Apple实现的算法／尾序结论来自本轮二进制，而非从Android移植假定。RF链路CRC-A／CRC-B、闪存完整性section CRC与此传输尾CRC没有被证明是同一个契约。

## 前端与宿主后端的最小分工

| 层 | 必须承担 | 不应重复承担 |
| --- | --- | --- |
| 原PN548／Comet | command/data构造、NCI字段和长度验证、分片、用户态append/check CRC、连接及超时管理 | 保留现有库行为，本轮不替换或调用 |
| 兼容IOKit／kernel-control前端 | 控制状态、模式切换、socket options、stream字节保真与背压／断连、所需错误通知；保留带CRC尾字节 | 不再给Comet发出的帧追加CRC，不剥掉输入尾CRC，不虚构RF发现／真实SE身份 |
| 宿主NFCC协议后端 | 按当前NCI／DNLD模式解析；验证host方向CRC；生成相应response/notification及CRC；维护reset、CRC切换、厂商参数、逻辑连接、credit和NFCEE状态 | 无需为无RF用例实现模拟天线波形，但不能把正常初始化依赖的配置/能力命令一律忽略 |
| 后续自有测试SE | 在真实建立的非RF逻辑通道上处理自有测试applet APDU | APDU的9000或桌面JavaCard不代表Apple Pay可信SE／配对身份 |

可独立验收的最小协议模型边界是：3字节NCI与2字节DNLD拆帧、CRC模式转换及错误帧拒绝、reset/init对应响应与异步通知、NFCEE发现与连接/credit，再到自有测试APDU往返。是否能保持全程normal NCI、哪些DNLD／厂商查询无法删去，需合并初始化研究，不能仅从帧格式下结论。

本轮仅完成静态契约与CRC表／向量复核，未实现或运行上述模型。HAL ABI详见[前端总清单](stockholm_hal_frontend_contract_20261023.md)，内核搬运边界详见[SPMI帧与CRC](stockholm_spmi_frame_crc_20261023.md)。
