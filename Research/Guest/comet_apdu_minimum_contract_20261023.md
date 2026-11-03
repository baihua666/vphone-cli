# 23G90 Comet：SetMode到一笔APDU最终callback的最小无RF契约

2026-10-23；本轮继续离线分析同版23G90保留副本。未执行Apple库／HAL／后端，未启动或挂载VM，未改系统、绕过门槛或绑卡。没有新增产品实验代码或开关；未来实验实现仍须独立宏隔离、默认关闭。

## 结论与范围

**普通eSE路径已接通静态调用链：模式转换→HCP DATA event→动态CID／credit传输→同pipe数据event→Comet最终consumer→PN等待对象→响应bytes。** 这补齐接口需求，不代表现有vphone已经实现SE后端或实际完成APDU往返。

此前的event75／后置event87只到初始化callback和软件Off状态；本轮明确进入Apdu、发送、WTX延期、数据最终callback与应用结果是不同阶段。不能用固定status0、HCI ANY_OK或只造一份SE列表代替完整事务。

专项证据：[SetMode契约](comet_apdu_modeset_contract_20261023.md)、[Comet数据与callback](comet_apdu_data_callback_contract_20261023.md)、[transport／credit／恢复](comet_apdu_transport_recovery_contract_20261023.md)、[PN等待与WTX](pn548_apdu_wait_callback_20261023.md)。前置：[record与PN对象生命周期](comet_se_post_init_closure_20261023.md)。除特别注明，字段、event和状态数值均十六进制，VA为本版未滑动地址。

后续已收敛为[最小无RF原型方案](nfc_no_rf_minimum_prototype_plan_20261023.md)：先验证宿主子集模型＋真实jCardSim APDU，再证明原Comet transport接入；分别列出代码复用、缺失接口、宏及逐层验收。该方案尚未实现或运行，不改变本文静态契约的证据等级。

## 模式路径：先分清五套数值

| 层 | 本轮普通eSE wired／APDU值 |
| --- | --- |
| PN配置 | routing期望1，经SetPower／SetConfiguration路径进入SetSEMode |
| Comet API | mode2，SE type1，要求真实已匹配record handle |
| 内部event | 8c，不能当线上opcode |
| SE子状态 | target3=Apdu；pending期间仍保留原current |
| NFCEE线上模式 | full路径发送mode1，不能照抄API mode2 |

从Off／PwrOff等原状态进入full表 `2b17beb98`：SetPower→SetMode→SERecoveryGetPipeStatus→Complete。Virtual／已Apdu存在原profile的同步优化及power-only表 `2b17bec08`，不是每次必发所有包，也不能为了少实现包而改型号flags。

| 操作／条件 | 实际命令或字段 | 合法回应与推进条件 |
| --- | --- | --- |
| 未命中跳步的standby | `2f 00 01 00`；API2已清L[1]，desired=L[1]&L[2] | `4f 00 01 status`，payload恰1；0成功，f1→51，bd保留，其它ff；成功后更新缓存 |
| full NFCEE enable | `22 01 02 ID 01`，ID来自当前record，本版eSE为c0 | `42 01 01 status`；0后仍可能等待NTF／timer，f1→51，其它ff |
| 普通enable完成通知 | 私有 `7f 20 len [ID,result,...]`，至少2个payload字节 | 待定callback、RSP门控、record ID及mode条件匹配才完成；result是独立数据字段，不是NCI status |
| 条件pipe查询 | `20 03 05 02 A0 22 A0 23` | GET_CONFIG的status／count／存在位与两TLV；value长度各1，值1恢复相应pipe、0标删除。静态profile另走原表 |
| 模式完成 | 内部a4／a5恢复原8c；成功提交target3 | pending事务消费1a18／1a20并调用五参 `(driver,user,handle,result,status)`；同步0不注册该异步callback，由PN block自行完成等待结果 |

模式有两个不能省略的边界：ModeSet的RSP0不是最终模式callback；而特定真实平台flags未命中时，等待NTF的兼容timer到期又可能以status0／NULL data推进。成功来源必须区分真实匹配NTF、同步缓存优化和兼容timer。模式callback0也不证明pipe／SE应用可用。

## 普通APDU的请求与回应

API `phLibNfc_eSE_Transceive 2a2f79e2c`要求当前Lib／handle／transferInfo／callback有效，并检查busy、恢复与下载等门控。普通type1按原模式与transfer字段选择8d或8e；二者都可进入普通 `eSETransceiveTrans 684e0`。**8e不等于真正的HCP raw事务**；8f及下载BA属于独立分支，不能拿来代替本轮普通链。

