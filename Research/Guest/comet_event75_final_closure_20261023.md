# 23G90 Comet：event75、初始 callback 与 LoadStack 静态闭环

2026-10-23；按本轮要求离线分析，不执行 Comet／HAL／后端，不启动或挂载目标 VM，不改系统、不绕过门槛、不绑卡。没有新增产品实验代码；不增加未使用宏。后续实现仍须独立编译宏隔离、默认关闭。

## 本轮补齐的缺口

**event75 到原初始化 callback 的状态表路由已证明；普通 LoadStack 最终返回的外层条件也已接上。** 这是同版机器码的静态控制流闭合，没有原生运行成功 trace，也没有证明 vphone 的 eSE 或 Wallet 已可用。

这里的 event75／76 是十六进制内部事件 `0x75/0x76`（十进制117／118），不是 NCI opcode。前轮未证的关键点在于：初始化 pending 时 current 仍为 Idle1，target3 另存；所以完成事件先查 Idle 表，不能凭“Init”函数名跳接到 state3 的完成函数。

配套完整证据：[12状态路由与表项](comet_event75_state_routing_20261023.md)、[callback 注册与消费](comet_init_callback_contract_20261023.md)、[child／SE／PN548 最终判据](comet_final_success_predicates_20261023.md)。前置 HCI 契约见[上轮整合](comet_hci_minimum_closure_20261023.md)。字段偏移和事件数值均为十六进制。

## 正常初始化的完整静态路线

L 为 Comet Lib context；S 为独立主状态记录；P 为 PN548 handle；W 为 PN callback 等待对象。以下以 driver/type 正确映射、普通配置驱动已到 Idle1、从未 loaded 开始为前提。

| 阶段 | 本版实际动作与继续条件 |
| --- | --- |
| 发起 | PN548 `0x2a3056754` 内调用 Comet `Mgt_Initialize 0x2a2f74ee8`，传 callback `0x2a3056940`、context W；Comet 参数和 busy 校验须先通过 |
| event05 | Idle 表行 `0x2b14914a0` 为 event05／next3／`SM_InitTrans 0x2a2f5d2fc`；返回 pending0d 时只保存 S.target=3、pending=1、saved_event=5，**current仍1** |
| 注册 | 原 API 仅收到 pending0d 后保存 callback至 L+17d8、user至 L+17e0；其它同步返回不承诺这个异步 callback |
| 前序完成 | 当前 profile 的 NFCC 配置、NFCEE／HCI及自然选中的 child／Session／pipe／重初始化均完成，静态收尾和 VerifySEStatus 通过；详见下节 |
| 派75 | `staticFeatureCfgComplete 0x2a2f57ac8` 在 `57d80–57d98` 派 `(driver,75,status0,extra,context)` |
| 选择 consumer | 主 dispatcher 按 **current1** 查 Idle 表 `0x2b1491470`，75行 `0x2b1491510` 指向 **IdleTransComplete 0x2a2f5e59c** |
| 恢复事务 | `MainStateHandler 02c30–02c40` 提交 target3、清 pending，把送给 handler 的 event 恢复为原05；status仍为输入0 |
| 原始 callback | Idle consumer 按 event05读取 L+17d8／17e0，**先清两槽**，再于 `5e904` 调 `(driver,user,status0)`；不是 state3 `InitTransComplete` 的 RawCtrlMsg callback |
| PN 等待完成 | `0x2a3056940` 保留原 status，交 `0x2a304ee00`；mutex 内写 W结果并 signal，等待器辨别未完成 sentinel、超时和实际结果 |
| MW 提交 | LoadMW 收到成功结果后仍有后置检查；正常 `0x2a30560d8–60e0` 才提交 P[39]=1、返回0 |
| 外层成功 | LoadStack 按原能力、flags和错误政策处理24项，遍历到 index23 后走普通 loaded=1 正常返回0；不能以入口旧 loaded 或 DL-only 返回替代 |

主状态表按 state*16 取表、再逐行扫描 event，行stride16并以cf结束。75行磁盘 next初值1会被运行时 target3改写；不能将磁盘初值当固定完成目标。当前状态、pending和callback均是运行时前提，本轮没有从磁盘表推断 guest 的实际状态。

callback 先清槽，只证明该 consumer 对同一保存槽的一次性消费；未证明全局并发／重入安全。错误消费者 `InvokePendingCb` 另有调用后清槽顺序，不能一概称全局严格一次。

## HCI child 与 eSE 的必要条件

`HciInitComplete` 更新 L[172]=2之后，仍可能启动 eSE／SE2／UICC child；LaunchChild 设置重试10、delay100、activeSE和初始化状态。`NfceeInitializeComplete` 也可能继续其它 child或eSE重初始化，不等于最终 API完成。

