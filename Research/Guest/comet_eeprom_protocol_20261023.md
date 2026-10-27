# Comet 23G90 EEPROM 参数与初始化分支

2026-10-23；离线读取同版 `libNFC_Comet.dylib` 重建 Mach-O、完整反汇编与初始化表。没有加载／执行该库、调用 HAL、启动／挂载 VM、加载驱动、改系统／门槛、绑卡或运行后端。本文给出的帧是静态推导格式，不是设备响应抓包或可用模拟器。

## 结论

**GetEepromParams／SetEepromParams 使用 NCI CORE_GET_CONFIG／CORE_SET_CONFIG 的扩展参数 `A0 0F`，读写完整 64 字节值；不是传递物理 EEPROM 地址。** 初始化只把该值首 8 字节解释为 MW／FW 版本和配置标记。标记影响内部初始化 sequence 跳过，而公开 ValidateEepromSettings 是另一条更广的配置读取／修复／重读路径。

因此最小无 RF 后端也不能仅返回“EEPROM OK”：需要与实际 GET／SET 一致的参数状态、长度、结果与重读行为。静态代码不能证明该参数在真实 NFCC 的断电持久化范围，也不能把它叫作 eSE 个性化数据或物理写入计数器。

配套：[本轮命令与LoadStack关系](comet_no_rf_loadstack_commands_20261023.md)、[上一轮初始化与帧边界](nfcc_no_rf_minimum_protocol_20261023.md)、[用户态帧／CRC](pn548_user_frames_crc_20261023.md)。主要证据为 `.build/validation/nfcc-protocol-20261023/{comet,init,user-frames}/`；本轮摘录在 `.build/validation/comet-config-20261023/eeprom/`。Comet 重建库 SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。VA 是同版用户态未滑动地址。

## 请求如何落到真实 NCI 帧

| 环节 | 函数／VA | 关键证据 |
| --- | --- | --- |
| 请求读日志参数 | GetEepromParams `0x2a2f54f3c` | 清 `ctx+0xe18` 起 0x6e8 字节，置 config `+4` bit12、`+0x244` bit7 |
| 通用 GET | GetConfigRfParameters `0x2a2f136b8` | 调 GetRfParams，分配 count+ID 列表，再进入 GetConfigSequence |
| GET 参数编码 | GetRfParams `0x2a2f13914` | `0x2a2f13c90–13c9c` 写 LE halfword `0x0fa0`，形成 wire bytes `A0 0F`，参数数量加 1 |
| GET 数量前缀 | `0x2a2f13780–13798` | 首字节写参数数量，后面复制编码的 ID 列表 |
| GET NCI descriptor | GetConfig `0x2a2f1410c` | 常量 `0x2a2fc36a8` 为 u32 `[1,0]`，OID 单独写 3，进入 CoreIfTxRx `0x2a2f0a880` |
| 请求写日志参数 | SetEepromParams `0x2a2f555dc` | 同样 flags，构造 64 字节参数值，调用 SetConfigRfParameters `0x2a2f16cb4` |
| SET 参数编码 | BuildSetConfCmdPayload `0x2a2f17ca8` | `0x2a2f18564–1857c` 对 `+0x244` bit7 选 `paramID=0xa00f`、长度参数 0x41、value=config+0x264 |
| 扩展 TLV | TlvUtilsAddTlv `0x2a2f189ec` | high byte A0／A1 时输出 high-ID、low-ID、`arglen−1`，故 wire length=0x40，再复制 64 字节 |
| SET NCI descriptor | SetConfig `0x2a2f10c74` | 同一 `[1,0]` 常量，OID 单独写 2，进入 CoreIfTxRx／CoreBuildCmdPkt |

`[1,0]` 是 **MT／接口种类与 GID 的内部描述值**，不是 wire opcode 两字节。并行 vendor 研究核对 CoreIfTxRx 的 command 分支与 CoreBuildCmdPkt `0x2a2f0cc94`，得到 MT=command、GID=0；因此真实头为 GET `20 03`、SET `20 02`。先前邻近常量 `[3,1]` 的误读不应沿用。本轮直接按文件偏移 `0xc36a8` 复核原始 8 字节为 `01 00 00 00 00 00 00 00`。

仅当请求只选择这个参数时，静态推导的无 CRC 帧形状如下；上层 transport 开启 CRC 时另遵守用户态 CRC 契约。

