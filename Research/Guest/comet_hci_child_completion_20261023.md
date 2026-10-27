# 23G90 Comet：HCI child、Session ID 与初始化完成条件

2026-10-23；仅离线静态分析已有同版二进制、函数边界、PAC 指针表与反汇编。没有启动／挂载 VM、执行库／后端、调用 HAL、改系统／门槛、加载驱动或绑卡；没有产品修改或新增空编译宏。

## 结论与证据范围

**HCI network 初始化完成后，还会按已发现的 SE 类型串行执行 child sequence。** eSE child 除 Session ID 与 pipe 查询外，还含缺失 pipe 时清 Session ID、重新发现的分支。单个 `ANY_OK`、NFCEE ModeSet 响应或非空 SE 列表不能替代这些完成条件。

本轮闭环至 child 收尾、静态配置派发 event `0x75`，并定位初始 API callback 的消费点；**尚未证明 event75 在当前状态表中最终进入该消费点**。因此不能声称原版 LoadStack 全链成功、APDU 可用或 Wallet 可绑卡。

来源：`libNFC_Comet.dylib` SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。函数索引／指针表复用 `nfcc-protocol-20261023/init/`，新摘录位于 `.build/validation/comet-hci-20261023/completion/`。下列 VA 均为未滑动地址；短 VA 省略共同前缀 `0x2a2f`。L 为 Lib context，K=`*(L+0x200)` 为 HCI context，C 为配置结构；字段偏移均为十六进制。

配套：[HCP／admin pipe](comet_hci_admin_pipe_20261023.md)、[NFCEE 发现与 ModeSet](comet_nfcee_discovery_20261023.md)、[eSE 电源及枚举](comet_ese_power_enumeration_20261023.md)、[EEPROM 编解码](comet_eeprom_protocol_20261023.md)。这些是当前 Apple 库的静态证据，不以其他平台实现代替。

## HCI network 与 child sequence

PAC 表 `0x2b17bea08` 的每项为动作／响应处理器；终项是完成函数：

| 顺序 | 动作 → 处理器 |
| --- | --- |
| 1 | OpenLogConn `5a548` → `5a5e4` |
| 2 | DisableStandby `54e00` → SetStandbyModeProcess `54ea8` |
| 3 | HciOpenAdmPipe `98ed0` → `99030` |
| 4 | HciSetAllowList `99124` → `993a4` |
| 5 | ModeSetHciNwk `9946c` → `99708` |
| 6 | DelayForSeNtf `9efd8` → `9f198` |
| 完成 | HciInitComplete `99814`，表项 `0x2b17bea70` |

Admin 分支确认为打开既有 pipe1；并未证明这里主动 CREATE_PIPE。HCP 分片、连接 credit、消息类型与动态 pipe 创建由配套报告恢复，不能把 HCI response instruction0 的 `ANY_OK` 解释为 payload 首字节 status0。

`LaunchChildDeviceSequence (9d69c)` 在 `9d6dc–9d6f8` 要求 `L[16b+index]!=2`，且 `L+188+index*16` 的句柄非空；随后置 `L+250=100`、`L[b71]=10`、`L[172]=1`，并把所选 slot 保存至 L+230。按 slot+8 的 type 选择表：

| API 内部 index／slot | type | child 表／终项 |
| --- | --- | --- |
| 3／L+1b8（eSE） | 1 | `0x2b17beaf8`／`beb40` |
| 2／L+1a8（UICC） | 2 | `0x2b17bea78`／`beab0` |
| 4／L+1c8（SE2） | 7 | `0x2b17beab8`／`beaf0` |

三表均为 `GetNfceeSessionId 5a794 / VerifyNfceeSessionId 5a9f4` → `DelayForSeNtf 9efd8 / 9f198` → `GetSEPipeStatus 59e64 / 5a2b8` → `NfceeInitializeComplete 5bc78`；eSE 在终项之前另有 `ClearEseSessionIdSeq 5abb0 / 5ad28`。指针证据保存于 `completion/sequences.json`。

