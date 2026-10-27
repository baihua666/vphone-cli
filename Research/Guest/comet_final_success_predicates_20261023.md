# 23G90 Comet／PN548：最终成功与 eSE 可用的不同判据

2026-10-23；仅离线核对已有同版 Comet、PN548 原始字节映射与定向反汇编。不执行库／HAL／后端，不启动／挂载 VM，不改系统／门槛，不绑卡，没有产品代码、补丁或空编译宏。

## 结论

**当前已将正常 init 的 event75 接到初始 API callback；但这个 callback、PN isLoaded、LoadStack return0、eSE 数据可用仍是四个不同结论。** event75 先同步完成初始 callback，返回后才派发四个 SE 状态机事件；四次派发结果未被 SM_SE_Initialize 检查。PN548 等待 callback 后还会处理错误、提交 loaded，并执行自己的条件步骤表。

本轮没有运行原生栈或取得成功 trace。以下恢复的是原代码的判据，不能宣称现有 vphone 已实现 NFCC／eSE 后端、能收发 APDU 或完成 Wallet 绑卡。

来源身份复用前轮：[PN548／Comet 初始化](pn548_nfcc_initialization_20261023.md)。Comet SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；PN548 使用已按原 DSC 纠正 stub 的 `nfcc-protocol-20261023/integration/pn548-annotated-disass.txt`。新证据 `.build/validation/comet-event75-20261023/completion/`，0700／0600；没有重新解包大 DSC。VA 均为未滑动地址；Comet 短地址省略 `0x2a2f`，PN548 保留全地址。L 为 Lib context，K=`*(L+200)`；字段偏移均为十六进制。

## event75 派发前必须跨过什么

`staticFeatureCfgComplete (57ac8–57e20)` 是静态收尾 sequence 的终项；实际前序包含 SetStandby、DisableESE／UICC／SE2、FlushSramData，不能把函数名解释成仅配置一条 listen-routing 命令。

| 位置 | 实际控制流 |
| --- | --- |
| `57b00–57b08` | L 有效时清 L+2f0 两字节、L[2e8]，停止初始化发现阶段 |
| `57b0c–57be4` | 有效 watchdog L+b78 时停止／删除并清0；部分全局状态位同步清理 |
| `57b20–57b3c` | 输入 status 非0：按 L[b73]==1 选89，否则ff，交 ReleaseLibNfcContext；不派成功75 |
| `57c04–57c8c` | 输入 status0 才执行内联 VerifySEStatus，比较 callback、期望配置与 eSE 软件状态 |
| `57cac–57d7c` | 成功后清 b73；按 c80/c81/c82/c83 和 generic callback 处理延迟的 PLL／XTAL 通知，清相应标志 |
| `57d80–57d98` | 调 `022e0(handle=L2628,event=75,status=0,extra=L+2628,context=L)` |
| `57d9c–57da8` | 保存 SM 返回值；只有返回0才调用 SM_SE_Initialize `6b5b0`，否则直接返回 |

VerifySEStatus 检查软件状态，**不测量物理电压或 APDU 通道**。令 I=`L+17d8 callback非空`，F=`u32(L+1e8)`，B=`F bit1`，s=`L[16e]`，`57c04–57c8c` 的完整局部判定为：

| 场景 | 通过条件 |
| --- | --- |
| I 真、F==0 | 直接通过，不比较 s |
| I 真、F!=0、s==2 | 通过 |
| I 真、F!=0、s==1 | B==1 |
| I 真、F!=0、s 不为1或2 | B==0 |
| I 假 | `(s==1)==(B==1)` |

比较失败在 `57c58–57c6c` 按 b73 选择89／ff后清理。状态 s==2 可在部分初始化配置下通过，因此这个判断不能提升为“eSE 已连接”。也没有证据把这里89自动转换为 PN548 的43。

## child／Session／pipe 为什么仍是必要状态

[child 专项](comet_hci_child_completion_20261023.md)给出原 sequence、字段和命令；本轮只复核其对完成判定的影响，不扩大底层协议。

