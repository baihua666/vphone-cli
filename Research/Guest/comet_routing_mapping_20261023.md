# 23G90 Comet：初始化 routing／mapping 的实际命令与状态

2026-10-23，仅离线读取现有同版二进制和小段证据；未执行库／VM／HAL／SE API，未启动服务器、修改系统、绕过门槛或绑卡。

**这里的 routing／mapping 是控制器静态配置，不要求实际 RF 发现或发射；但仍有真实能力检查、命令和响应。** 零 RF-interface count 会被 mapping 的同步 validator 拒绝；routing table 容量不足也会在发包前拒绝。Lib 的 mapping process 虽固定返回0，常规错误路径会绕开它而终结序列，并非允许忽略响应或吞掉失败。

## 证据和线上编码

对象：`libNFC_Comet.dylib` UUID `AAD82B14-9985-3582-9A57-22047E668A31`，Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；`__text` SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。地址均为未滑动用户态 VA，仅供本版研究；函数名由日志／function-start 恢复。未使用旧 otool 外部 stub 的错误标签推断导入。

父任务已逐字节证明原 DSC 六个 const/data/authstubs 区段与重建 Mach-O 相同，结果在 `.build/validation/comet-config-20261023/raw/section-comparison.json`。本轮不再提取 DSC。

发送沿用[厂商初始化研究](comet_vendor_initialization_20261023.md)已恢复链：descriptor `{type:u32@0,GID:u32@4,OID:u32@8,payloadPtr@10,payloadLen:u32@18}`，type1 → CoreIfTxRx `0x2a2f0a880` → command mux2 → CoreBuildCmdPkt `0x2a2f0cc94`，线上头为 `[20|GID, OID&3f, payloadLen]`。以下十六进制包均不含按既有状态追加的尾 CRC；CRC 不改变 NCI length 字节。

公开 NCI 名称只以 [NXP 固定版本 nci_defs.h](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)交叉核对：RF_DISCOVER_MAP OID0、RF_SET_LISTEN_MODE_ROUTING OID1；routing tag 0/1/2 对应 technology/protocol/AID。下面的实际值、条件及 Apple 私有字段均取当前 Comet，未以 Android 实现替代。

## Lib 初始化的调用次序与跳步

原指针表中的连续四项如下；中间没有 RF_DISCOVER／RF 激活命令。

| 表项 VA | 函数 VA | 条件／作用 |
| --- | --- | --- |
| `2b17bc780` | `2a2f55700` SetLsntModeRtng | 前一状态0且 Lib `+c84` 为0或2时构造四条 routing；其它值跳过 |
| `2b17bc788` | `2a2f558a4` SetLstnModeRtngProcess | 原样返回传入状态 |
| `2b17bc790` | `2a2f0ef1c` mapping 初始化函数 | 仅 Lib `+c84==0` 才提交两条 mapping；否则返回0 |
| `2b17bc798` | `2a2f5590c` InitSetMappingProcess | 不读取传入状态，固定返回0 |

`SetLsntModeRtng` 在前一状态非0时不发包；`c84==1` 将该状态转为0，其它 c84 保留错误。这里保留 c84 的原数值条件，未把它自行命名为某款硬件。

另一路 `RfDiscMapping` `0x2a2fa1e74` 先检查 Lib `ba9/baa/bb0` 是否至少一项为1，再调用 `0xef1c`；否则直接跳过。这是另一调用场景的附加条件，不能套到表项 `bc790` 的直接调用上。`SetProtoColToRfInterFaceMapping` `0xec74` 还先把 Lib `+5c1` 传入 `0x2034`，再调用同一 mapping 初始化函数。

## Routing：四条默认 protocol TLV

`SetLsntModeRtng` `0x2a2f55700–558a4` 清零内部数组，在 `557e4–55834` 直接写下列四条，每条内部占 `0x20` 字节：type:u32@0、route:u8@4、power:u8@8、protocol:u32@c。