HciInitComplete 成功先置 L[172]=2；普通型号尝试 child index3，失败后在原型号条件下尝试 index4、index2。L[bb0]==1 还有静态 pipe 分支。各 child 启动期望返回 pending `0x0d`；不能把启动 pending 当完成。输入错误按 L[b73] 选择 ReleaseLibNfcContext 的状态 `0x89`／`0xff`（`99884` 附近分支），并可能先 HciDeInit。

这些 index、type、NFCEE wire ID、routing ID 属于不同字段域，不能互换；尤其 index3 不代表 wire NFCEE ID3。

## Session ID：CORE 配置、八字节与重试

`GetNfceeSessionId (5a794)` 要求 L 有效且 L[16a]>=2。它清零配置结构 C（0x6e8 字节），并按当前 L+230 选定的 SE、状态与完成标志决定是否查询：

| 对象 | 查询条件（除共同条件） | 配置 flag／值地址 | CORE_GET_CONFIG 命令 |
| --- | --- | --- | --- |
| eSE type1 | `(L[16e]&0xfd)==1` 且 L[228]==0 | C+4 bit13；C+478 bit7；值 C+570 | `20 03 03 01 A0 EB` |
| UICC type2 | `(L[16d]&0xfd)==1` 且 L[229]==0 | 同主 flag；子 bit6；值 C+578 | `20 03 03 01 A0 EA` |
| SE2 type7 | L[16f]==1 且 L[22a]==0 | 同主 flag；子 bit5；值 C+568 | `20 03 03 01 A0 1E` |

命令来自 `GetConfigRfParameters 136b8`／GetRfParams encoder，响应 parser 要求参数值长度**恰为8**；缺少上述条件会 SkipSequenceSeq，不能强称每次都发这三条。这里没有已证的 HCI_GET_PARAMETER registry1 会话读取。

`VerifyNfceeSessionId (5a9f4–5abb0)` 在成功、配置指针及相应返回 flags 齐备时，将选定的8字节值与八个 `FF` 比较。不是“只要存在就成功”：

- **不同于全 FF**：将该对象完成标志 L[228]／[229]／[22a] 置1，清重试计数 L[b71] 和 delay L+250。
- **全 FF**：若计数非零则减1；减至0时置 L[22c]=1。
- 未返回预期 flags／对象类型不匹配的路径会清这些完成标志及计数／delay；不能用无参数的 status0 冒充合法 Session 响应。

`DelayForSeNtfProc (9f198)` 在计数仍非零时调用 RepeatSequenceSeq(...,2)；L[22c]==1 时记录 “Session Id is not retrieved in 10 tries”、清22c并返回 `0xff`。child 启动明确设置100与10；这不代表所有网络等待也固定100ms或10次。

## 两种 EoOp 来源与等待条件

`ModeSetHciNwk (9946c)` 先清计数／delay；按对象尚未有完成标志累计等待：eSE 状态1或3且 L[228]==0 加4000，UICC 同类条件加2000，SE2 加2000（`994d0` 后分支）。是否已启用 HCI network record 还决定实际 ModeSet 或同步路径。

| 来源 | 当前代码中的字段／控制流 | 与 Session 的关系 |
| --- | --- | --- |
| 系统 EoOp `SysEoOpNtfHandler 9ba9c` | `9bb14` 后读取实际 payload[0]：c0→eSE，02→UICC；81 仅 L[ba8]==1 时→SE2；分别置 L[228]/[229]/[22a]=1，末尾 `9bc2c–30` 调 StopSEInitTimer |
| NCI 通知进入上述回调 | `ProcessSysEoOpNtf 2191c` 的非 pending-ModeSet 分支，`21aac–21ad4` 原样转交 payload 指针与长度，以内部事件15调用 N+188 callback；不将80转换为c0 |
| HCI admin EndOfOperation | ReceiveAdminNotifyEvt `5023c` 的 event ins1 调 `HciEvtEndofOptRcvd 9e3e8`；函数先置 L[228]=1，再检查等待 timer |
| HCI EoOp 推进 sequence | 仅 L+248 timer 有效且 L+250==4000 时，`9e428` 后停止／删除 timer，清 delay／计数并调用 SeqHandler(status0)；否则虽日志称 fast/drop，L[228] 仍已置1 |