- HciInitComplete `99814` 的 success 先置 L[172]=2，然后可能启动 eSE／SE2／UICC child；启动返回 pending0d不是最终成功。
- LaunchChildDeviceSequence `9d69c` 在对象状态未移除、句柄非空时置 L[b71]=10、L+250=100、L[172]=1、L+230=所选对象；eSE index3／type1并非 wire NFCEE ID3。
- GetNfceeSessionId／Verify `5a794/5a9f4` 按配置读取严格8字节的 A0EB／A0EA／A01E；全 FF 走重试，非全 FF或相应 EoOp 可推进完成标志。无参数的 status0不等于 Session 成功。
- GetSEPipeStatus `59e64/5a2b8` 在普通 eSE 分支读 A022／A023，值1恢复 K332／330，值0记 ffff；静态型号有独立 pipe 表，不能人为改型号跳查询。
- ClearEseSessionId `5ac48–5ac70`：K330、K332 两个 pipe ID 任一 FF才实际 SET A0EB为八FF；双 pipe 存在则同步 no-op。实际写成功 Proc `5adb4` 才置 L[22d]=1。
- NfceeInitializeComplete `5bd44–5bdac` 优先检测22d并启动 `0x2b17be9a8` 重初始化：禁用 eSE／发现、设 mode、重读接口、重新发现。不能把一次有效 Session 快照当成永久完成。
- 普通成功 `5bdcc–5be4c` 置172=2，再按当前对象／型号／其他 SE 状态尝试后续 child；最后才启动 StaticListenModeRouting。错误进入89／ff清理，而非忽略。

“child complete”说明此原分支的控制面完成；实际被移除对象、Host synthetic entry、接口关闭配置仍须区分。数据可用至少还需真实 eSE record、pipe／连接／credit状态与实际数据事务证据。

## 75→初始 callback 与后置四个 SE 事件

本轮[状态路由专项](comet_event75_state_routing_20261023.md)恢复主表，关键边另保存 `completion/route-cross-check.txt`：

1. 原 init event5 返回 pending 时，MainStateHandler `02d60–02d6c` 保存 target3、pending1、saved_event5；current仍为1。
2. state1 的75表项选择 IdleTransComplete `5e59c`。`02c28–02c40` 在75提交 target、清 pending，并将回调事件恢复为 saved_event5。
3. `02d38–02d4c` 同步调用该完成处理器；`5e644–5e648` 按event5进入 `5e7a4`。
4. `5e7a4–5e7b4` 读取并清空 L+17d8／17e0；`5e8f8–5e904` 调保存的 callback，参数为 `(handle=L2628,context=原17e0,status)`。
5. 该同步调用返回后，staticFeature 的 `57da0` 才决定是否继续 SM_SE_Initialize。因此不能倒置为“四个 SE 事件都成功后才给初始 callback”。

以上闭环适用于前述正常 init pending 状态；事件、状态或保存 callback 不满足时不能泛称所有75必然产生同一 callback。另一个 `SM_Main_InitTransComplete` 在 `12054–120c4` 消费 L+1aa8／1ab0，不应误接为这次初始 callback。

`SM_SE_Initialize (6b5b0)` 的常量 VA `0x2a2fc3738`、fileoff0xc3738实读16B为 `82 00 00 00 87 00 00 00 93 00 00 00 98 00 00 00`。`6b5f8–6b618` 依次以 status0派 **82／87／93／98**，`6b638` 固定返回0，完全不检查四次 `022e0` 返回。

022e0 按事件范围分派：81..ae进入 SEStateHandler `916d0`，故这四项是 **SE 状态机内部初始化事件**，不是四条 NCI 命令，也不是四个完成通知。同日后续[四事件路由](comet_se_post_init_routing_20261023.md)已证明其正常路径仅同步软件归一：82为Common，87／93／98读对应Lib状态，归Off1／Removed5或失败；不能用 SM_SE_Initialize return0证明它们各自成功或 eSE 可用。

## PN548：callback、等待对象、loaded 提交

令 P 为 PN548 handle，W为 callback 等待对象；下表只描述普通初始化链，不把 DL-only或复用已有 loaded 当新启动验证。

