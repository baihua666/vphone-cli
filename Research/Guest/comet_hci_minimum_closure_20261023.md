# 23G90 Comet：HCI child、连接和最小无 RF 完成条件

2026-10-23；本轮继续离线读取现有同版证据，未执行Comet、HAL、VM或后端，未修改系统、门槛或银行卡状态。用户新增的宏要求已写入根AGENTS与架构规范；本文仅研究，不新增空的产品宏，也不表示已实现实验后端。

## 结论

**HCI控制面已进一步收敛到实际连接、HCP/admin pipe、Session及child完成条件；尚不能宣称原生LoadStack或eSE会话运行通过。** 完整实现仍须维护真实的连接、credit、pipe、Session、通知与恢复状态，并验证当前profile的原生异步完成，而非把若干请求配上固定成功响应。

细表：[逻辑连接与credit](comet_hci_connections_20261023.md)、[HCP与admin pipe](comet_hci_admin_pipe_20261023.md)、[child／Session与完成](comet_hci_child_completion_20261023.md)。前轮[routing／NFCEE到LoadStack](comet_nfcee_loadstack_closure_20261023.md)及[配置／CRC](comet_no_rf_loadstack_commands_20261023.md)为前置契约。

对象仍为23G90 IPSW原版Comet：UUID `AAD82B14-9985-3582-9A57-22047E668A31`，source `366.9.1.0.0`，重建库SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。复用此前已逐字比较的原始text及六个data／const／stub段，没有重新解包大DSC或读取guest库冒充部署核对。VA与方法边界以子报告定向字节为准。

## 分层命令与响应

下列NCI帧省略可选transport CRC。HCP是NCI DATA中的载荷，不能把它的指令号当成NCI control OID；HCP的final bit也不同于外层NCI PBF。

| 层／操作 | 本版恢复的格式 | 响应及完成要求 |
| --- | --- | --- |
| 创建HCI逻辑连接 | `20 04 06 03 01 01 02 ID 01`；destination3、count1、TLV `01 02 ID 01` | 正常RSP字段status、MPS、credits、动态connID；保存连接活跃状态和NFCEE关联。不能按其它规范版本把destination改成2 |
| NCI DATA | `CID/PBF 00 len HCP...`，MT0；按保存的MPS分片 | ConnID按已连接的NFCEE查找，发送受credit限制；CID不是NFCEE ID，也不是HCI pipe |
| credit通知 | `60 06 len ...` | 更新连接credit并唤醒待发；0 credit需等待与超时，不可无限发送。多pair边界以连接报告的实际实现限制为准 |
| HCP头 | byte0=`pipe | (final<<7)`；byte1=`instruction | (messageType<<6)` | messageType区分command/event/response；请求与响应按pipe和注册的callback匹配 |
| 打开admin pipe | HCP `81 03`：pipe1、final1、command OPEN_PIPE | ANY_OK为response type2／instruction0，即无参数时HCP `81 80`；成功RSP与后续pipe状态须一致 |
| admin allow list | HCI SET_PARAMETER，register3、admin pipe1 | 值与允许的host来自当前上下文；失败不能由日志“create pipe”掩盖 |
| pipe创建通知 | ADM_NOTIFY_PIPE_CREATED，instruction12 | 本版精确5B载荷消费host@0、gate@3、pipe@4；由通知建立端点／注册，不能据日志认定发送过CREATE_PIPE |
| eSE Session查询 | `20 03 03 01 A0 EB`；UICC用A0EA，SE2用A01E | CORE_GET_CONFIG正常RSP含对应参数、精确8B值；全ff是未取得Session，不是HCI admin GET_PARAMETER |
| eSE pipe状态 | 原分支CORE_GET_CONFIG读取A022/A023 | value长度均1；与保存的连接／APDU pipe记录一致。部分平台另走静态pipe分支 |

逻辑连接响应的本地parser存在宽松／特殊错误路径，可能返回0却未建立active记录；因此验收还须检查记录、MPS、credit与动态ID，而非仅API返回值。关闭、数据分片与credit的具体边界见连接报告，不用一条示例请求覆盖所有恢复分支。

`HciOpenAdmPipe`调用OpenPipe(pipe1)，没有由这条初始化路径发送CREATE_PIPE的证据。HCI GET_PARAMETER原语确实存在，但已定位的直接调用用于eSE ATR；不能把NCI Session查询挪到HCI层，也不能从通用HCI库存在某API推断本版child初始化必调它。

## HCI child与Session的实际状态要求