普通send `HciDataSend 99c58`调用 `SendEvent 9a054`，实际为type1、instruction10。令c为已关联动态CID低4位，p为当前有效APDU pipe，n为APDU字节数；以下仅示意可容纳于单HCP／NCI片的形状，不含可选CRC：

```text
请求：c 00 (2+n)  (80|p) 50 <C-APDU bytes>
回应：c 00 (2+m)  (80|p) 50 <R-APDU bytes>
```

`50=(type1<<6)|ins10`。普通R-APDU也是同pipe的 **DATA event**；不是type2 ANY_OK。正常响应须走已注册CID、HCP重组、pipe／type／ins匹配及当前pending事务；任意DATA、错误pipe或type2“成功”均不构成普通APDU完成。

| 阶段 | 本版必须维护的状态 |
| --- | --- |
| 数据准备 | 发送ptr／len、接收ptr／capacity、真实SE handle、pipe及回调槽；不能只保存请求bytes而丢失接收容量 |
| HCP分片 | payload≤253时首片含2字节头；更长首片253、续片最多254，仅首片带type／ins；final bit7独立维护 |
| NCI分片 | 每个HCP片按连接MPS再切，头为 `[c|(more?10:0),00,len]`；PBF bit4和HCP final不是同一标志 |
| 发送credit | 只在查询成功且额度非0时直接发送；每实际提交一个NCI DATA片、TML返回pending0d后扣一份credit；ff在当前减法路径也会减为fe |
| 补充credit | 单pair合法 `60 06 03 01 CID delta`；CID必须与活跃连接及等待者关联，净额度0不是恢复发送 |
| 接收 | CRC／NCI长度及PBF重组后按CID投递，再按HCP pipe重组、type／ins和事务匹配；发送callback0并未带R-APDU |

本版credit多pair循环未见按pair推进，不能按其它实现假定能正确处理多个CID；最小候选应先明确单pair契约。当前特殊credit算式也不是通用饱和加法，不能误写成ff无限额度或任意溢出饱和。

## 最终callback与超时必须分别判断

普通Comet consumer先读取并清18c8／18d0，再调用六参 `(driver,user,0,&L270,L284,status)`；它与模式五参、初始三参以及WTX五参均不同。PN主consumer取x1=user、x3=response、w5=status；普通status0还要求response非NULL、长度>1，才登记接收长度。否则可变为d00d，不返回有效数据。

PN在等待结果低16位为0、最终NFData建立成功后才交回响应bytes；这仍不是SE应用的SW1／SW2成功判定。接收buffer必须由真实数据路径填写，不能只把status或长度改成成功。局部consumer先清槽不等于所有异常路径都先清槽或全局并发严格一次。

Comet普通接收还要求事务仍busy、DATA非空：长度超过容量给08，空DATA给ff；无接收buffer／容量0的局部分支却可保留status0而不复制，不能由此认定缓冲区有效。最终consumer另有特定24／L2f2条件改status为da的分支。status、实际长度、buffer与最终交出的bytes必须一并核对。

| 等待层 | 本版完成／超时行为及不能替代的条件 |
| --- | --- |
| credit等待 | 保留待发片并等待匹配CID额度；首次timer到期可额外重启1个timer参数单位；最终重查仍无额度时交发送callback内部status9，再进入mux失败路径，不是APDU成功 |
| HCI command响应 | 主要用于type0 command／type2 response；普通DATA event不能凭ANY_OK结束或混用此timer |
| APDU事务等待 | 发送提交pending后即启动独立H348 timer，不等第一段回答；参数优先用u16 L2f4（≥7d0），否则用L280，但`L280>>4<271`时改取2710。超时通常2c，L2f2条件可改da；随后清理、派a5、恢复原操作并消费callback |
| WTX | 普通数据事件11读取首payload字节高4位，按原函数换算timeout、写L2c0／H354；回调五参status4a，H348有效才重启。PN另按该u32重设deadline并消耗WTX预算；WTX不是R-APDU |
| PN总等待 | 原函数起始deadline60秒；WTX按info/1000秒从当前时刻重设deadline，预算初值29a。耗尽可Signal2c；其它总等待超时还有dump／restore／诊断／延长或退出分支，不能统一映射2c |

PN主consumer在等待值已为2c时跳过正常长度登记，但仍有Signal／release动作；本轮不把它称为“所有晚到callback均丢弃”。接口实现仍须按真实pending、超时和移除生命周期撤销旧事务，禁止将旧回应交给另一请求；没有动态验证其所有并发排列。

## 移除与恢复边界

