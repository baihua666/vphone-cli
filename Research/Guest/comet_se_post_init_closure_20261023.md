# 23G90 Comet：后置SE四事件与真实eSE对象的完成边界

2026-10-23；继续离线追踪同版23G90。只读保留的Comet／PN548、反汇编及原DSC小段；未执行库／HAL／VM／后端，未挂载目标实例、改系统、绕过门槛或绑卡。没有新增产品实验代码或宏；后续实现仍须独立编译宏隔离、默认关闭。

## 本轮结论

**初始callback之后的 `82／87／93／98` 并不缺一轮线上初始化协议：它们只同步归一软件SE子状态。** 真实eSE来源仍是之前的NFCEE发现、Lib建档、HCI child与Session／pipe；PN548随后通过GetList快照建立自己的对象。这四个事件既不创建NFCEE硬件，也不直接生成PN对象，更不验证APDU响应。

所有事件、字段偏移及短状态值均为十六进制。配套：[四事件及6张状态表](comet_se_post_init_routing_20261023.md)、[Comet record生命周期](comet_se_record_lifecycle_20261023.md)、[PN548对象与就绪检查](pn548_ese_ready_lifecycle_20261023.md)。前轮[主callback与LoadStack路线](comet_event75_final_closure_20261023.md)继续有效。

本轮还更正两处旧分析误读：eSE的NFCEE ID实际为 **c0**，不是80；PN枚举中的removed恢复失败并不直接返回1，而可继续到return0。旧发现／供电／整合／child报告已就地注明纠正及新证据。

## 四事件的完整最小软件契约

初始callback已经在 `IdleTransComplete` 同步调用并清槽；`staticFeatureCfgComplete 57da0` 才继续调用 `SM_SE_Initialize 6b5b0`。后者传status0顺序派四事件，不检查返回值，固定返回0。

每NFCC主记录S下有四个独立SE记录 `R_k=S+10+k*10`，含current／target／pending／saved_event。`SM_SEStateHandler 916d0`按所选记录current查目录 `2ae0f7ed8+current*16+8`，再线性扫描event。合法current0..5的**6表、98行（含终止行）**已经与保留原DSC逐字核对，并由父任务独立重复读取验证。

| event／记录 | handler | status0下的实际行为 |
| --- | --- | --- |
| 82／通用Host槽k0 | CommonTrans `5f0f0` | 仅日志，返回输入0，由dispatcher提交软件current1 |
| 87／eSE槽k1 | eSEInitTrans `675d4` | 读L[16e]：1→返回0并提交current1；2→直接置current5后返回d6；其它值／无L→ff |
| 93／UICC槽k2 | UiccInitTrans `67680` | 同上，改读L[16d]、设置k2 |
| 98／SE2槽k3 | SE2InitTrans `6772c` | 同上，改读L[16f]、设置k3 |

状态1对应模式转换日志中的 **Off**，5为 **Removed**；Off不是测得的物理断电，更不是Apdu状态3。值3也不被后三个init handler当作connected接受。ff不提交row.next，保留原current；d6保留handler已经写入的Removed5。

主S.pending为1或任意SE记录pending为1时，这四事件可被busy6f拒绝；正常初始化75已清主pending，但callback重入后的运行状态不能由静态代码假定。即使某项返回6f／d6／ff，6b5b0仍处理下一项并返回0；没有在此链改写已经发出的初始callback。四个init handler均不发NCI、注册timer或返回pending0d，不能把通用异步FSM分支套成这四项必须等待的响应。

## 真实record如何接到软件状态与PN对象

```text
NFCEE_DISCOVER_NTF：eSE ID c0
  → NCI内嵌record R（记录ID、active及协议/TLV）
  → UpdateSeInfo登记Lib：L1b8=R、L16e=1、列表type1
  → 当前profile的HCI child／Session／pipe／收尾
  → event75 → 初始callback → event87归一eSE软件FSM

PN548 GetList读取Lib快照
  → type1条目 → 建立/重配PN对象 → 存入内部context+210
  → 独立的模式、移除、OS策略和数据事务处理
```

图中是静态数据依赖，不表示所有节点在单一线程按图顺序完成。四事件自身不写Lib列表、不通知PN建对象；连接点是后续GetList读取的同一份Lib记录。PN等待唤醒与后置事件之间的线程先后，须按专项队列分析及真实trace分别确认，不能据此臆造必然竞态或全局完成屏障。

