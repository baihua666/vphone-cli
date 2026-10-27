# 23G90 Comet：APDU transport、分片、credit 与等待恢复契约

2026-10-23；纯离线复核已保留同版字节、函数边界和调用索引。不执行 Apple 库／VM／HAL／后端，不改系统、不绑卡、不解包大 DSC、不写产品实现或空实验宏。没有实测 APDU trace。

## 结论与范围

**普通 APDU 是动态逻辑连接上的 HCP 消息；HCP chaining、NCI PBF、发送 credit 与事务回应是四套相关但独立的状态。** TML 接收发送请求、发送 callback0、credit通知、HCI ANY_OK均不能替代普通 APDU 数据回应。

本报告收敛 transport 到 HCI receive 的连接；[APDU数据／完成回调](comet_apdu_data_callback_contract_20261023.md)负责普通／raw事务、最终 callback与移除／超时；PN最终数据交付由本轮整合报告承接。前置：[动态连接](comet_hci_connections_20261023.md)、[HCP/admin](comet_hci_admin_pipe_20261023.md)、[PN eSE生命周期](pn548_ese_ready_lifecycle_20261023.md)。

来源仍为 Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`，Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；`nfcc-protocol-20261023/user-frames/comet-disass.txt`及既有原始小段。新证据 `.build/validation/comet-apdu-20261023/transport/`（0700／0600）。VA为未滑动地址；短地址省略共同前缀 `0x2a2f`。下文 N=NCI context，Q=N+398的Core context，H=HCI context；所有偏移为十六进制。

## 普通APDU到transport的实际入口

普通 HciDataSend `99c58` 选择实际 multi-OS pipe，必要时回退查gate f0，再调用 HCI Transceive `9a054`，参数 **ins10、messageType1、len=L268、data=L260**。因此合法单包 HCP 形状为 `[80|pipe,50,APDU...]`；pipe来自当前已创建／恢复的表，不应固定为19或任意NFCEE ID。

普通回应也由**同pipe、type1 event、ins10**进入ProcessEvents `9b024`。type2 response `ANY_OK`在普通APDU事务的处理器中仅记unexpected而不完成；详见数据callback专项。HCI command的type2响应timer不能套到此普通event事务。

`HciCoreSend 4bc24` → `SeSendData 29044`，使用 H+318的N、H+320的NFCEE record。`290f8–29104` 调 LogConnGetConnId按record查动态CID；`291e0–291f0` 复制 HCP params 至mux请求+20；`29204–29228` 选择data mux1或原条件下3。mux编号是内部选择，不是线上 opcode。

连接记录 `E_i=N+ec8+i*20` 的 +8=CID、+9=credits、+a=MPS、+10=关联record、+18=active；正常建连RSP提供真实CID/MPS/初始credit。仅某函数返回0可能仍未建立 active record，前置条件见连接报告。

## 两层发送分片与线上字节

当前库先分HCP，再按当前连接MPS分NCI DATA：

| 层／指令证据 | 本版实际编码 |
| --- | --- |
| HCP首片 `429bc`，`42a70–42a88` | byte0=`pipe | (final<<7)`；byte1=`ins | (messageType<<6)`；然后复制本片消息payload |
| HCP续片 `42888`，`42934–42968` | 仅byte0的pipe/final头，随后连续消息payload；不重复ins／type头 |
| 单HCP消息payload≤253 | `0c2ec–0c310` 首片final1；HCP长度为payload+2 |
| 更长消息 | `0c680–0c690` 首片取253、final0；`0c520–0c530` 中间续片最多254、final0；`0c3e0–0c3fc` 最后一续片final1 |
| 每个HCP片进入NCI `42cc0` | `42d90–42da0` 按CID查MPS；`42e00–42e20` 比较当前待发长度与MPS，尚有后续则置NCI byte0 bit4 |
| NCI头／payload `42fd8–43038` | `[CID&0f | (more?10:00),00,本NCI片长,HCP连续字节...]`；每片推进当前HCP片游标／剩余长度 |

HCP final bit7=1表示本HCP消息最后／单片；NCI PBF bit4=1表示当前NCI消息仍有后续片。一个HCP首片可再被多个NCI DATA承载，不能把每个NCI片都额外加一份HCP头。

MPS不是APDU总长度，也不等于HCP的253／254分段阈值。当前GetConnMaxPldSz也有连接／profile字段分支，不能把缺失或0 MPS解释为“无限长”；后端须提供与真实profile一致的有效值。

纯宿主算术例（不是原库执行／真实端点）：260字节普通payload→两个HCP片长255、8；若该连接MPS=64，则NCI payload片长64/64/64/63和8，共五个DATA credit。对应公式与边界算术保存在 `source-derived-arithmetic.json`，不把示例CID／pipe写成实际设备身份。

上述字节不含可选链路CRC；CRC由当前用户态模式另行追加／校验，不能计入NCI头byte2的payload长度或当作HCP数据，见[CRC帧层](pn548_user_frames_crc_20261023.md)。

## 发送credit：何时扣除、何时暂停

`BuildHciNciPkt (0bed8)` 的 `0c018–0c048` 先按CID读credit；只有查询成功且credit非0才进入直接发送分支，其余情况进入等待注册（不能把查询失败视为已有额度）：

- `0c04c–0c068` 注册 CreditsUpdateCB `25da8`，不立即调用TML发送。
- 注册成功 `0c168–0c174` 保存mux／CID至N[1847]/[1848]并返回pending0d，保留待发内容。
- 有额度时才构建DATA并调用 CorePktSendToTml `0d198`。**`0c1c8–0c1ec` 在TML返回pending0d后，每次对data mux调用 DecrConnCredit；control mux2排除。** 即每实际提交一个NCI DATA片消耗一credit，未等到APDU回应才扣。
- DecrConnCredit `3ecf0` 的 `3edc4–3edd8` 只在非零时做byte减1；0返回ff，**ff在这条路径也减为fe**，没有“ff无限额度”特例。

TML pending意味着底层接受异步写入，不等于线缆／控制器确认或APDU事务完成；此时credit已扣，故失败／重试必须依原状态路径推进，不能无条件加回或把同一片重复提交。

## credit NTF与本版多pair边界

本版注册MT3/GID0/OID6；单对合法通知为 **`60 06 03 01 CID delta`**。LogConnNotifCB `881b8` 要求context／wrapper／payload有效、status0、len非0，且当前metadata GID0/OID6。局部未证明 `len>=1+2*count`，建模仍须给完整合法payload。

`88358–883c4` 查P[1]的CID并把P[2]加到连接credit byte；`883d4–883dc`检查的是 `(0xff & ~sum)==0`，命中在 `88494–88498` 改为fe，**不是通用溢出饱和算法**。例如旧254加2先存byte0；旧1加254命中特殊分支存fe。不能只依据日志“limit exceeded”改成标准饱和实现。

本轮定向补齐前轮多pair未知：count来自P[0]，但 `88390–883a0→88358` 只增加循环计数、重读同一wrapper+8，随后仍读P[1]/P[2]，**未见按pair推进payload指针／索引**。因此当前机器码不能支持“count>1会逐对处理不同CID”的假设；本报告仅收敛真实单pair分支，不将其他平台parser套入本版或制造异常包实验。

正常有效非零额度、CID匹配等待者时，`8873c–88820` 停／删credit等待timer、清等待CID为ff、清callback/context，并调用保存callback `(ctx,credit,status)`。通知CID不匹配、连接无效或净额度0不应被当成成功恢复发送。

**delta0并非无条件无操作。** 本版 `8850c–886e8` 依据N1446/N15b6等feature位和CID／状态处理zero-credit通知：可停止等待timer、置N[f59]，或通知上层内部事件13重启HCI命令等待。普通credit增加、EOF timer和这些zero-credit策略是不同分支；不能拿“收到credit NTF”当完成APDU。

## credit等待timer及超时传播

LogConnGetCtxt `88924` 返回 **C=N+1958**。当前单个等待槽：

| C偏移／N地址 | 含义 |
| --- | --- |
| C+9／N1961 | waited CID |
| C+20／N1978 | callback（正常发送为25da8） |
| C+28／N1980 | callback context |
| C+31／N1989 | credit等待相关标志 |
| C+38／N1990 | timer ID |
| C+40／N1998 | timer active标志 |
| N1941 | 首次到期后的额外延期标志 |

`RegForConnCredits 3e318` 先保存CID与callback/context；已有timer则停删。N[f59]==1时 `3e47c–3e48c` 可直接返回0而不创建timer，不能声称每次等待都有相同deadline。

其余路径创建timer并设置时长：N138e/N1446/N15b6任一1时参数1000；否则 N11ae>=251时参数=N11ae−50；再否则按既有record/profile推算，默认参数250（`3e544–3e724`）。这是传给库timer API的数值，不是wire字段；本轮不将未核单位强写成全profile固定毫秒超时。

`WaitCreditTimerCb 3e728` 并非第一次到期就直接失败：

1. `3e810–3e84c` 若N1941==0，停timer后尝试用参数**1**重启同一callback；成功在 `3ea0c` 置1941=1后返回。
2. 后续到期或重启失败在 `3e870–3e8f4` 清标志、匹配并删除timer，取出且清空等待callback/context、waitedCID=ff。
3. `3e8f8–3e944` 重新读N1848所指CID额度；若查询成功且非零，callback `(ctx,credits,0)`，可恢复发送。
4. 否则 `3e948–3e9e8` 停相关NCI响应timer、调用ProcessSpmiRegInfo(N,0)，特殊CID3写N19d4=24，最后callback **`(ctx,0,9)`**，日志名为RF_TIMEOUT。这个9是内部发送失败结果，不是控制器送来的NCI status9。

CreditsUpdateCB `25da8` 仅 `credit!=0 && status==0` 选择mux内部事件2，其他情况选择事件3（`25e88–25eb0`）并进入MuxHandler `0ac9c`；即等待成功与失败各自进入原发送状态机，不直接调用APDU成功callback。credittimer、NCI控制响应timer、HCI command timer与APDU response timer必须分别维护。

## RX：NCI重组、CID分发与HCP重组

本版先验证NCI实际长度=`byte2+3`（`04b20–04b2c`，用户态CRC处理之后）；DATA MT0时 `04c18–04c2c` 保存CID低4位到Q+39c、MT0到Q+390。

CoreRecvChkPbfAndUpdate `0536c` 在 `05418–05444` 读NCI byte0 bit4；PBF1推进接收片链，最后一片再走完成检查。CoreGetDataLength `058a8` 汇总链节点长度并为每节点扣3字节NCI头；CoreRecvManager `033e4–033fc` 单节点直接取payload+3，多节点 `0379c–037d4` 分配并调用059b8汇聚。完整RX状态表／所有跨CID乱序异常本轮未穷举，不把局部PBF检测提升为任意乱序兼容性。

CID路由链已补齐：

1. RegUnRegSeEvent `b7870` 先以NFCEE record查真实CID；`b7ba0–b7bd0` 以MT0／该CID注册 SeEventCb `b7c28`，并在N1240+i20保存record／HCI callback／context。
2. CoreRecvManager `03314–0331c` 从Q+39c取CID；CoreGetIndex `051c4–051dc` 用该CID匹配数据注册。`03698–0370c` 调对应data callback，传剥离头且已重组的payload wrapper与status。
3. SeEventCb `b7ce8–b7d10` 按注册record关联选择HCI callback，将输入status原样传递；HciCoreRecvCB `4b2d8`负责下一层。
4. HciCoreRecvCB `4b3fc–4b43c` 按HCP低7位pipe选择片链；单片长度大于104h拒绝，bit7==0缓存，bit7==1才在 `4b4f0–4b500` 调 ExtractData `878fc`。
5. ExtractData首片去2字节HCP头，续片去1字节；保留pipe、type／ins，并核对实际payload计数。成功后 `4b6c4–4b6d0` 调 ReceiveHandler `9bc6c`，再由实际pipe+messageType路由到事务handler。

所以HCP final=1仍只表示消息组装完成；pipe/type/ins／事务状态必须再匹配，不能把任意DATA或首个final片当APDU回应。HCP重组失败、未注册CID／pipe、错误type都不能提升为成功。

## 发送callback、接收错误与移除边界

SeSendCb `2924c` 保留传入status，释放N11f8发送缓存，清N+e88/e90后在 `292d8–292e0` 调 **`sendCb(ctx,status,NULL)`**。这条路径没有R-APDU。普通HCI发送成功不会因此直接向PN交回数据；发送失败如何进入事务终结由数据callback专项展开。

HciCoreRecvCB收到下层非零status，在 `4b35c–4b37c` 清理接收链并取清H+b8回调，传 `(H+c0,status,NULL)`。它不同于已经收到完整合法HCP消息再匹配APDU事件；不能把下层错误包装成成功的空APDU。

eSE移除、OS-reset、APDU timeout会与保存的pending事务共同清理；本轮不重复数据专项的所有callback槽。transport层必须同步撤销旧record／CID关联、credit等待和分片状态，不能继续使用已经失效的连接；具体“哪些移除分支清哪些槽”以数据专项与前轮生命周期报告为准，尚未证明每一种移除均经过同一自动CLOSE包。

## 最小候选与本轮验证界限

最小无RF候选仍需：真实NFCEE record关联的动态CID/MPS/credit；HCP与NCI双重分片；逐DATA扣credit及相应NTF补充；credit0暂停和原timer／错误分支；NCI重组后按CID投递，再按HCP pipe/type/ins匹配；事务结束／移除时一次性清理原等待与缓存。前端提供字节transport与这些控制状态，宿主后端要给真实数据／生命周期回应；没有支付SE身份或APDU应用实现的证据。

验证仅含定向反汇编、常量／字段控制流及宿主算术；没有运行Apple encoder/parser、没有控制器通讯。遗留：多pair通知完整兼容性不能按规范推断；全部zero-credit／EOF/profile组合、RX跨CID乱序与所有移除分支、真实数据事务及其超时恢复尚未运行验证。