eSE removed c0可以保留非空Lib handle，同时置接口removed、清Session完成flag、使两pipe为ff；PN对象也可仍存在且removed=1。`IsEnumerated`或某些`IsOSReady`的true不覆盖这些失效事实。

当前普通pending事务的移除处理可以进入数据终结并保留内部41／原错误；错误消费者的清槽顺序与正常consumer不同，不能全部概括成相同的一次性保证。PN收到41会重枚举，43有最多3次power-on尝试；它们不等于原请求已经执行成功，亦不授权对任意错误无限重发。

重新发现／重建record／CID／pipe、恢复Session以及重新枚举PN对象需要协调同一代状态；不能用旧record地址、旧credit或旧数据片继续下一事务。尚未穷举全部profile、通知乱序、恢复分支与销毁屏障，未声称所有移除都自动发送同一CLOSE命令。

## 兼容前端与宿主SE后端的责任

这里的“前端”指未来向guest原栈呈现Stockholm／NFCC传输契约的一侧；“宿主SE后端”指实际处理SE状态和APDU的端点。它们是责任划分，不代表当前已有这两个模块或透传服务。

| 责任 | 兼容前端承担 | 宿主SE后端承担 |
| --- | --- | --- |
| 字节与控制器协议 | 既有驱动／transport契约、NCI头／CRC、HCP封装、CID／MPS、分片、注册和通知路由 | 接收完整APDU及关联的真实会话，不要求它伪装成NCI parser |
| credit | 按自身可接收容量管理额度、逐片消耗／补充与背压；credit可先于APDU完成 | 提供实际处理／队列状态，让前端保持有界背压；不把APDU完成冒充credit ACK |
| 模式与电源 | 依原profile解释请求、缓存与状态，按实际结果生成对应RSP／NTF并处理timer | 提供真实enable／disable／reset／移除结果及当前SE状态；不能只是无条件返回0 |
| APDU语义 | 透传请求、关联pending和接收容量、按同pipe event返回真实回应 | 执行SE应用／协议、返回R-APDU与SW，维护必要的应用状态；不由前端编造9000或凭据 |
| WTX与等待 | 编码原WTX事件及时间、推进或终止原等待，保留各timer来源 | 仅对真实未完成操作提供可用的延期／结束信息；不能无限WTX替代响应 |
| 移除与恢复 | 撤销失效record／连接／片链／等待关联，通知原栈并协调重枚举 | 终止或报告旧操作、重新提供真实会话能力；恢复后不把旧回应串到新请求 |

无RF可以省去实际射频交换，不能省去本版自然选中的NFCEE／HCI控制面和SE应用执行。真实SE身份、应用、密钥及Wallet后续条件没有由上述协议封装自动产生。本轮没有制造可支付SE或验证绑卡。

## 最小可验证方案与证据范围

后续实验应先在独立测试环境按真实profile验证：

1. 模式同步0和pending0d分别完成；full路径能区分standby、NFCEE RSP、匹配EoOp与兼容timer；最终eSE状态及pipe一致。
2. 一笔自有测试端点APDU，经真实动态CID／pipe返回匹配DATA event；Comet最终status、PN长度、buffer与bytes一致。
3. 超过MPS／HCP阈值的请求和回应正确重组；credit0暂停、匹配单pair恢复，不重复发送或超扣额度。
4. 不回应、无credit、WTX、预算耗尽、错误pipe／type、接收容量不足、移除后晚到数据分别进入原错误／恢复路径；不能只测固定小包成功。
5. 真实部署前验证实验宏开启／关闭：关闭时无实验注册或副作用，基础路径可用。现在只形成验证清单，不新增空宏或模拟成功数据进入产品。

Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`，重建库SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；PN548 UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`、SHA256 `4960bb6a3c44fabd86c6b045aa6049b2047eca2dbb53ba3ab13026522e1ed220`。本轮只核对已有同版副本，不冒充guest运行身份核验。

证据位于Git忽略目录 `.build/validation/comet-apdu-20261023/`，含函数摘录、原序列表、18项相关SE行独立核对、PN原text及9个函数比对、宿主分片算术；没有执行Apple encoder／parser。指针格式经MCP核对[Apple官方定义](https://raw.githubusercontent.com/apple-oss-distributions/dyld/main/include/mach-o/fixup-chains.h)，协议命名另见专项NXP固定源码，全部Apple控制流结论来自本版字节。

本轮未改产品、补丁、版本、宏或VM数据；未新增大DSC、App、服务器或后端。静态调用链闭合与宿主算术检查不等于原生运行成功。未来代码遵守[独立编译宏规范](../../Documents/Guides/architecture-boundaries.md#定制与实验功能的编译开关)，默认关闭并独立验收。
