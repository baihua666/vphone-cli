# 23G90：SetMode进入APDU模式的完成契约（离线）

日期：2026-10-23。范围：PN548→Comet公共SetMode→eSE SE状态机→条件电源/NFCEE/pipe配置序列→模式callback。**进入软件Apdu状态不等于一笔APDU、SE应用或Wallet成功。** 数据/credit由同轮独立研究承接。
本轮仅静态读取同版二进制/原DSC小段，未执行Apple库/HAL/VM/后端、未挂载VM、未改系统/门槛/产品代码、未绑卡。纯研究不添加实验宏。

## 身份与证据

- Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`，重建Mach-O SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；原DSC text与重建已逐字验证。
- 本轮证据 `.build/validation/comet-apdu-20261023/modeset/`：完整函数摘录、PN已校正stub摘录、`sequences.json`、`apdu-state-rows.json`、`constants.json`与`static-validation.json`。
- SE表来源为前轮原DSC目录/AUTH/DIRTY（6表98行逐字验证）；本轮2张模式sequence直接读保留原AUTH并再与重建比较。地址/原encoded指针保留在JSON，不是直接把raw word当VA。
- [NXP官方固定提交NCI定义](https://raw.githubusercontent.com/NXPNFCLinux/linux_libnfc-nci/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)本轮经MCP读取，仅交叉核对NFCEE_MODE_SET=OID1、参数2字节/RSP status1字节；以下Apple mode/API/条件以本版指令为准。

## 五种数值空间不能混用

| 层 | 本轮eSE进入APDU的值/含义 |
|---|---|
| PN配置routing期望 | 配置eSE值1的wired分支 `2a304fc08–fc14` 调PN SetSEMode(SE编号1,mode2)；配置值不是wire mode。 |
| Comet public API | `phLibNfc_SE_SetMode(driver,SEhandle,mode2,callback,user)`；type1=eSE。 |
| 内部SE event | `FindSetModeTransEvent 9da34` 中 `9db10–28` 将type1/API2映射 **8c**。不是83、85或NCI opcode。 |
| SE状态机current/target | 软件state3=Apdu；普通初始化后eSE软件state1=Off。 |
| NCI NFCEE mode | full sequence置 `L+238=1`，线包 **`22 01 02 <真实NFCEE_ID> 01`**；API2不会原样成为wire mode2。 |

eSE对象SetPower(type2普通与type6 Eos)均可进入SetEmbeddedSecureElementPower→SetConfiguration→routing→SetSEMode；既有缓存/profile可跳步，不能把SetPower当一条固定物理供电命令。前段准确对象绑定见[eSE电源与枚举研究](comet_ese_power_enumeration_20261023.md)。
Comet API0/1/3/4有不同事件/型号策略；例如type1/API3→8a，而若型号不支持保留fully-off可降API1。本文不把它们与API2混接；type7/API2→9b也不冒充eSE type1路径。

## 公共入口、真实record和同步/异步分支

`SE_SetMode 2a2f79a88`：

- `79b84–b98` 发现已有data/ATR/raw回调槽 `L+18c8/1988/18d8` 非空，返回6f。之后SE FSM还会检查主/SE pending；不承诺并行请求。
- `79cac–ce4` 要求mode<=4且callback非NULL；扫描 `L+198` 起5个16B列表条目，以调用者真实SEhandle匹配。`79cf0–f4` 保存条目地址到 `L+230`（下文E），并以E+8取SE type。
- type1/API2清 `L[1]` 与 `L[22b]`；`79d94` 保存所选API mode至 `L+23c`，event8c以status0交SM。
- 立即返回0：`79df8–e00` 更新 `E.mode(+c)=L[23c]`，**不注册/调用异步callback**；PN queue block自行把同步结果写入等待对象。
- 返回pending0d：`79ddc–df0` 才保存callback/user到 `L+1a18/1a20`，保留E.handle，并把 `L+240=7f`。其他错误不会伪装成pending。

SE FSM记录与表公式见[后置SE状态机研究](comet_se_post_init_routing_20261023.md)：eSE记录 `R1=S+20`，字段current/target/pending/original event为 `+0/+4/+8/+c`；pending返回仅保存target3与event8c，current尚未提交3。

| 当前SE state | 原表event8c行VA | handler / nextState3 |
|---|---|---|
| 0（尚未归一） | 无，遇cf | null→93 |
| 1 Off | `2b1490f10` | `67a3c` OffToApdu |
| 2 Virtual | `2b17bd790` | `6839c` VirtualToApdu |
| 3 Apdu | `2b1490d50` | `685c0` ApduToApdu |
| 4 PwrOff | `2b17bd890` | `68da8` PwrOffToApdu |
| 5 Removed | `2b17bd960` | 同OffToApdu；不等于record/后端已恢复 |

## 按原状态选sequence，不能强制每次同一包序列

- Off `67a88–acc` 只处理8c；若BA8/BA9/BAA/BB0任一flag为1，则调用 `IsVirtual(driver,type2)` 检查UICC软件状态；其返回0（UICC Virtual）时拒绝93。未命中该拒绝才置L238=1并选full表。
- PwrOff `68df4` 同样置L238=1并选full表（无L返回ff）。
- Virtual `683e8–68484`：BA9/BAA/BB0任一为1时，若 `L[2e9]==1` 直接更新E.mode并返回0，否则置L238=1走full表。
- Virtual在上述flag均不为1时，`684bc–dc` 比较电源缓存 `L[0]` 与desired `L[1]`：相等同步0；不等选**power-only表**，不在此路径发送NFCEE mode命令。
- 已Apdu `685c0`：同8c只比较这两个缓存，相等同步0，否则power-only。以上均未绕过型号条件。

原AUTH表每项16B `{send,process}`，最后 `{NULL,complete}`：

| full `2b17beb98` | send → process |
|---|---|
| row0 `beb98` | SetPowerModeSeq `9bde4` → `9bf90` |
| row1 `beba8` | SetModeSeq `9c09c` → `9c1dc` |
| row2 `bebb8` | SERecoveryGetPipeStatus `5a10c` → `5a2b8` |
| terminal `bebc8` | NULL → SetSeModeSeqComplete `9c378` |

power-only `2b17bec08` 只有 `9bde4→9bf90`，terminal `bec18→9c378`。因此“SetMode成功必须总见NFCEE_MODE_SET”不符合当前优化路径；反过来，full路径也不能只应答standby。

## full路径wire、状态与正常完成条件

1. **standby/电源缓存**：`9bea0–bf38` 计算desired=`L[1]&L[2]`，若与当前L[0]相等或特定profile条件满足可同步跳过；否则调 `NCI_SetPowerMode b6074`。
   eSE API2已清L[1]，故未跳过时包为 **`2f 00 01 00`**；SendStandbyCmd `469c4` 使用descriptor `{1,15}`、OID0、timeout参数7d0。
   NCI原表 `2b17bc350` 为SendStandbyCmd→CommonNciRsp2 `1a0ac`→CompleteStandby `46a9c`。合法RSP **`4f 00 01 status`**；`1a13c–18c` 要求payload非NULL、len恰1、status0；f1→51、bd→bd，其余/非法→ff。
   Lib `SetPowerModeSeqEnd 9c080–94` 成功才更新当前缓存L[0]、翻转L[1]并置L[2]=1；不能在发送时提前当供电完成。
2. **NFCEE enable**：`9c160–184` 从 `E.handle` 取NCI record，使用L238=1调用 `Nfcee_ModeSet b5db0`，发送 **`22 01 02 ID 01`**。ID从record+1取，不能将PN编号1或HCI连接ID代入。
   合法RSP **`42 01 01 status`**；status0进入后续完成，f1→51，其它ff。局部parser未证明严格len检查；合法模型仍须有status字节。
3. **RSP后等待**：除record为空或mode1/ID1等原例外，CompleteModeSet `6b9cc` 创建 `N+1238` timer、参数7d0，并等待通知；**RSP0不是Lib模式callback完成**。
   正常enable匹配私有 **`7f 20 len` EoOp**：`2191c` 要求待定callback、RSP门控N[1920]=1；普通非ID1 record还要求payload[0]=recordID且请求mode非0。至少两个payload字节，payload[1]是独立结果byte，不是NCI status。
   匹配后停/删timer，经Notify消费 `N+d38/e80` 的callback以推进Lib sequence；Power OFF `7f 18` 是mode0侧另一完成条件，不能用来随意完成本次mode1。完整例外见[NFCEE通知研究](comet_nfcee_discovery_20261023.md)。
4. **Lib模式处理**：SetModeSeqEnd `9c350–36c` 对eSE/enable成功可调用HCI `CoreAbortAllTran 4b9c4`，设置 `L[228]=1,L[16e]=1`；普通mode1分支不将EoOp结果byte当L240模式写入，L240可仍为pending初值7f。
5. **pipe状态**：full表继续SERecoveryGetPipeStatus；HCI上下文缺失分支局部可返回0，不能据它认定pipe可用。L[bb0]==1走已恢复的静态pipe信息；其他profile中eSE两个pipe `H[330]/H[332]` 都FF才请求配置，已有字段则可能同步跳步/注册pipe19。
   查询按flags编码 **`20 03 05 02 A0 22 A0 23`**，合法结果各value长度1，存在位和值1更新相应pipe，值0标删除。实际parser/静态值详见[HCI child报告](comet_hci_child_completion_20261023.md)，不能制造一份与当前profile矛盾的固定成功快照。

## 异步模式callback闭环

`SetSeModeSeqComplete 9c378`：成功在 `9c458–60` 写 `E.mode=L23c(API2)`；失败停止尚有效的L248 timer，只保留43/51/8f，其余非零归ff（`9c414–42c`），并清L[2e9]。
`FindSetModeIntEvent 9e8cc` 对type1按status0/非0产生 **a4/a5**，交SM；这两个event不是wire通知。

- 本次eSE pending event8c/currentOff1：a4查Off表 `2b1490f40→67b5c`；SE FSM `91b58–7c` 提交target3、清pending、把handler的x1恢复为保存的8c。a5对应 `2b1490f50`，清pending并恢复8c，但不先提交目标3。
- `SE_TransComplete 67b5c` 的 `67ca8–cc8` 认出8c，取callback=`L[1a18]`、user=`L[1a20]`，清这16字节，设L238=3；`67d10–28` 调 **callback(driver=L2628,user,SEhandle=E.handle,result=L240,status)**。
- 该五参数callback与初始三参数callback、APDU data回调都不同；result字可能是7f，不能当status0或API mode2。
- PN block `2a3087324` 调Comet；立即0由block直接记录结果；pending0d则等callback。PN callback `2a3087498` 取x1等待对象、x4状态，原样完成结果；不会用x3替换status。

## 超时、失败与恢复边界

- NCI ModeSet等待timer `6c1a4` 到期清timer；若N[12bb]/[12ba]/[12b9]/[12b4]任一等1，回调status2f，否则**兼容分支回调0**，data=NULL。该分支依真实平台flags，不能把所有timeout统一叫失败，也不能将0说成已经收到EoOp。
- 该0仍可能让SetModeSeqEnd/后续sequence推进；证明成功来源须分开记录RSP、匹配NTF与兼容timer，不能仅观测最终callback0。
- PN SetSEMode `2a3086fd8` 对最终43最多尝试3次（计数1..3）；其他错误不套同一重试。CRC/response-timeout的低层错误细节触发原错误处理，不能由此保证SE移除恢复必成功。
- 当前API真实record匹配、Off/Removed事件入口、power-only优化和callback保存均不是“创建SE后端”；Removed record/句柄重用/再发现还必须服从生命周期。本文不扩大到所有移除与重入排列。
- 后续一笔数据仍须另验Apdu状态、真实pipe、HCI回复、credit、timer与SE应用处理；模式callback0不能代替这些条件。

## 兼容前端与宿主SE后端的责任边界

前端必须保留原API数值转换、driver/record关联、所选profile与sequence、同步0/pending0d差别、callback次数及超时来源；transport应按当前线上包和通知分发推进状态，而非按内部event直接伪造完成。
宿主SE后端需要提供与真实NFCEE身份/模式、pipe状态与SE生命周期一致的执行能力，并实际处理后续APDU与应用状态；仅兼容NCI/HCI头、返回status0或软件state3不构成SE应用/凭据能力。
本轮产物只有可复核的静态接口约束，没有模拟器、成功响应生成器或原库运行trace；未证明APDU、支付凭据或Wallet绑卡可用。