LaunchChildDeviceSequence按当前SE类型选择表，设置delay100、重试计数10、activeSE及child初始化状态。HCI网络初始化与eSE child是不同sequence，仍受原平台、接口、对象及通知状态控制，不是所有profile共用一条固定报文trace。

eSE child包含ClearEseSessionID的条件分支：连接／APDU pipe记录缺失时清Session配置为8字节ff，成功后置重初始化标志；NfceeInitializeComplete据此转到eSE重新发现／初始化序列，完成后再清标志。这是实际状态变更，不是只读Session查询；本轮没有执行清除操作。

Session验证将选中的8B值与全ff比较；满足后更新对应flag与等待状态，否则维持原计数／delay重读。Session有效、EoOp和pipe状态共同影响等待完成，不能给三者随意填同一个“已就绪”布尔值。Session值也不证明支付身份或银行卡个性化。

GetSEPipeStatus的eSE普通分支读取A022/A023：值1分别形成内部记录`4116`、`f019`，值0写`ffff`；前者关系到连接pipe，后者关系到APDU pipe。它们是内部压缩记录，不是两条NCI opcode，也不能未经字段编码核对就把16位值原样发送。平台bb0有独立静态pipe分支。

`HciInitComplete`成功更新HCI状态，`NfceeInitializeComplete`仍可继续child、eSE重初始化或StaticListenModeRouting。最终静态收尾还涉及standby、模式禁用、条件flush及VerifySEStatus。前轮已明确逻辑禁用与物理断电不同，记录软件状态通过不能当作硬件测压通过。

## 最终callback与LoadStack成功判据

父任务保存的`integration/final-init-callback.txt`定位了两个不同的callback槽，不能因方法名含Init而混接：

- `SM_Main_InitTransComplete @0x2a2f11ebc`中`0x12054–120c4`消费并清空的是`L+1aa8/1ab0`。
- `SM_Main_IdleTransComplete`的`0x5e7a4–5e7b4`读取并清空`L+17d8/17e0`，再于`0x5e8f8–5e904`以handle、原context、status调用该callback。
- `staticFeatureCfgComplete`成功会派内部event75；Release失败派76。后续[同日路由恢复](comet_event75_final_closure_20261023.md)已证明正常Idle1／pending event05经75／76恢复原05并到初始callback；这是条件可达性，不是任意75均成功。
- `SM_SE_Initialize @0x2a2f6b5b0`另按常量表依次派四个内部事件；它们不是线上NCI命令，不作为缺失wire响应的替代品。

PN548的LoadMW callback `0x2a3056940`把原status交等待对象。正常LoadMW可在`0x2a30560e0`先置handle+39的isLoaded，然后LoadStack才执行后续24步。原入口若已经loaded也可直接返回0；step6枚举可以只协调Host／清理失踪eSE而成功。这些事实都不等于eSE APDU已可用。

因此最小验收至少要分别保留以下证据：

| 验收层 | 必须看到的实际状态 |
| --- | --- |
| 控制器初始化 | 原profile要求的FW／CRC／配置、routing／mapping与NFCEE通知均按契约完成 |
| HCI网络 | 连接活跃、动态ConnID/MPS/credits有效、admin pipe及允许host／通知状态一致 |
| eSE child | eSE record存在；Session与连接／APDU pipe有效；EoOp、等待和可能的重新初始化完成 |
| 原生LoadStack | 原init callback实际完成；PN关键后续步骤和正常返回路径成立，未以已有loaded或DL-only代替 |
| eSE数据可用 | 对真实已建立的端点执行自有测试事务并验证超时／移除恢复；本轮没有执行这一级 |

当前可以据此实现与验证独立无RF协议模型，但仍缺真实模型／前端实现、原库运行证据及部分SE子状态和恢复分支。主状态event75缺口已由后续同日研究补齐，见上述链接。**本轮交付是恢复出的契约和完成条件，不是已经跑通的控制器／eSE／Wallet闭环。**

## 宏隔离要求与验证范围

以后实现NFCC／SE后端或Wallet实验时，必须按[编译开关规范](../../Documents/Guides/architecture-boundaries.md#定制与实验功能的编译开关)设置独立具名实验条件，在所属target既有构建配置集中定义、默认关闭，并隔离实现与窄组装入口。关闭后不注册实验服务或修改系统，基础路径可用；涉及已部署补丁另需恢复原始输入／重建部署，不因删宏自动回退。

本轮没有新增产品开关定义、源码实现、固件补丁、测试服务器或App。研究证据在`.build/validation/comet-hci-20261023/`，为定向字节、表和布局检查；未执行Apple parser／原生栈或发送控制器命令。前轮原版身份与小段证据继续复用，没有重新生成大缓存。