系统通知为厂商 NCI `7f 20` 路径（前轮 NFCEE 报告）；HCI admin ins1 是另一层消息。本版系统 handler 使用 c0／02／81，NFCEE_DISCOVER的eSE分支也匹配c0；不同通知的payload格式仍需分别核对。此前误写“NFCEE eSE ID80”，已由同日[record生命周期复核](comet_se_record_lifecycle_20261023.md)更正：80只是比较分界。局部只显式检查 payload 非空／length>0，却在 eSE 分支读 P1 作 ATR-wait 日志；应记录真实合法 payload，不能把薄弱长度检查当协议允许短包。

Session 非全 FF 与 EoOp 都可推进同一完成标志；因此不能固定假设“必须先收到某个通知再查询 Session”，应遵守实际配置、通知到达顺序与 timer 分支。

## pipe 状态查询及静态型号分支

`GetSEPipeStatus (59e64)`：三对象状态都2时无查询；否则按选中 type 与 L[bb0] 决定 CORE 配置或静态路径。GetRfParams `13914` 与 ProcessRfParams `1437c` 的实际编码／长度检查：

| 对象／条件 | 线上查询 | 响应参数／长度／C 字段 |
| --- | --- | --- |
| eSE，L[bb0]!=1 | `20 03 05 02 A0 22 A0 23` | A022=1字节→C465；A023=1字节→C464 |
| UICC，L[bb0]!=1 | `20 03 03 01 A0 24` | A024=1字节→C466 |
| SE2 | `20 03 03 01 A0 E9` | A0E9=1字节→C467 |

eSE 请求设置 C+244 bits23/24；encoder 先检查bit24，所以实际顺序 A022→A023。UICC／SE2 分别bit25／26。parser 分别在 `14ca8/14ce4/14d20/14d5c` 检查长度1并设置对应存在位。

`GetSEPipeStatusProc (5a2b8)` 同时检查返回存在位，值1视为打开、0视为删除；其他值日志 unknown，但部分路径保留原 status，不能扩大为一律失败。成功字段写入如下（halfword 以小端记）：

| 参数 | 值1写入 K | 值0 | 回调注册 |
| --- | --- | --- | --- |
| A022 | K+332=`0x4116`（pipe16/gate41） | ffff | 本处不额外注册 |
| A023 | K+330=`0xf019`（pipe19/gatef0） | ffff | pipe19→RegisterPipeCb `9b7b0` |
| A024 | K+340=`0x410a` | ffff | pipe0a |
| A0E9 | K+342=`0x4123` | ffff | pipe23 |

L[bb0]==1 的 eSE 分支改用 `UpdateStaticPipeInfo (5a02c)`；UICC 写 K340=410a。静态函数把 VA `0x2a2fc3720` 的16字节复制至 K330..33f：`19 f0 16 41 27 f0 2b 41 28 f0 2c 41 29 f0 2d 41`，并注册八条 pipe。该常量已按 fileoff0xc3720 实读核对；只能用于自然命中此型号的分支，不能人为设型号来省去查询。

动态 admin CREATE_PIPE 通知则能恢复同一 K330／332 字段：hostc0/gatef0、hostc0/gate41 对应 eSE 两条；随后需真实 OPEN 交互，详见 admin 报告。固定 pipe 查询与动态创建不可混成同一步。

## 缺失 pipe 会清 Session 并重新发现

`ClearEseSessionIdSeq (5abb0)` 在 `5ac48–5ac64` 检查 **K[330]、K[332] 两个 pipe ID**：两者都不为 FF 则同步返回0，不写配置；任一为 FF 才设置 C+4 bit13、C+478 bit7，将 C+570 八字节填 FF，并调用 SetConfigRfParameters `16cb4`。