| 方向 | 帧形状 | 长度解释 |
| --- | --- | --- |
| GET command | `20 03 03 01 A0 0F` | payload 3：count=1，扩展 ID 两字节 |
| GET 正常 response | `40 03 45 00 01 A0 0F 40 [64-byte value]` | payload 69：status、count、ID、len、value |
| SET command | `20 02 44 01 A0 0F 40 [64-byte value]` | payload 68：count、ID、len、value |
| SET 正常 response 形状 | `40 02 02 00 00` | status=0，failed-param count=0；不是实际抓包值 |

普通一次 API 可以包含多个配置参数，不能把所有 CORE_GET／SET_CONFIG 都写死成上表单项格式。`0xa00f` 是 TLV 参数标识，不是 EEPROM offset；代码没有向驱动传递本参数对应的实体存储地址。

## GET 响应的严格条件与内存字段

GetConfigRsp `0x2a2f14204` 的正常分支要求成功回调、非空响应、status=0；`0x2a2f14260–1426c` 将收到的参数数量与请求保存值比较，匹配后才进入 ProcessRfParams `0x2a2f1437c`。其他 status 有单独部分／错误处理，不能一律归成功。

ProcessRfParams 的 A0 0F 分支 `0x2a2f14ac8–14b10` 检查 low-ID=0x0f，**长度必须是 0x40**，才复制 64 字节到结果 struct `+0x264`，并置 struct `+4` bit12、`+0x244` bit7。GetEepromParamsProc `0x2a2f54ff4` 又检查这些结果 flags（`0x5503c` 与 `0x550d0`），否则报 Get EEPROM params failed／EEPROM params read failed。

随后 `0x2a2f550e8–550f8` 仅将 value 的首 8 字节复制到 `ctx+0xe10`，没有对字段做 endian 转换；当前 arm64e 小端布局如下。

| A0 0F value 偏移 | 宽度 | 上下文字段 | 直接日志／用途 |
| --- | --- | --- | --- |
| 0 | LE u16 | `ctx+0xe10` | wCurrMwVer，`0x2a2f5511c` 读取 |
| 2 | LE u16 | `ctx+0xe12` | wCurrFwVer，`0x2a2f5513c` 读取 |
| 4 | LE u32 | `ctx+0xe14` | bConfig，`0x2a2f5515c` 读取；名字虽带 b，实际读写 32 位 |
| 8..63 | 56 字节 | 留在 config struct | 此初始化路径没有解释其含义；不得发明 reserved／counter／密钥字段 |

注意 `+4` 和 `+0x244` 是宿主内存中的“字段存在／选择”掩码，不属于上述 64 字节 wire value；不能把这些 flags 追加到响应中。

## SET 值与标记分支

SetEepromParams 在 `0x2a2f5563c–55654` 构造首 8 字节：MW version 固定 `0x0435`，FW version 为 `ctx+0xbd4` 的低 16 位，bConfig=`0xc3c3a5a5`。`0x2a2f55658–55680` 先清 64 字节 value 区，再复制这 8 字节，所以本调用实际发送剩余 56 字节为零；不能误述为只写 8 字节或保留原尾部。

这给出 value 前缀 `35 04 [fw-low] [fw-high] A5 A5 C3 C3`，后接 56 个零。它是库构造的数据，不能据此选择任意 FW version 冒充真实硬件。`0x0435` 未解释为 iOS 产品版本或自行格式化成三段版本。

GetEepromParamsProc 在 `0x2a2f55194–5523c` 对 bConfig 分支：

| 读取的 bConfig | 本函数动作 |
| --- | --- |
| 0 | 日志 Firmware updated，置 `ctx+0xc83=1`，继续配置 |
| `0xa5a5c3c3` | 与 0 合流，置 `ctx+0xc83=1`，继续配置 |
| `0xc3c3a5a5` | 日志 Skipping set config，调用 SkipSequenceSeq，增量 5 |
| 其他值 | 日志 Unexpected MW Log Area Value still forcing MW config，正常返回，继续既定配置 |

此处**没有把读回 MW／FW version 与期望值比较**；它们在本函数只被记录。完整 MW／FW 兼容检查在别的初始化阶段，不能用这里的 marker 分支取代。

SkipSequenceSeq `0x2a2f2bd04` 只在当前 sequence 指针相同且索引+增量未越界时更新索引。初始化表 `0x2b17bc6c0` 的 `+0x90` 为 GetEepromParams／Proc，后接 InitSetConfig、SetEepromParams、SetLsntModeRtng 等；所以增量 5 是内部库 sequence 调度，不是绕过 VM 门槛、整个 LoadStack 或公开 EEPROM 验证。