| 表示层 | 已证字段／含义 | 不能混为同一件事 |
| --- | --- | --- |
| NCI记录 | `R=N+f80+i*68`，R[1]为ID；wire status0→u32(R+4)=1，status1→0 | R+4的active、wire状态数字与Lib枚举不是同一编码 |
| Lib发现状态 | connected c0按初始化门槛写L[16e]=1，并保存L+1b8=R、L+1c0=type1、L+1c4=(R+4!=1) | L16e=1只被event87用来归一软件Off，不证明wired APDU已建立 |
| 移除状态 | removed c0置L16e=2、清L228、两eSE pipe ID=ff；L1b8仍可非空 | 非空Comet handle不能证明当前未移除 |
| SE软件FSM | 独立全局R_k.current：1Off／5Removed等 | 不等于Lib L16e或PN对象字段，也不创建真实record |
| PN对象 | type1列表条目经creator创建／重配，保存于PN内部context+210 | 指针存在、对象字段有效、未移除和数据可用应分开验收 |

NCI正常建档会先将R[0]置ff；不能以此单字节认定无记录。R是NCI context内嵌数组，L1b8是借用指针；StartDiscovery调用的ReleaseNfceeCntx只释放记录TLV并清该指针，未清ID／count或释放整个R。完整free(N)才使内嵌R随owner失效。发现重用／全NCI释放后，旧借用指针及PN对象里的句柄必须按真实所有者生命周期协调，不能用同一地址或残留非空值当代际有效性证明。

## 本轮纠正的两个判据陷阱

**ID误读：** `UpdateSeInfo 0695c`读取ID，`06960 cmp80/b.gt`仅分流；eSE最终匹配在`06a9c cmpc0`，removed亦在`06a20 cmpc0`。80不命中eSE分支。本版系统EoOp通知也出现c0，但不同通知的载荷格式仍须各自遵守，不能只替换一个常数就算协议闭合。

**枚举恢复失败被外层容忍：** PN在`0x2a306f698/6ac`调用off→on并以返回bit0判错；失败路径记录日志，`0x2a306f7ec`仍跳到`0x2a306f890`继续循环，最终可在`0x2a306fb44`返回0。只有成功分支在`0x2a306f88c`清object+18的removed标志。因此“step6=0且eSE指针非空”仍可能对应removed对象。

`NFDriverIsSecureElementEnumerated 0x2a3072fcc`对eSE仅检查context+210非NULL，不查removed或OS。`IsOSReady`也不是统一硬件探针：wrapper的对象函数槽为空可直接返回true；另一creator绑定的Eos判断读取软件OS模式缓存，默认值也存在允许继续的路径。具体型号绑定及API条件见PN专项，不能把这些谓词的true当成SE内操作成功。

## 最小验收应保留哪些证据

| 层级 | 最小观测要求 |
| --- | --- |
| 发现／建档 | 本版c0正常通知被原parser接受；真实NCI record及Lib entry对应、字段／count正确；Host合成条目另计 |
| child控制面 | 当前profile所需连接、credit、Session、pipe、EoOp、重发现完成；未用固定status0代替状态演进 |
| 后置归一 | 分别记录87的输入L16e、SM返回值和eSE槽current；不能只采集6b5b0的0 |
| PN协调 | type1真实条目与context+210对象关联；检查removed及模式；列表缺失、恢复失败、重新出现和卸载释放结果一致 |
| 数据可用 | 通过原模式转换和数据入口，在自有测试端点取得请求／响应完成；验证超时、credit及移除恢复；本轮未执行 |

到这里，无RF启动协议不需要为82／87／93／98额外编造四条线上命令。仍需真实实现前置NFCC／HCI／SE状态及数据端点；单纯填record、强制Off／Apdu或强制API返回true不能当作原生验证。

同日后续已完成[SetMode到普通APDU最终callback的离线契约](comet_apdu_minimum_contract_20261023.md)，列出自然profile下的模式路径、DATA event、credit、完成通知、超时与移除收尾，以及兼容前端／宿主SE后端的责任。仍无实际数据事务运行证据；无需再把这四个同步事件当成未实现的异步初始化序列。

## 来源、验证与宏边界

Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`、重建库SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；原text与重建逐字一致，SHA256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。PN548保留副本UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`、SHA256 `4960bb6a3c44fabd86c6b045aa6049b2047eca2dbb53ba3ab13026522e1ed220`；使用已修正import stub的定向反汇编。本轮未重新读取guest文件冒充部署身份核对。

encoded指针的低34位runtimeOffset经MCP复核[Apple官方定义](https://raw.githubusercontent.com/apple-oss-distributions/dyld/main/include/mach-o/fixup-chains.h)，具体路由和状态语义只取本版字节。证据在Git忽略目录 `.build/validation/comet-se-post-init-20261023/`：96B原SE目录、全表／独立比对、函数摘录及两项纠正的精确分支，目录0700／文件0600；没有生成新大DSC。

本轮只改研究文档，不改产品、版本、补丁、默认开关或VM数据；不为离线取证增加空宏。未来实验代码仍遵守[具名编译开关规则](../../Documents/Guides/architecture-boundaries.md#定制与实验功能的编译开关)，默认关闭、独立模块与窄组装入口，开启／关闭分别验收。静态比对通过不等于原库、APDU或Wallet运行成功。