| 顺序 | type | route | power | protocol | 实际编码的 TLV |
| --- | --- | --- | --- | --- | --- |
| 0 | 1 | `00` | `01` | `05` | `01 03 00 01 05` |
| 1 | 1 | `c0` | `01` | `04` | `01 03 c0 01 04` |
| 2 | 1 | `02` | `01` | `04` | `01 03 02 01 04` |
| 3 | 1 | `00` | `01` | `04` | `01 03 00 01 04` |

公开协议名中 04 为 ISO_DEP、05 为 NFC_DEP，power01 为 switched-on。**这些 route 字节是静态表中的目的值，不能证明同号 NFCEE 已被枚举、存在有效 eSE，或具备支付身份。** 这里没有 AID／卡片信息。

`VerifyRtngTableConfig` `0x2a2fb6fd8` → `ValidateSetRtngParams` `0xb3338` 计算 TLV 总大小；若大于 NCI context `+e:u16` 的 max-routing-table-size，直接返回内部 `0x8b`。这四条合计20字节，因此要求该容量至少20。

之后 `GetFeatures` `0xb7180` → `VerifySupportedRouting` `0xb3a08` 验证能力：features对象 `+4` bit0/1/2 分别控制 AID/protocol/technology routing；请求 power bit1/2 还分别要求 features `+8` bit0/1。当前四条需要 protocol-routing 能力，未请求 switched-off／battery-off routing。通过后保存 count 到 NCI `+382`、entry pointer 到 `+1228`；失败不进入发送。

`SetRtngCmdHandler` `0x2a2fb3614` 按 max-control-payload（NCI `+10:u8`）分批选择条目，分配 `sum(TLV)+2` 字节，`BuildSetLstnRtngCmdPayload` `0xb38c8` 输出 `[more,count,TLVs...]`；并保存 more 到 `+380`、推进 cursor `+381`、把 more 写回 Lib `+180`。不能把所有 routing 表都假定为单包。

若实际协商容量允许四条同包，其请求是 **GID1／OID1，payload22字节**：

```text
21 01 16 00 04
01 03 00 01 05
01 03 c0 01 04
01 03 02 01 04
01 03 00 01 04
```

通用 serializer 的另外两类并未用于这次默认表：technology `0xb3bd8` 为 `[00,03,route,power&7,technology]`；protocol `0xb3c9c` 为 `[01,03,route,power&7,protocol]`；AID `0xb3d60` 为 `[02,AIDlen+2,route,power&7,AID...]`，内部 AID 位于 entry+c、长度位于 entry+1c。实际 RF CRC、APDU 和 SE 身份均不属于这些字段。

发送 `SetRtngConfig` `0x2a2fb1ab4` descriptor 为 `{1,1,1}`，payload来自 NCI `+370/+378`，timeout `0x7d0`。sequence `0x2b17bf3e8` 是 send → `ProcessCommonNciRsp1` `0x1e920` → `CompleteSetRtngConfig` `0xb1ba8`。

成功 RSP 应为 `41 01 01 00`：parser要求前置状态成功、payload非NULL、长度精确1且status0；否则返回错误。completion释放 `+370` buffer并清长度；more为0时清 cursor/count（`+381`的u16）和 `+390`的u16，再按原状态回调 `0xe6e8`。Lib `SetLstnModeRtngProcess` 保留状态，不把失败改成成功。

分批 helper `0xb37a4` 的比较是 `maxPayload > accumulatedTLV` 才收入，另在 builder 加2字节头，且零条时有选一条的回退；不能仅据这个比较声称任意边界容量均正确。上面的22字节同包实例需要同时满足选择分支及下层包长验证；没有修改原算法或以异常容量缩减配置。

## Mapping：两条三元组，不是 TLV

