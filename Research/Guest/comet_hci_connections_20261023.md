# 23G90 Comet：HCI 逻辑连接与 credit transport（离线）

日期：2026-10-23。范围只含 CORE_CONN_CREATE/CLOSE/CREDITS、连接表与 HCI 数据发送接口；不声称 admin pipe、Session 校验或 LoadStack 已运行成功。
本轮未执行 Comet/HAL/后端、未启动或挂载 VM、未改系统/门槛/产品代码、未绑卡。新定制实现的具名编译宏规则适用于后续实现；本轮纯研究不添加空宏。

## 对象与证据

- 同版 IPSW 原版 `libNFC_Comet.dylib`，UUID `AAD82B14-9985-3582-9A57-22047E668A31`。
- 重建 Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；原 DSC 与重建 `__text` 已逐字相同，text SHA `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。
- 当前指令：`.build/validation/nfcc-protocol-20261023/user-frames/comet-disass.txt`；函数边界索引 `init/comet-functions.json`。方法名以当前日志字符串与边界交叉识别，不冒充完整私有符号表。
- 本轮定向摘录、常量与静态校验：`.build/validation/comet-hci-20261023/connections/`。`constants.json` 两处常量已与保留原始 `__TEXT.__const.bin` 比较一致；校验未执行库。
- 下文 `L` 为 Lib ctx，`N` 为 NCI ctx，`H` 为 HCI ctx，`P` 为已剥离 NCI header 的响应/通知 payload；VA 均属此 Comet。
- [NXP 官方固定提交 nci_defs.h](https://raw.githubusercontent.com/NXPNFCLinux/linux_libnfc-nci/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)仅作协议名称交叉核对：GID0，CREATE4/CLOSE5/CREDITS6，NFCEE destination3、HCI interface1。当前 Apple 字节以以下指令为准。

## 创建：选中 NFCEE record 后建立动态连接

| 当前函数/VA | 已确认行为 |
|---|---|
| `OpenLogConn 0x2a2f5a548` | 保留传入失败；成功仍需 `L[16a]!=0`，否则 `ff`；清 `L[22d]`，取 `N=*(L+c10)`、record=`*(L+188)` 调 `Nfcee_Connect`。 |
| `Nfcee_Connect 0x2a2f6c810` | 保存 record 到 `N+1228`，回调到 `N+d38/e80`；`6c874–898` 构造 destination=3、参数数1、TLV tag1/len2/value=`record[1],01`。 |
| `LogConnCreate 0x2a2f3d77c` | `3d858–8a8` 比较 `N[ec1] > N[d]` 后拒绝，并扫描动态槽1..3；`3d954–9bc` 生成6字节 payload。`N[d]` 为先前 CORE_INIT 保存的最大逻辑连接能力。 |
| `SendConnOpenCmd 0x2a2f87acc` | `87b44–b8c` 使用常量 `2a2fc36a8` 首两 word `{1,0}`、OID4，payload=`N+370`、len=`N+378`，交 `CoreIfTxRx`；内部 timeout `7d0` 不是 wire 字段。 |

当前 NFCEE/HCI 路径真实线包（未含可选链路 CRC）为：

```text
20 04 06  03 01 01 02 <NFCEE_ID=record[1]> 01
│  │  │   │  │  │  │       │              └─ HCI access interface
│  │  │   │  │  │  └─ TLV length=2
│  │  │   │  │  └─ NFCEE destination parameter tag=1
│  │  │   │  └─ number of parameters=1
│  │  │   └─ destination type=3（不可改写为2）
└─ MT=CMD,GID=0；OID=4；payload length=6
```

`{1,0}` 是内部 descriptor 的 type/GID；线上 `20` 由 encoder 生成。完整 descriptor→CoreIfTxRx→CmdTx→CoreBuildCmdPkt 链见 [厂商初始化研究](comet_vendor_initialization_20261023.md)。

## 创建响应、记录布局与实际可用条件

`LogConnResp 0x2a2f87be8` 的正常 RSP 为 `40 04 04 <status> <MPS> <initial credits> <connID>`。
`87c48–6c` 仅在 status0 时按选中槽 `i=N[ec2]` 保存三字段并置 active1。
连接记录 `E_i=N+ec8+i*20`，初始化共4槽，槽0为静态连接，动态申请只选1..3：

| offset | 字段/实际使用 |
|---|---|
| `+0` / `+4` | byte destination ID / u32 destination type |
| `+8` / `+9` / `+a` | byte connID / credits / MPS |
| `+10` / `+18` | destination record 指针 / byte active |

`LogConnInit 0x2a2f88044` 设静态 connID0、credits0、MPS0、active0，选中槽 `ec2=ff`，写 `ec1=1`。本轮未闭环 `ec1` 所有增减点，不能把槽数与计数维护混为一谈。
`CompleteConnOpenSequence 0x2a2f87cf0` 释放请求 payload，清一次性 callback 后传 `&E_i.connID` 与内部 status。
`NfceeConnCb 0x2a2f6c900` 成功分支调用 `LogConnUpdateDestInfo 3dc24` 保存 record 关联，再经 `LogConnGetConnId 3dda4` 查 connID，然后通知上层。

必须保留当前实现的证据边界：

- `87c24–30` 只检查 payload 非空/len非零，未在此函数证明 `len>=4`；正常建模仍须完整4字节，不能利用越界读取代替响应。
- `status=f1→内部51`；输入失败/空 payload→内部ff。**其他非零 wire status 在 `87c40–44` 可返回内部0，却不更新 active/MPS/credits/connID。** 该局部返回值不能证明连接建立。
- `LogConnGetConnId` 未找到/未 active 时可给出 `ff` 而返回0；应核对 active record、有效 connID 与 MPS，不能只核对 callback 的零值。
- 本轮未见 CREATE RSP 分支验证 connID 高位/MPS正值；离线协议约束须与后续低4位编码、分片一致。未知字段不填假值。

## 关闭与失效

| 当前函数/VA | 已确认契约 |
|---|---|
| `LogConnClose 3daf8` | 先查 connID、保存选中槽/回调，运行 close sequence；未找到路径可直接返回0，不能据此说已发送 CLOSE。 |
| `SendConnCloseCmd 87d8c` | 取 `E_i+8`，descriptor `{1,0}`、OID5、len1 ⇒ **`20 05 01 <connID>`**。 |
| `LogConnCloseResp 87ec4` | 正常 **`40 05 01 <status>`**；status0 清 active；f1→51，其余非零同样存在局部0返回而不清 active。 |
| `CompleteConnCloseSequence 87fb0` | 清请求并调用上层完成回调。 |
| `UpdateClosedLogConnInfo 3dee8` | 可按 destination record 直接使连接 inactive；不能反推所有失效均实际发送 CLOSE。 |

## credit 通知、等待与消耗

`LogConnInit` 从 `2a2fc3b30` 读到 `{3,0,6,0}`，注册 `LogConnNotifCB 0x2a2f881b8`；type3/GID0/OID6 对应线上 **`60 06 <len>`**。
正常通知 payload 是 `count` 后跟 `(connID, credit_delta)` 对；单对合法形状为 `60 06 03 01 <connID> <delta>`。

- handler 要求上下文/包装与 payload 有效、上层 status0、len非零，并核对当前解析 GID=`N+72c` 为0、OID=`N+730` 为6。
- 单对路径 `88380–88494`：由 P[1] 查连接，把 P[2] 加入 `E_i+9`。`bics ff,sum` 命中后写fe；这是特殊值分支，**不能笼统称所有溢出均饱和到fe**。
- 已恢复单对所需数据流；当前多对循环的指针推进/各 pair 独立处理未闭环，且未在该入口证明 `len>=1+2*count`。不扩推多对兼容性。
- `GetConnCredits 3e1f0` 对非零 connID 检查 record/active 后给 credits；mux `0bed8` 内 `c018–c068` 在已知连接 credits0 时走 `RegForConnCredits 3e318`，暂存发送，返回 pending `0d`，此时不发 TML 数据。
- 等待状态含 `N+1978` callback、`+1980` context、`+1961` waited connID、`+1990` timer；有效非零 credit 与等待 connID 匹配后，`8873c–8881c` 停/删 timer、清等待并调用 callback。
- mux `c1d4–c1ec` 在 TML 发送返回 pending 后，对数据 mux 调 `DecrConnCredit 3ecf0`；每个实际发送的数据分片消耗一 credit。命令 mux2 排除此步骤。
- 未把 credit `ff` 解释为无限额度；当前减法路径按 byte 消耗。credit0/EOF/响应 timer 还有特别处理，本轮不把零 delta 通知当“获得发送额度”。

## HCI 发送接口与分片层次

`OpenLogConnProcess 5a5e4` 在上一步 status0 后重建 `H=*(L+200)` 的 HCI Core。
H 中 `+318` 为 NCI ctx、`+320` 为 NFCEE record、`+3bc` 为 driver handle。
`HciCoreInit 4afcc→RegUnRegSeEvent b7870` 使用 record 查当前 connID，注册接收回调 `HciCoreRecvCB 4b2d8`；**connID 不等于写死的 NFCEE ID**。

| 层次/VA | 当前已确认字段与约束 |
|---|---|
| `HciCoreSend 4bc24` | 入参为 pipe byte0、instruction byte1、message type byte2、len32@4、data ptr@8；调用 `SeSendData 29044`，使用 H 的 NCIctx/record。 |
| `SeSendData 29044` | 查 connID 写内部 descriptor+c，复制 HCP 参数到 mux object+20；选 mux1/特定条件3，保存异步 callback/context。mux 编号不是 wire opcode。 |
| `HciCoreBuildHcipacket 429bc` | 首片 HCP header：`pipe | (final<<7)`、`instruction | (messageType<<6)`，再拷 payload。 |
| `HciBuildHcpFragment 42888` | HCP 续片是 `pipe | (final<<7)` 后接连续数据；不要为每片重新添加 message header。 |
| `BuildDataPktNci 42cc0` | 由保存 connID 查询 MPS；按 MPS 分片，h0=`connID&0f`，还有后续数据则置 bit4；h1=0，h2=本片长度，后接 HCP 字节。 |

因此外层实际 DATA 是 **`<connID低4位 | (more?10:00)> 00 <片长> <HCP bytes>`**，MT0；`42e00–e20` 与 `42fd8–43038` 给出 header/复制证据。
**HCP 的 bit7 chaining 与外层 NCI 的 bit4 PBF 是两层状态**；必须同时维护 HCP重组、MPS、credits 与 connID关联，不能只把 APDU 放进 NCI payload。
`HciCoreSend` 有独立 HCI 命令响应 timer（默认2000，可被上下文覆盖）；credit wait timer、NCI控制命令 timer 与它也不是同一个完成条件。
TML pending/发送 callback 成功只说明下层发送推进，不等于 HCI response、admin pipe、SE APDU 或 LoadStack 成功。

## 最小离线约束与未闭环

1. 先有选中的 HCI NFCEE record/有效状态，再创建 destination3/interface1 的动态连接；记录 RSP connID/MPS/credits 并绑定 record。
2. DATA 用绑定 connID、MPS 做 NCI分片，分别处理 HCP chaining；发送每片消耗 credit，零额度等待对应 connID 的有效 credit NTF。
3. 同时保存异步 callback/timer；关闭/失效后禁止复用旧 active record。控制 RSP、credit NTF、HCI response 必须分别检查。
4. 以上可以形成独立离线解析/状态约束；本轮仅字节与静态分支核对，没有实现模拟器或伪造成功响应，也没有证明真实系统 LoadStack 成功。
5. 同日后续[APDU transport](comet_apdu_transport_recovery_contract_20261023.md)已补齐credit等待timer与RX路由；多pair循环未见按pair推进，不能假设逐对处理正确。全部EOF/profile组合、重组异常与运行证据仍未全证；admin pipe与Session由同轮独立研究承接。
6. 与 [NFCEE discovery](comet_nfcee_discovery_20261023.md)、[用户态帧/CRC](pn548_user_frames_crc_20261023.md)合看：连接准备、帧完整性与 SE身份/应用可用分别需要证据。