`ctx+0xc83` 在 InitializeComplete／staticFeatureCfgComplete 的 PLL／XTAL 通知分支也被读取并最终清零；可确认它还影响初始化通知处理，不能把它命名成全局“EEPROM 已持久化”或“可以绑卡”标志。

## 与公开 ValidateEepromSettings 的区别

LoadStack 的 EEPROM 验证经 `phLibNfc_Mgt_ValidateEepromSettings (0x2a2f76628)` 进入状态机；它与上述日志区域读写不是同一函数。GetEepromSettings `0x2a2fa10a4` 构建更广的所需配置 flags，仍调用通用 GetConfigRfParameters；包括 poll／listen、system、discovery、SWP 和扩展配置。

GetEepromSettingsProc `0x2a2fa13d4` 将返回值与当前型号／配置分支期望比较：已匹配项清 selection bit，需修正项保留 selection bit并填期望值。所有组没有剩余 selection bits时才能跳过 SET；否则把待修正 struct 放 `ctx+0x1540`，由 SetEepromStngs `0x2a2fa1a70` 再走通用 CORE_SET_CONFIG。

关键重读环：`0x2a2fa19b4–19e8` 在仍需修正且 `ctx+0xcc9>=2` 时返回 0xff；SetEepromStngsProc `0x2a2fa1b70–1b8c` 递增 `+0xcc9`，以 RepeatSequenceSeq 增量 2 返回前面的配置读取步骤。这是**配置修复重试计数**，不是物理 EEPROM write counter。真实 write-counter 启用属于PN548 step5（A154）；step23是另一个standby策略，见主报告，不能混称。

因此后端若 SET 返回成功却不反映到后续 GET，公开验证仍可能重试耗尽；A0 0F marker 命中也没有证明这些更广配置符合当前型号要求。无 RF 不意味着无需返回 poll／listen 参数：库初始化可能验证这些静态配置，即使实验不执行 RF 发现。

### 公开验证实际选择的参数与期望值

以下 `c` 为 Lib context，`q` 为 GetEepromSettings 分配／响应解析的配置 struct。条件保留实际内存字段，尚未把型号分类字节命名为芯片型号：`M := u32(c+0xc84)∈{0,2}`；`P := c[ba9]、c[baa]、c[bb0]均不等于1`；`Z := 这三字节均为0`；`Q := P且c[ba8]!=1`。`0xa1110–131c` 是选择端，下表“期望”来自 Proc 的比较／修复端；**读取条件与比较条件并非总是相同**。

| ID | GET 选择条件与掩码 | 比较／修复期望；正常单值 SET wire value | 比较 VA |
| --- | --- | --- | --- |
| `28` | M；q+58 bit0 | q[5c]=1；`01` | `0x2a2fa143c–1460` |
| `32` | M；q+94 bit2 | `(q[9c]&7)==1`；修复为`(旧值&fc)|1`，序列化取低2位左移5，wire `20` | `0x2a2fa1498–14c8` |
| `5B` | M；q+17c bit3 | q[1e3]=0；`00` | `0x2a2fa14ec–1508` |
| `80`／`81` | M；q+220 bits2／3 | q[227]／q[228]各1；各`01` | `0x2a2fa1760–17a8` |
| `A0 19` | P；q+244 bit14 | P时u32(q+3a4)=2；`02` | `0x2a2fa1564–15a0` |
| `A0 D5` | P；q+244 bit15 | c[ba8]=1时u32(q+3a8)=10；c[ba8]=0且Z时=4；wire `0a`／`04`；其它组合未设期望 | `0x2a2fa15a4–15f4`、`0xa1a60` |
| `A0 02` | P；q+244 bit1 | P时q[24a]=1；`01` | `0x2a2fa15f8–1634` |
| `A0 04` | P；q+244 bit3 | 仅c[ba8]=1时q[24b]=0x0c；`0c`；其它组合清该选择位、不强制清零 | `0x2a2fa1638–165c` |
| `A0 07` | P；q+244 bit6 | P时u32(q+25c)=0且u32(q+260)=1；序列化为`q[25c]\|(q[260]<<1)`，wire `02` | `0x2a2fa1660–16a8` |
| `A0 37` | P；q+244 bit16 | 仅Z时q[3ac]=0xee；`ee` | `0x2a2fa16b0–16dc` |
| `A0 06` | Q；q+244 bit5 | c[ba8]!=1时q[259]=0；`00` | `0x2a2fa16e0–1724` |
| `A0 EC` | c[bb2]!=1；q+46c bit0 | q[492]=`u32(c+1e8)&1`；wire `00`／`01` | `0x2a2fa17e0–181c` |
| `A0 ED` | 无额外条件；q+46c bit2 | q[494]=`(u32(c+1e8)>>1)&1`；wire `00`／`01` | `0x2a2fa181c–184c` |
| `A0 A2` | c[ba8]=1；q+46c bit3 | 同条件q[495]=1；`01` | `0x2a2fa16e0–1710` |
| `A0 44` | M；q+580 bit4 | q[58d]=0；`00` | `0x2a2fa1888–18a8` |