初始化函数 `0x2a2f0ef1c–efcc` 在 `c84==0` 时构造两个12字节内部 entry：protocol:u32@0、mode:u8@4、interface:u32@8。常量 VA `0x2a2fc3708` 的精确8字节为 `{u32 2,u32 80}`，分别填第0条 interface、第1条 protocol；不是两条 descriptor。

| 顺序 | protocol | mode | interface | 线上三元组 |
| --- | --- | --- | --- | --- |
| 0 | `04` | `03` | `02` | `04 03 02` |
| 1 | `80` | `01` | `80` | `80 01 80` |

`ConfigMapping` `0x2a2f0ed0c` 需要非NULL context／entries／callback及count非0；经过 validator 后分配 `3*count+1` 字节。`BuildDiscMapCmdPayload` `0xf434` 写count，然后每条写 `protocol:u8, mode&3:u8, interface:u8`。私有80的物理／SE含义没有在这条构造路径中给出，不按编号猜测。

实际请求 **GID1／OID0，payload7字节**：`21 00 07 02 04 03 02 80 01 80`。发送 `ProtoIfMap` `0xf5c8` 的 descriptor 为 `{1,1,0}`，timeout `0x7d0`；sequence `0x2b17bf388` 为 send → `ProtoIfMapRsp` `0xf6b8` → `CompleteProtoIfMap` `0xf7a8`。

`ValidateDiscMapParams` `0xefcc` 调用 protocol／mode／interface validators；mode要求低两位非0，builder只保留低两位。`VerifySupportedRfIntfs` `0xf34c` 首先读取 NCI `+4:u8` 的 supported RF-interface count：0会记录“NFCC does not supported any RF interface”，返回ff；`ConfigMapping`在 `ed8c→eed0` 同步返回ff，不分配／发包。非0路径中的 CheckRfIntfs 循环只观察到日志调用，没有逐项比较所请求 interface 是否属于 advertised list，不能把它描述为完整成员校验。

因此 CORE_INIT 可被其独立 parser 接受的 n=0，**不等于此 mapping 操作可以执行成功**。本分支同步返回ff；Lib sequence 的常规处理会将它送至末项 completion，未进入 mapping process。此结论依赖实际命中 `c84==0` 分支，不能泛化成所有模式的 LoadStack 都必失败。

`ProtoIfMapRsp` `0xf6b8` 清 NCI `+19c1`，要求 payload非NULL、长度精确1且第0字节status0；成功包为 `41 00 01 00`。非零status或坏长度返回ff；明确非零status且 `+19c0==1` 时额外置 `+19c1=1`。`CompleteProtoIfMap` `0xf7a8` 无论传入状态先写 `+ea0=4`，释放／清空 `+370/+378`，再把原状态送 `0xe6e8` 回调。

**Lib `InitSetMappingProcess` `0x5590c–55968` 本身完全不读传入状态，固定返回0，但常规非零错误不经过这个 process。** 父任务保存的实际调用链已交叉核对：CompleteProtoIfMap → Notify `0xe6e8`（`e768–774`保留status）→ InternalSequence `0xe7d8`（常规 `e8fc–e908`保留status）→ SeqHandler `0x8590`。

SeqHandler 的 `8770–8780` 将普通非零status直接送 `88f8`，令idx=count，再经 `89f8→8614→8b84` 调用末项 completion（`8bb4`仍传原status）；仅status0才可进入前一项process调用点 `8a78`。当前step同步非零返回也从 `8acc` 走终结链。因此 mapping RSP非零／坏长度、或 n=0 导致同步ff，都不能靠这个固定0 process 转成功。`0f/24`、send-busy重试及 discovery drop有专门分支，不属于本文初始化ff错误。证据在同轮 `integration/lib-sequence-status-propagation.txt` 和 `integration/nci-to-lib-sequence-callback.txt`。

## 无RF模型的职责与本轮边界