| 检查 | 本版条件及不能省略的状态 |
| --- | --- |
| 连接／admin | 真实 NFCEE对象、动态 ConnID／MPS／credit、admin OPEN、allow-list和pipe通知登记；status0而无active记录不能算完成 |
| Session | 按当前 SE读取 A0EB／A0EA／A01E，严格8字节；全FF、EoOp和重读计数／delay走真实分支，不能固定返回“已就绪” |
| eSE pipe | 普通profile读取A022／A023并维护K332／K330；静态profile独立。任一pipe ID为FF时实际清A0EB为八FF并置22d，然后禁用／重新发现／重读接口，再完成初始化 |
| 收尾 | 自然选中child完成后进入 SetStandby、DisableESE／UICC／SE2、条件FlushSramData和 VerifySEStatus；输入错误不派成功75 |
| VerifySEStatus | 为软件状态比较。初始callback非空且F=L+1e8为0时直接通过；F非0时s=L[16e]为2通过，s为1要求F.bit1=1，其它s要求该bit=0。callback空时要求 `(s==1)==F.bit1` |

VerifySEStatus 不测压也不验证APDU；它的通过条件允许特定配置下s=2，因此不能提升为“真实eSE已连接”。详细命令、长度、状态变化与失败路径保留在专项报告中。

**初始 callback 在四个 SE 内部事件之前发生。** `staticFeatureCfgComplete` 看到主SM返回0后才调用 `SM_SE_Initialize 0x2a2f6b5b0`；后者顺序派82／87／93／98进入SE子状态机，不检查四次返回值，固定返回0。其 return0不能证明四个事件各自成功。同日后续[四事件与对象生命周期研究](comet_se_post_init_closure_20261023.md)已展开此缺口：四事件仅同步软件归一，不发起新的NCI初始化，eSE控制面验收仍须保留真实对象和数据证据。

## 失败路由与 LoadStack 容错

event76同样在正常 pending初始化的Idle表选择 consumer，并恢复原event05；清pending但不在该分支提交current3，对原event05另记target0c。输入错误原样交初始化 callback；没有证据把局部89自动转换成PN548的43。缺表的特殊分支甚至可返回0却无callback，所以观察SM返回0本身不够。

PN等待对象的未完成值为 `0x00000badcafef00d`；signal只负责唤醒，必须核对结果。LoadMW的43分支至多3次eSE power-on重试，不代表其它错误也会重试成功。

LoadStack表 `0x2b2414540` 共24项、stride24。它使用进入步骤前的loaded快照；step0／1的flags106、step6的192含100，仍可执行。step含80且返回0d时走卸载／重跑MW，至多7次；含40的步骤可忽略其它错误。step5 flags62、step23 flags66含忽略位，step6 flags192没有。最终成功要求遵守这些原分支，不是机械要求24个函数全部返回0。

## 分层验收与剩余边界

| 可以提出的结论 | 至少要保留的证据 |
| --- | --- |
| 初始 init 成功 | 普通pending链、真实前置状态、17d8槽被消费、原status0进入PN等待对象 |
| 本次 MW loaded | 等待结果成功、后置检查通过、本次提交P[39]，排除旧值 |
| 本次普通 LoadStack 成功 | 前述MW链及全部步骤的实际执行／跳过／容错路径、最终正常return0；排除入口复用和DL-only |
| eSE控制面完成 | 真实eSE对象／record、child／Session／pipe／连接／credit、mode／EoOp、重发现及后置SE状态一致 |
| eSE数据可用 | 自有测试端点的真实数据请求／响应及错误、超时、移除恢复；本轮未执行 |

GetSEList可只含Host，枚举发现eSE失踪后也可能清旧对象并return0；还须检查P内部context+210的真实eSE对象和状态。LoadStack0、列表非空、callback0均不能独立证明eSE数据可用，更不证明SE内应用／密钥、可信支付身份或Wallet绑卡。

同日后续已离线展开82／87／93／98的SE子表及对象生成／移除路径，见上述后续研究；剩余可聚焦SetMode到APDU模式及一笔数据事务的完整完成条件。实现后端与取得原库运行trace仍是之后独立工作。

## 原始证据与检查范围

对象为23G90 IPSW原版Comet，UUID `AAD82B14-9985-3582-9A57-22047E668A31`、source366.9.1.0.0；重建库SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`，原textSHA256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。这是IPSW源文件身份，不冒充本次guest部署核对。

为独立核对缺失的目录字节，本轮从已有同版IPSW临时提取arm64e DSC。新读496B主状态目录、32B Idle75／76行，以及原AUTH／DIRTY data；12主状态458行全部与原DSC逐字一致。目录SHA256 `5f4d58d4b203678b123481a7f926f42f64100fc4445f1573c1534eeb6a67cd55`；encoded指针低34位格式经MCP核对[Apple官方fixup-chains.h](https://raw.githubusercontent.com/apple-oss-distributions/dyld/main/include/mach-o/fixup-chains.h)，实际状态语义来自本版指令。

证据保留于Git忽略目录 `.build/validation/comet-event75-20261023/`，包括原始小段、反汇编、全表和静态比对JSON。临时大DSC完成检查后删除，提取工具的临时DMG已卸载／清理；目标Disk.img的size／mtime／ctime与分析前一致。完成文档链接、空白和原始表项检查；没有产品构建／运行测试，因为本轮只增加研究文档。