ID闭环依据：GetRfParams `0x2a2f13914` 的普通ID分支 `0x13a54/13a9c/13acc/13b20/13c60`、system分支 `0x13e6c–13f14`、SWP分支 `0x13f18–13f78` 和 `A044` 分支 `0x13d60–13d78`。SET builder `0x2a2f17ca8` 在 `0x17ed4–17ef4` 对32做位编码；`0x185e4–1861c` 对A019／A0D5虽取u32字段地址，但扩展TLV helper argLen=2只复制低1字节。其它上述项同样wire value长度1；A044 helper为`0x2a2fb4850`。不能将q struct宽度当作wire长度。

GET response parser ProcessRfParams 对32要求普通TLV length=1（`0x1488c–148bc`），值`20`经ROR32右旋5得到1；其余编码可能映射为其它内存枚举。A019／A0D5在 `0x14b98–14bf4` 将扩展TLV value首字节零扩展写u32字段；SWP与A044在 `0x14d90–14ea4` 复制value首字节。这里恢复的是可匹配值，不代表这些解析分支对每个非规范length都同样严格拒绝；不能据此构造宽松后端协议。

Proc先在`0xa1544–1560`清q+244的bits1/2/3/5/6/14/15/16及q+46c bit3，再按上述条件重加需修复项；所以“GET读过”不代表必写回。反过来SWP检查即使未GET A0EC也可因当前期望与默认结果不同而重加bit0；后端须处理实际SET列表，不能只允许原GET ID集合。Listen还检查q[cc] bit0应为0（`0xa14cc–14e8`，对应ID50），但本GetSettings入口没有选择该项，不能把50列为此入口固定GET。

这16项ID（80／81分开计数）已具体化该公开入口直接构造的选择集合，**不是Comet全部配置清单，也不是目标实例必发的固定16项请求**。本入口未选择A00F或CRC参数A0BF；对应命令仍由其他初始化阶段管理。实际型号分类字段与模式的来源、目标所选请求顺序／分包和所有错误恢复未闭环，不能修改分类字段来缩减无RF实现。

## 持久化边界与最小验证职责

本轮可证明的是“库经 NCI 请求读／写配置参数并按结果调度”。这些函数没有直接文件写入或 EEPROM 物理地址操作；名字 EEPROM 不证明芯片对每个参数断电保存、写入原子性、flash wear、写计数或 rollback 行为。也未证明 SetEepromParams 成功回调之后立即重新读取该日志参数；后续新一轮初始化读取是另一个时点。

未来独立宿主模型最小职责是保存真实收到的参数值并按合法 GET 返回，支持扩展 ID／长度、多参数请求、失败与异步结果，完成配置修改→重读比较；磁盘保存／软复位／断电复位的保留策略必须另有证据和显式实验目标。不要把伪造固定“已配置 marker”作为跳过初始化的实现。

本轮不实现模型、不执行 GET／SET、不生成供原生栈消费的成功响应，也不声称 eSE 上电、NFCEE 枚举或 Wallet 可用。eSE power 验证仍是独立前置条件，A0 0F 不携带已证明的支付凭据或 SE identity。

## 复核与遗留

本轮 Ruby 静态断言 descriptor=`[1,0]`，保留原始 8 字节、函数摘录及 metadata.json；目录 0700、文件 0600。没有新增大 DSC 解包；复用现有同版重建库，没有远程反编译／固件上传／Python或产品代码改动。

未闭环：A0 0F 其余 56 字节真实语义、各型号全部参数合法值、实体存储地址／持久化与写计数、每条错误 status 的完整恢复策略、实际 hardware readback。所有成功帧形状仅由当前编解码路径推导，运行通过仍未验证。