该分支的真实写命令为 `20 02 0C 01 A0 EB 08 FF FF FF FF FF FF FF FF`。BuildSetConfCmdPayload `1886c–18880` 选择 A0EB、8字节值；内部 helper 长度参数9不应误写成值长度9。它是原初始化的实际写操作；本轮只静态恢复，未调用。

异步写成功进入 `ClearEseSessionIdProc (5ad28)`，`5adb4` 置 L[22d]=1；错误保留输入 status。同步 no-op 不应称必然清会话：SeqHandler `08a00–08a34` 对同步动作返回0直接进入下一动作，响应处理器在另一路 `08a78–08a84` 被调用。

`NfceeInitializeComplete (5bc78)` 成功且 L[22d]==1 时，选择 eSE 重初始化表 `0x2b17be9a8`：DisableESE → DisableNfceeDiscovery → SetNfceeMode → GetNfceeIntfCfg → EnableNfceeDiscovery → `SeReInitSeqComplete 99aa8`。后者仅清 L[22d]、返回输入 status，不能独立视为最终 API callback。

## child 收尾与最终 callback 的证据边界

NfceeInitializeComplete 的普通成功路径置 L[172]=2；按当前 type 和原状态／型号条件继续 SE2、UICC child，或调用 `StaticListenModeRouting 5bb28`。输入失败选择89／ff清理。该函数名字不表示“所有 child 和 LoadStack 已完成”。

StaticListenModeRouting 选择表 `0x2b17bc570`：SetStandby → DisableESE／UICC／SE2 → FlushSramData → `staticFeatureCfgComplete 57ac8`；其完整状态校验见电源报告。`57d80–57d98` 以 status0向 SM 派 event75；SM 返回0才调用 `SM_SE_Initialize 6b5b0`。

最终 callback 的消费点已另行定向恢复（证据 `comet-hci-20261023/integration/final-init-callback.txt`）：

- `SM_Main_InitTransComplete 12054` 使用 **L+1aa8／1ab0**，不能误称这就是初始 API callback。
- `IdleTransComplete 5e7a4` 读取并清除 **L+17d8／17e0**；`5e8f8–5e904` 以 `(handle=L+2628, context=原17e0, status)` 调用保存的函数。
- 后续[同日路由恢复](comet_event75_final_closure_20261023.md)已闭环正常Idle1／pending event05的75／76表项、原event恢复和Idle consumer可达性；仍没有证明局部错误89自动转换为LoadMW的43，也没有实际callback运行trace。

## 原分支最小闭环与遗留项

1. 先固定实际型号／接口配置，建立真实 NFCEE record、HCI logical connection／credit；不能靠 Host synthetic entry 或改型号跳过 SE。
2. 完成当前 HCI network 表中的 admin OPEN、allow-list、ModeSet／timer 分支；响应类型、instruction 与 HCP 分片遵守 admin 报告。
3. 对自然选中的 child，返回长度与存在位正确的8字节 Session；保留非全 FF／全 FF／EoOp 的状态演进和重试行为。
4. 返回该型号的 pipe 配置，或完成真实动态 CREATE／OPEN。任一 eSE pipe 缺失时，实现清 A0EB→重新发现的实际状态变化，不能永远返回同一个成功快照。
5. 完成其他自然选中 child、静态收尾、VerifySEStatus；再核对最终初始 callback 的 status 与消费次数。

仍缺：当前实际型号对应的完整 HCI 主机行为与真实 trace；Session ID 持久存储／重启语义；EoOp 与各型号 timer 的全排列；后置SE子状态机全部动作；eSE APDU、SE 内应用／密钥及后续 Wallet 条件。SM event75→Idle completion的状态表证据已由后续同日研究补齐。以上清单是离线恢复的接口需求，不是已实现的模拟后端或通过的原生启动验证。