兼容前端负责收发 NCI／CRC、控制面与超时；宿主控制器模型负责 routing表、mapping表、实际 advertised capacities／features、分批more语义和真实响应／拒绝。可以没有 RF 发射器及 polling循环，但不应凭空把接口数、routing能力或目的NFCEE伪装成已实现。配置写入被接受也不能证明目标 SE 可工作。

函数名 `StaticListenModeRouting` `0x2a2f5bb28` 容易误导：其 sequence `0x2b17bc570` 实际是 SetStandbyMode → disable ESE/UICC/SE2 → FlushSramData → staticFeatureCfgComplete／VerifySEStatus，不是本文 `21 01` 的第二个别名。该后续供电／枚举链由配套研究恢复，不能省略后便声称完整生命周期通过。

尚未证明：实际实例选择哪组 c84／产品分类；route c0/02 对应实体及可用性；私有 mapping80 的完整数据通道；分批routing所有边界和读回一致性；实际RF／NFCEE事件。没有运行原生LoadStack，也没有制造成功trace。

证据位于 Git忽略目录 `.build/validation/comet-nfcee-20261023/routing/`：定向反汇编、函数索引及纯算法重组的 `init-wire-shapes.json`。数学重组只检查长度／结构，不是控制器执行证据。目录0700、文件0600；只新增本研究报告，未改产品、补丁、系统或其它报告。

## 窄补：staticFeature sequence 的 FlushSramData

`0x2b17bc5b0/5b8` 对应 Lib `FlushSramData` `0x2a2f1131c`／`FlushSramDataProcess` `0x2a2f11a68`。**此步可以发真实私有 NCI 命令，并非函数名所暗示的单纯清 host 缓存。**

- 入口 `1134c–11354` 无条件先调 `EnableDisable_SyntaxErrRetry` `0x2a2f02034`，参数0；后者写 NCI `+19c0=0,+19c1=0`。这是本地状态改变，不发 NCI。
- `11358–11378` 检查 Lib `ba9/baa/bb0`：任一字节==1才进 `FlushSramToFlash` `0x2a2f113d0`；全部不为1则返回0、不提交flush命令。没有新增c84或SE存在性的选择条件，也未修改这些分类。
- NCI入口需要非NULL context及callback；sequence `0x2b17bf308` 是 `FlushDataCmd` `0x11568` → `FlushDataRsp` `0x11890` → `ProcessCommonNciCompleteSeq1` `0x119f4`。仅发送返回pending `0xd`时保存callback=`0xe7d8`与Lib context，失败保留返回状态。
- `FlushDataCmd` 在 `115bc–115d4` 加载 const `0x2a2fc3550={1,15}`、OID=`21`、payload=NULL／len0；经已恢复encoder得到 **`2f 21 00`**，timeout `0x7d0`。不能将它误写成SET_CONFIG、RF命令或内部ioctl编号。
- RSP对应 `4f 21 01 status`。`FlushDataRsp` 保留非零前置status；前置成功时要求payload长度精确1。线上status `00→内部0`，`01→93`，`09→1`；其余一般为ff，坏长度也为ff。
- **例外：线上status `06`（日志明确“Semantic error”）在 `11970→119a4→119c4` 被原代码视为内部0。** 因而 `4f 21 01 06` 也被此parser接受；不能把它按通用status表误判为失败，更不能反过来用该接受路径声称数据已真实持久化。
- completion `0x119f4` 把原状态传 `Notify`；Lib process `0x11a68` 原样返回状态，不另置“已刷写”标志或清一片SRAM。本轮这些函数内未见controller数据内容／地址／长度参数，实际flash持久化语义与数据范围仍需固件侧证据。

故最小命令清单须保留这项原选择条件：未命中时只有本地syntax-retry状态变化；命中时则是控制器私有flush操作及其特殊响应规则。上述仅恢复契约，未运行flush、写任何guest／SE／flash或扩展HCI分析。对应定向函数片段和 `flush-wire-shape.json` 保存在同一routing证据目录。
