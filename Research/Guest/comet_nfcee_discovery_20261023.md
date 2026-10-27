# 23G90 Comet：SWP 配置、NFCEE discovery 与异步通知

2026-10-23，仅离线读现有提取物；未执行库／HAL／后端，未启动／挂载 VM，未修改系统、门槛或卡状态。研究按 research 技能使用一手字节与官方定义，不是运行成功证明。

## 结论与对象

**SWP 接口配置、discovery 命令响应、NFCEE 通知及 SE 初始化完成，是不同层次。** 当前代码会先读写私有配置，再发 NFCEE_DISCOVER；成功 RSP 只保存数量并注册通知，设备记录由随后 NTF 更新，后面还有模式、Session ID、HCI 及计时流程。即使某个原条件使 discovery 不发包，也不证明存在可用 SE。

对象为 23G90 IPSW 原版 `libNFC_Comet.dylib`，UUID `AAD82B14-9985-3582-9A57-22047E668A31`；重建 Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`，原 `__text` 已逐字核对。父任务还比较了原 DSC 六个保留 data／const／stub 段，均与重建产物相同，见 `comet-config-20261023/raw/section-comparison.json`。本轮未重新提取 DSC、未重新挂载实例核对 guest Comet。

VA 为未滑动用户态地址；私有方法名来自 function-start 区间及其日志。定向反汇编、精确 descriptor、序列索引保存在 `.build/validation/comet-nfcee-20261023/discovery/`（0700／文件0600）。复用 [厂商配置](comet_vendor_initialization_20261023.md)、[EEPROM／通用配置响应](comet_eeprom_protocol_20261023.md)、[帧／CRC](pn548_user_frames_crc_20261023.md)。

通过 MCP 核对 NXP 官方固定 commit [nci_defs.h](https://raw.githubusercontent.com/NXPNFCLinux/linux_libnfc-nci/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)：NFCEE管理GID2、DISCOVER OID0、action1／0、状态active0／inactive1／removed2；仅作为通用术语。下面 Apple 私有参数、内存字段与分支以当前指令为准。

## SWP 接口控制实际是 CORE_SET_CONFIG

令 `L` 为 Lib context、`C` 为临时 `0x6e8` 字节配置对象；`bb2` 是上轮已恢复的平台分类字节，不能把内部字段偏移当线上 opcode。

`phLibNfc_SwpIntfControl 0x2a2f9ee70` 清零 C，置 `u32(C+4)=0x2000`；`C[46c]=(L[bb2]==0 ? 5 : 4)`。在 `...9eee8–9eefc`，`C[492]=(L[bb2]==0) & u32(L+1e8)`（最终存byte），`C[494]=(u32(L+1e8)>>1)&1`，`C[493]=0`；随后调用 `SetConfigRfParameters 0x2a2f16cb4`。

序列化 `0x2a2f1878c–187f4` 用 `C[46c]` bits0／1／2选择 `A0 EC`／`A0 D4`／`A0 ED`，各helper argLen2，经扩展TLV encoder转为线上value长度1。**此调用未选择bit1，因此虽然写了C[493]=0，也没有发送A0D4。**

| 原分类条件 | 静态推导命令形状（不含CRC） |
| --- | --- |
| `L[bb2]==0` | `20 02 09 02 A0 EC 01 u A0 ED 01 e`；`u`为上述C[492]，`e`为C[494] |
| `L[bb2]!=0` | `20 02 05 01 A0 ED 01 e` |

通用 SetConfigRsp `0x2a2f10e7c` 解析 status 与失败参数列表；成功／错误约束见厂商配置报告。`SwpIntfControlProc 0x2a2f9ef7c` 本身只记录日志并返回0，不能据此把缺失或拒绝的底层RSP归成功。这里没有新的SWP专用vendor opcode；参数ID也不是物理引脚号或EEPROM地址。

## GetNfceeIntfCfg：读回状态怎样决定跳步

`GetNfceeIntfCfg 0x2a2f55968` 清 `L+e18` 配置对象；置 `C+4 bit13`、`C[46c] bit2`，且仅在 `L[bb2]==0`时置bit0。`GetRfParams 0x2a2f13cf0/13f18–13f54` 写出big-endian ID字节；CoreGetConfig descriptor为`{1,0}`／OID3。

| 条件 | 无CRC命令 |
| --- | --- |
| `bb2==0` | `20 03 05 02 A0 EC A0 ED` |
| `bb2!=0` | `20 03 03 01 A0 ED` |

GetConfigRsp `0x2a2f14204` 成功正常分支要求status0、返回count与保存的请求count相符，再交 `ProcessRfParams 0x2a2f1437c`。其 `...14d90–14e1c` 将A0EC／A0D4／A0ED的value首byte分别存入结果 `C[492/493/494]`，置 `C[46c]` bits0／1／2及`C+4 bit13`。这里没看到各项value长度严格等于1的本地检查；离线合法响应仍须满足TLV长度与总payload一致，不能复制短包读取行为。

`GetNfceeIntfCfgProc 0x2a2f55a34` 的状态保存：

| 位置／条件 | 保存或失败 |
| --- | --- |
| 初始化默认（`...55a7c–55a94`） | `L[16d]=(bb2==1 ? 2 : 3)`；`L[16e]=3`；`L[16f]=2` |
| 上游status非零或结果缺C+4 bit13 | 返回0xff |
| 存在A0EC且value0 | `L[16d]=2` |
| 存在A0ED且value0 | `L[16e]=2` |
| 存在A0D4且value0 | `L[16f]=2`；此初始化GET未选择A0D4，不应虚构它必回 |

这些1／2／3是Lib层接口／发现状态，**不是wire NFCEE status**。实际NTF还会把1写入已连接接口，removed／disabled路径写2；3保留为代码中的原始默认值，不在本报告强命名为成功。

## EnableNfceeDisc 的原条件与实际发送

`phLibNfc_EnableNfceeDisc 0x2a2f55b9c` 先置 `L[2e8]=1`，清 `u32(L+228)`；若三个字节 `L[16d/e/f]` **全为2**，或 `u32(L+1f8)!=0`，立即返回0、不发discovery。其它路径调用 `phNciNfc_Nfcee_StartDiscovery 0x2a2fb5a78`；没有改动或运行这些条件。

NCI入口先检查context／callback，分配1字节（失败0x0c）；调用 `ReleaseNfceeCntx 0x2a2f6f6f4`，再写action1至分配的payload及 `N[1188]`，保存上层callback／context，装入sequence `0x2b17bdfd0`。正常立即返回pending `0x0d`；立即失败释放payload。后续生命周期复核明确：这里ReleaseNfceeCntx仅按N[f68]释放R+10的TLV保存区并清该指针，未清ID／count、未释放内嵌R／N；不能凭函数名称整表清空，也不能把旧缓存当本次已枚举结果。见[record生命周期](comet_se_record_lifecycle_20261023.md)。

| sequence成员 | 实际函数 |
| --- | --- |
| 发送 | NfceeDiscover `0x2a2f6bbf8` |
| 响应 | ProcessNfceeDiscoverRsp `0x2a2f6bcd0` |
| 完成 | CompleteNfceeDiscoverSequence `0x2a2f6bdc4` |

发送 `...6bc4c–6bc90` 从 `0x2a2fc3608`取精确descriptor `{1,2}`（原段相对offset0x138，bytes `0100000002000000`），写OID0，payload为上述1字节action。沿既有 CoreIfTxRx→mux2→CmdTx→CoreBuildCmdPkt 映射，得到：**enable `22 00 01 01`**；禁用API复用同发送器时action0为 `22 00 01 00`，本轮未把所有禁用调用条件展开。timeout参数0x7d0是内部参数，非线上payload。

## RSP：只确认启动、保存count、注册NTF

正常RSP格式为 `42 00 02 status count`。当前 `ProcessNfceeDiscoverRsp ...6bd0c–6bd64` 检查非空payload，只显式拒绝长度>2，随后读取`P[0]`及成功时`P[1]`；因此**合法离线结构应要求长度恰2**，不能将它的短包检查缺口当兼容协议。

- 上游非零status直接保留；NULL response或一般非零`P[0]`→0xff；`P[0]==0xf1`→内部0x51。
- `P[0]==0`时，`P[1]`保存到 `N[f69]`（预期NFCEE数量），`N[1188]`复制到 `N[f78]`（当前discovery action），返回0。count=0不会由此变成“已存在SE”；此处也没看到count<=5的检查。
- Complete `...6be28–6be90` 按action1注册NfceeDiscNtfHandler；action其它值取消注册。注册descriptor从`0x2a2fc35f0`取`{3,2}`、OID0，并设置内部注册选项byte；这是NTF匹配条件，不是要发送的新命令。
- Complete在注册成功后即通过 `phNciNfc_Notify 0x2a2f0e6e8` 回调上层；本函数没有等待`N[f68]==N[f69]`的循环。Lib `ProcessNfceeDiscRsp 0x2a2f55c5c`成功时置 `u32(L+1f8)=1`，日志仅为“successfully started”。

因此须分别记录“请求pending／RSP接受／通知注册／实际设备记录／后续SE完成”，不能由 `L+1f8=1`推导全部通知已到。

## NTF：字段、长度边界及5槽设备表

NTF匹配为MT3／GID2／OID0，即header `62 00 len`；`NfceeDiscNtfHandler 0x2a2f6c33c`接收已去header／CRC的payload。正常结构为 `id, wireStatus, m, protocols[m], k, TLVs...`，不是status+count型RSP。

| 字段／处理 | 当前代码证据与离线约束 |
| --- | --- |
| 入参 | 上游status非零保留；NULL context→0x31；NULL wrapper／buffer或payloadLen0→1。之后读取多字段，不能把len>0当完整结构验证 |
| ID／status | `...6c3c8–6c3ec`拒ID0／ff；status仅0／1／2进入有效路径。0／1为connected active／inactive，2另走removed |
| 设备槽 | `N+f80+i*0x68`；GetDevIndex `0x2a2f0e58c`最多遍历5槽，按ID复用或找空槽，无槽→0xff。新设备成功后 `N[f68]++`，与RSP的`N[f69]`是不同字段 |
| 记录内容 | ID存record+1；正常wireStatus0→u32(record+4)=1，status1→0；record+0先设ff。removed路径有独立事件／reason处理，不应伪装为inactive |
| protocols | StoreNfceeProtocols `0x2a2f6ccb0`读取`m=P[2]`，要求m<=5；每项仅允许0、1、2、3、0x80，保存count@record+8及列表@+9；0项可解析，不证明可传APDU |
| TLV | protocols后一个byte为k；TlvUtilsParseTLV `0x2a2f7458c`按`T,L,V`累计并要求剩余区长度准确收尾；StoreTlvInfo `0x2a2f6ca10`最多接受3项，支持tag0／1及厂商A0分支，其它tag失败。A0分支含removed reason，不能随意删掉或改写 |
| 总长度 | 合法模型需先验证至少`4+m`字节，再逐项验证TLV边界与count，不复制原处理器逐字段读取前不足的bounds检查；动态配置容量也必须与RSP count／实际ID集合一致 |
| 上层通知 | `...6c658–6c670`仅在处理成功且NCI callback `N+e8`存在时调用；内部event1与事件结构包含connected／removed标记、ID、record指针。该callback参数不是原始wire payload |

解析成功后，record保留protocol与TLV数据；普通tag0／1把指针指向已分配／保存的TLV区。Release／removed生命周期必须清理记录及相关存储，不能靠每个包重新填一份瞬时空对象。

Lib `SENtfHandler 0x2a2f05cd8`随后依ID与当前状态选择UICC／HCI／eSE等路径。以当前eSE ID0xC0的connected分支 `...06ef4–06f58`为例：需 `L[2e8]==1`、`L[16e]!=1`、`L[22b]==0`；增加 `L[16a]`，保存record指针到 `L+1b8`，置`L[16e]=1`、`u32(L+1c0)=1`，并存`u32(L+1c4)=(record+4!=1)`。因此Lib接口状态1与NCI record active值1含义不同，后者还被取反成另一个内部mode字段；不能一律复制wire status。

同日后续逐分支复核更正：此前本段误写ID80。`06960 cmp80/b.gt`仅为分界，真正eSE匹配是`06a9c cmpc0`；removed分支`06a20`也匹配c0。见[record生命周期复核](comet_se_record_lifecycle_20261023.md)。

## 补充：NFCEE_MODE_SET 的独立命令与等待

`phNciNfc_Nfcee_ModeSet 0x2a2fb5db0`接受record及mode（0／1），`...b5e58–b5e68`从record+1取ID、写mode作为第二byte、长度2；sequence `0x2b17bdfb0`为ModeSet `0x2a2f6b7c4`→ProcessModeSetRsp `...6b8a8`→CompleteModeSetSequence `...6b9cc`。发送器在`...6b820–6b868`复用`{1,2}`、OID1，因此wire为 **`22 01 02 ID mode`**，不是A0EC参数或ioctl编号。另有NULL record→ID0的独立路径，不能把它套入普通已枚举SE。

ModeSetRsp读取payload[0]：0成功、f1→内部51、其它ff；当前局部未见长度检查，合法RSP需有status字节。Complete在成功且record非空、并非`mode1 && ID1`时创建NCI timer `N+1238`，期限参数0x7d0、callback=`NfceeMgmtSetModeTimeOutHandler 0x2a2f6c1a4`；此路径未立即Notify上层。其它成功例外或错误路径走Notify。timeout清理timer，再按NCI平台flags选择内部status0x2f／0传保存callback `N+330/338`；故超时也不总等价统一失败码。正常通知的timer取消／callback路径补充如下；仍不能把RSP成功当SE模式迁移完成。

### 正常 ModeSet 完成通知：两个私有 NTF，非 NFCEE_DISCOVER_NTF

RegAllNtfs `0x2a2f470d0`的`...473b8–473e8`与`...474a4–474cc`复用精确常量`0x2a2fc36a0={3,15}`（bytes `030000000f000000`），分别注册OID0x18与0x20。因此当前线上匹配为 **`7f 18 len` NFCEE Power OFF**和 **`7f 20 len` System End of Operation（EoOp）**，handler分别为`ProcessModeSetDisableNtf 0x2a2f21afc`／`ProcessSysEoOpNtf 0x2a2f2191c`。它们与`62 00`设备枚举通知不同。

| handler／条件 | 正常完成动作 |
| --- | --- |
| 两者公共门控 | `N+330` callback必须非NULL、`N[1920]==1`；该byte由ModeSet发送时清0，成功RSP处理开头置1（`...6b8e4–ec`） |
| EoOp `...219a8–219d4` | 当前record非NULL且ID不为1时，要求`payload[0]==record[1]`且请求mode非0；否则记录drop并保留等待。NULL record／ID1走单独允许路径 |
| Power OFF `...21ba4–21bb4` | record为NULL或请求mode0才进入完成；record非NULL且mode1时改走一般SE通知，不取消此次ModeSet等待 |
| 停timer | EoOp `...219d8–21a2c`／Power OFF `...21c08–21c5c`：有效`N+1238`先stop、delete、写无效值 |
| 结果及上层 | EoOp取payload[1]、Power OFF取payload[0]保存到`N[1a18]`，清`N+330/338`，再调Notify，传入上游callback status及该结果byte指针。局部检查不构成严格payload长度保证：合法结构应至少EoOp2字节、Power OFF1字节 |

**正常NTF并非直接调用N+330。** ModeSet入口`...b5ea8/b5eac`将callback/context存`N+d38/e80`，`...b6064/b6068`另保存同份到`N+330/338`作pending／timeout用途。正常handler清后者后调用 `Notify 0x2a2f0e6e8`；`...e72c–e774`读取并清前者，再实际调用原callback。timeout路径才直接调用`N+330/338`。因此正常NTF的data byte也不能与callback status或wire NFCEE active状态混为一谈；并未由这段证明最终LoadMW完成。

## 异步完成、Session ID与timer边界

主初始化 `InitializeComplete 0x2a2f55d38`在成功分支注册 `SENtfHandler`（`...55e1c–55e38`），并将 `L[16a]=1`；它还注册其它通知、处理静态配置／错误路径。这个值不是discovery RSP中的controller count。

实际后续 HCI／NFCEE sequence表 `0x2b17bea08`及附近变体包含：OpenLogConn、standby、HciOpenAdmPipe、allow list、ModeSetHciNwk、**DelayForSeNtf**，随后HciInitComplete；另有GetNfceeSessionId→VerifyNfceeSessionId→DelayForSeNtf→GetSEPipeStatus→NfceeInitializeComplete。此处只证明表成员和执行条件，未宣称所有profile都跑每一步。

- `DelayForSeNtf 0x2a2f9efd8`仅在上游status0时处理；若`L[2f0]==1 && (u32(L+1e8)&0xb)==2`，清2f0并立即完成；delay `u32(L+250)==0`也直接完成。
- 否则用`L+250`毫秒创建／启动timer，callback=`NfceeNtfDelayCb 0x2a2f5aed8`；成功保存timer于`L+248`、置`L[2f1]=1`并返回0x0d。创建失败0x0c，启动失败0xff。
- timer callback校验现存Lib context，清2f1、停止／删除timer、把L+248设无效值，再调用Lib SeqHandler继续；**定时器到期不是一条成功NFCEE_NTF**。StopSEInitTimer `0x2a2f5c134`依接口状态与Session/EoOp flags组合可提前走同callback。
- `GetNfceeSessionId 0x2a2f5a794`要求`L[16a]>=2`后才按当前SE类型／接口状态选择读Session ID；无须poll时用SkipSequenceSeq跳1步。实际poll仍走CORE_GET_CONFIG；此处没有发APDU。
- `VerifyNfceeSessionId 0x2a2f5a9f4`将选中8字节Session ID与全ff比较；有效时置`L[228/229/22a]`对应flag并清timer counter／delay。全ff时递减`L[b71]`；耗尽置`L[22c]=1`。
- `DelayForSeNtfProc 0x2a2f9f198`在counter仍非零时RepeatSequenceSeq回退2步；22c置位时日志“Session Id is not retrieved in 10 tries”并返回0xff。本轮未把所有profile设置b71的初始值／所有session TLV ID展开，不能由日志固定所有重试次数。

### 已闭环的 Session ID 配置参数

GetNfceeSessionId清配置后，`L+1290`就是`C+478`（`C=L+e18`）；按当前SE类型选择bit6／7／5。GetRfParams `...13fc4/13fdc/13d4c`分别写LE halfword `eba0/eaa0/1ea0`，转换成线上ID字节；ProcessRfParams `...15014–150e8`每项要求value长度精确8后复制。

| 当前分支（非所有profile） | 选择bit／ID | CORE_GET_CONFIG无CRC命令 | 结果与验证flag |
| --- | --- | --- | --- |
| UICC：type2，`L[229]==0`且`L[16d]`为1／3 | bit6→`A0 EA` | `20 03 03 01 A0 EA` | `C+578`，成功存在bit6；Verify置L[229] |
| eSE：type1，`L[16e]`为1／3且`L[228]!=1` | bit7→`A0 EB` | `20 03 03 01 A0 EB` | `C+570`，存在bit7；Verify置L[228] |
| SE2：type7，`L[22a]==0`且`L[16f]==1` | bit5→`A0 1E` | `20 03 03 01 A0 1E` | `C+568`，存在bit5；Verify置L[22a] |

三者仍受`L[16a]>=2`及当前对象等前置条件。对应正常RSP需status／count匹配并包含该ID、长度8和真实8字节值；全ff被Verify视为尚未取得Session ID，触发既有重试计数。这里没有选择／合成Session ID值，也没有把它称为可直接重放的SE身份凭据。

## 对最小无RF契约的含义与未恢复边界

需要维护：A0EC／ED等真实配置值、discovery action和请求count、预期数量与实际ID集合、每个NFCEE的active状态／协议／TLV生命周期、Lib接口状态、Session/EoOp与timer完成状态。把所有接口配置为零可能命中已有跳步，但同时表示没有相应可用接口，不能拿它证明SE能力或Wallet可绑卡。

NFCEE discovery属于内部执行环境枚举，不能与RF_DISCOVER的射频轮询混为一谈。上层mapping／routing、SE模式、HCI pipe／APDU传输、供电和PN548完成条件仍需独立成立；尤其父任务已发现RF interface count0虽然可被CORE_INIT解析，却不保证后续mapping分支可继续。

本报告尚未闭环：所有NTF乱序／重复／removed reason分类、全部HCI与Session值的语义、各profile timer默认值及最终LoadMW callback的所有路径。已恢复足够的静态负向约束来检查离线模型，但没有构造成功控制器响应、运行原生LoadStack或证明SE初始化成功。