| 阶段 | 精确证据与成功／错误含义 |
| --- | --- |
| 发起 init | block `0x2a3056754`，`6808–6824` 以保存的W为context、`0x2a3056940`为callback调用已核对的 `phLibNfc_Mgt_Initialize`；立即返回0d才走正常异步等待 |
| 初始 callback | `0x2a3056950–6974` 保留原w2；非0时先补错误信息至 W+8／c；随后以 `(W,原status)` 调 `0x2a304ee00`，不重写为0 |
| 唤醒等待 | `0x2a304ee24–ee54` 持 mutex 写 `u64(W)=status`、更新诊断 byte，并 signal cond；不能只观察 signal就判成功 |
| 等待结果 | `0x2a304e970` 在 mutex 下比较结果与未完成 sentinel `0x00000badcafef00d`；`0x2a304edb4–edd8` 解锁并返回结果。仍有 timeout／非法状态路径，不是收到任意通知即可解锁成功 |
| LoadMW 消费 | `0x2a3055b24–5b34` 调等待函数，非0进入错误处理；43有最多3次 eSE power-on重试，其他错误保留各自分支，不能统一当 retry成功 |
| loaded 提交 | 正常可达 `0x2a30560d8–60e0` 才置 return0、P[39]=1；部分路径在此前还调用 `_NFDriverDebugFailedHW @0x2a30673a4`并检查结果，callback0不能跳过后置分支 |

因此原 callback0是 LoadMW 成功链的必要证据，但不是独立充分条件。P[39]提交在 LoadStack 的后续0..23步骤之前，不代表步骤已全部完成。

## PN548：24步与最终返回

原表 VA `0x2b2414540`，24项、stride24；本轮直接复核既有576字节表并保存 `completion/pn-step-flags.json`。关键条件：

- `0x2a3055104–5108` 保存此时 loaded 快照；`5158–5160` 按真实 NFProductHasNFCRadio跳过带0x8步骤，其余仍按主／副控制器和load flags决定。
- `5184–518c`：0x100允许不依赖 loaded 快照执行。step0／1 flags0x106，step6 flags0x192；因此“MW刚置loaded”不会自动跳过这些步骤。
- `52dc–52e8` 实际函数返回0才直接推进；错误在 `54ac–54b4` 检查step0x80且结果0d，满足时卸载、重跑LoadMW、从头再试；达到7次则Max retries退出。
- `556c` 的step0x40允许其他错误继续。step5 flags0x62、step23 flags0x66都含此位，step6的0x192不含；不能把24项均描述成强制成功门槛，或把全部错误吞掉。
- `5220–5230` 才确认遍历到index23并到 `568c`。此处读取P[39]和stack+34／38；普通 loaded=1时选择return0，未loaded保留模式／状态结果，`5714`交回调用方。

三个容易混淆的 return0：

| 结果 | 必须附带的路径证据 |
| --- | --- |
| 入口复用成功 | `0x2a3054e64–4e70` 若P[39] bit0原本已设，直接return0；未重做初始化或24步 |
| DL-only／失败后继续DL | 仅原能力与flags、特定错误组合可进；不代表普通 SE 生命周期完成 |
| 新普通 LoadStack 成功 | 从未loaded进入、真实初始 callback成功、LoadMW提交loaded，按原条件完成／跳过／容错全部24项，最终正常返回0 |

step6枚举 return0也须查看实际结果：GetSecureElementList读Lib缓存，可只含Host；旧eSE缺失可清理旧对象后仍返回0。应另保留P内部context+210 eSE对象、真实record／state以及移除恢复证据，见[eSE电源／枚举](comet_ese_power_enumeration_20261023.md)。

## 可用于验收的分层判据

| 层级 | 实际应核对 | 不能替代它的局部结果 |
| --- | --- | --- |
| init完成 | 当前profile条件成立，正常pending链消费并清除17d8/e0，原status0交到PN等待对象 | event75被调用、某函数名含Complete |
| MW已加载 | 等待结果成功、后置分支成立、P[39]由本次提交 | cond_signal、callback0、旧loaded |
| 新普通LoadStack成功 | 本次正常MW链及24步原条件／错误政策后正常return0 | DL-only、入口复用、仅step6成功 |
| eSE控制面完成 | 真实eSE对象／record、child Session／pipe、mode／EoOp、重发现和后置SE状态一致 | Host非空、VerifySEStatus通过、四事件函数return0 |
| eSE数据可用 | 真实已建立端点的数据请求／响应、错误／超时／移除恢复得到验证 | 初始化callback、loaded或LoadStack0 |
| Wallet／支付 | 后续真实可信SE能力及Wallet端到端验证 | 前述任何单项局部成功 |

同日后续已展开82／87／93／98及record／PN对象生命周期，见[后续整合](comet_se_post_init_closure_20261023.md)。遗留边界仍包括各自然profile完整模式／数据事务和真实运行证据；没有实现后端、执行原库或制造成功trace。
