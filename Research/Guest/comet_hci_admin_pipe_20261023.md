# 23G90 Comet：HCI admin pipe、HCP及管道恢复

2026-10-23；纯离线分析既有23G90 Comet。未执行库／HAL／SE API／VM，未启动协议服务器、修改系统或绑卡，也未新增产品实现／空编译宏。

**HCI admin 初始化的实际操作是打开固定 pipe 1、设置 allow-list，并接收控制器创建／打开动态 pipe 的命令。** 这不是只需几个 NCI control 成功响应的路径：HCI 在动态逻辑连接上的 NCI DATA 内承载，pipe与gate状态还会影响后续Session恢复和eSE可用性。当前所见路径没有主动 CREATE_PIPE；日志“create pipe for ADM”不能当作主动创建命令的证据。

## 对象与来源

`libNFC_Comet.dylib` UUID `AAD82B14-9985-3582-9A57-22047E668A31`，Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`，`__text` SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。VA均未滑动、只适用于本版研究；未用旧otool外部stub标签推断导入。

复用 `.build/validation/nfcc-protocol-20261023/{comet,init,user-frames}` 与已核对的同版小区段，无新DSC提取。MCP读取的 [NXP固定版本NCI定义](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)仅交叉核对NCI DATA／连接／control分层；下面所有HCI opcode、字段和条件取当前Apple二进制。

本文以 **L=Lib context，H=HCI context** 表示偏移；`L+200`指向H，`H+3c0`反向指向L。Session／child完成细节见[HCI child与Session研究](comet_hci_child_completion_20261023.md)，不将APDU／ATR完整事务扩入本报告。

## 实际HCP封装与NCI DATA

内部 HCI send params：`pipe:u8@0, ins:u8@1, msgType:u8@2, payloadLen:u32@4, payloadPtr@8`。

| 层 | 实际编码／解析 | 当前代码证据 |
| --- | --- | --- |
| HCP首包byte0 | `pipe | (final<<7)`；pipe占低7位，bit7=1表示最后／单包 | BuildHcipacket `0x2a2f429bc`，`42a70–42a88` |
| HCP首包byte1 | `ins | (msgType<<6)`；解码分别取低6位／高2位 | `42a78–42a88`；ExtractData `0x878fc`的`8797c–8799c` |
| HCP后续片 | 仅pipe／final头1字节，后面直接续payload，不重复消息头 | BuildHcpFragment `0x42888`；ExtractData续片从片内+1复制 |
| msgType | 0=command、1=event、2=response；3被ReceiveHandler拒绝 | CoreInit注册type0/1；Open注册type2；ReceiveHandler `0x9bc6c` |
| NCI DATA | `[ConnID&0f | (PBF<<4),00,N,HCP片...]`，尾CRC按现有状态追加 | BuildDataPktNci `0x42cc0`，`42f0c–42f18`、`42fd8–43008` |

`CoreSend` `0x2a2f4bc24` → `SeSendData` `0x29044`：使用H保存的NCI context `+318`与连接对象`+320`；`LogConnGetConnId` `0x3dda4`从逻辑连接表查实际ConnID。**不能把ConnID固定为某个常数，也不能把HCI ins03写成NCI GID/OID。** NCI credit不足会走等待／注册credit回调，普通字节echo不足以完成传输。

首包短消息payload≤253时 `BuildHciNciPkt` `0xbed8`在`c2ec–c310`传final1给`0x429bc`；更长时首片取253字节、final0（`c680–c690`），后续片最多254字节、final0（`c520–c530`），末片final1（`c3e0–c3fc`）。HCP chaining与外层NCI PBF是两层机制，不能合并解释。

RX `CoreRecvCB` `0x4b2d8`按低7位pipe积累分片，见bit7=1才调用ExtractData。ExtractData仅首片拆2字节HCP头、续片去1字节头，并核对最终payload计数；ReceiveHandler再按**pipe+msgType**查注册回调。response type2会撤销该次注册；收到未注册pipe／type不是完成初始化。

CoreSend对command创建`0x7d0`响应timer；发送pending `0xd`仅证明进入异步等待，HCI response type2到达时才删除timer。重试／busy／timeout均有独立路径，未用固定成功替代。

## OpenAdminPipe：OPEN，不是CREATE

`HciOpenAdmPipe` `0x2a2f98ed0–99030`先要求L、`L+200`与`L+208`均非NULL。以下条件原样保留：

- `L[bb0]==1`时直接返回0，不发OPEN。
- 否则若`L[ba8]==1`且`*(L+208)[1]==1`且该对象`u32@4==1`，也直接返回0。
- 其它情况调用`OpenPipe(H,pipe=1,callback=0xe7d8,user=L)`；期待pending `0xd`，其它发送返回值被Lib改为ff。

`OpenPipe` `0x4f8ec`写 `{pipe,ins03,msgType0,len0,NULL}`，清H`+3b9`，发送后注册本pipe的response callback `OpenPipeCb` `0x4f004`。**单包HCP请求是 `81 03`**；外层仅可参数化为 `C 00 02 81 03`，C为实际ConnID的低4位，未包含尾CRC。

`OpenPipeCb`要求前置status0、收到的HCI **response instruction==00（ANY_OK）** 才把回调状态置0；非零ins／前置失败给ff。它没有要求payload恰为1字节：空payload给上层值0，有payload则取首字节存H`+4d5`传回。**ANY_OK在HCP消息头，是 `81 80` 的80，不是把payload[0]当NCI status0。**

`HciOpenAdmPipeProc` `0x99030`在输入status0且context有效时继续；失败转ff。它不主动CREATE，也不在这里建立eSE APDU／connectivity管道表。

## 初始化Allow-list：HCI SET_PARAMETER registry03

`HciSetAllowList` `0x99124`使用与OpenAdmin相同的context及跳过条件；`ba8==1`的实际发送分支直接选择 `[c0,81,02]`。其余分支按L的`16e/16f/16d`状态分别为1或3时加入`c0/81/02`，日志依次称eSE／SE2／UICC；三者均未选中则不发送。

发送调用为 `AnySetParameter(H,registry=03,pipe=01,len=selectedCount,data=hostList,cb=0xe7d8,user=L)`（`9933c–99364`）。setter `0x4f6c0`生成ins01、msgType0、payload=`[registry,values...]`。例如三者全选时 **HCP=`81 01 03 c0 81 02`**；这里host字节来自原分类／状态条件，不是可自行伪造的SE身份。

setter仅接受registry03或registry01；registry01还强制value长度8，registry03使用调用者长度；总体要求value长度<253。`AnySetParameterCb` `0x4ecd4`只在前置status0、HCI响应ins00时成功，释放发送内存后原序列回调；非零ins转ff。未看到本初始化路径实际调用registry01写SessionID，API接受该长度不等于有已执行的会话恢复步骤。

## GET_PARAMETER的真实参数边界

`AnyGetParameter` `0x4f18c`签名实际为 `(H,gate,registry,pipe,callback,user)`；gate仅用于本地合法性检查，**不直接写入wire**。gate1接受registry≤4，gate4仅registry1，gate5接受≤6，其它gate要匹配H`+331`或`+333`保存的私有gate。

通过后发送 `{pipe,ins02,msgType0,len1,payload=[registry]}`，即单包HCP `[80|pipe,02,registry]`。response需ins00，回调`AnyGetParameterCb` `0x4ee30`把解码后的payload／长度传上层；本层不把任意payload当成8字节SessionID。

当前function-start／直接call索引中唯一GET caller是 `SM_SE_eSEGetAtrTrans` `0x68ae8`：取H`+330`的APDU pipe、`+331`的gate，两者不得ff，读取registry01。它属于ATR路径，不能反推child初始化在admin pipe读取SessionID。函数指针调用和未展开API仍保留边界，未声称整个映像绝无其它用途。

## 动态管道：接收创建命令、ACK，再接收OPEN

`CoreInit` `0x4afcc`先将H`+328`的8字节和`+330`的4字节置ff，`+340`的4字节置0，随后注册admin pipe1的command（`ReceiveAdminNotifyCmd` `0x50638`）与event（`ReceiveAdminNotifyEvt` `0x5023c`）。初始化这些表不会自动让pipe有效。

`ReceiveAdminNotifyCmd`对ins12进入创建通知分支；要求前置status0、H/L及payload有效且**payload长度精确5**。它读payload[0]为host、[3]为当前用于归类的gate、[4]为动态pipe；[1]/[2]在该表更新分支未参与判断。日志称“Source Gate”不能改写成实际读取payload[1]，更不能仅凭日志补出未验证的完整五字段语义。

| host byte0 | gate byte3 | 目标字段／含义来自当前日志 |
| --- | --- | --- |
| `c0` | `f0` | H`+330=pipe,+331=f0`，eSE APDU |
| `c0` | `41` | H`+332=pipe,+333=41`，eSE connectivity |
| `02` | `41` | H`+340=pipe,+341=41`，UICC connectivity |

该分支先对新pipe注册type0的`ReceiveOpenPipeNotifyCmd`，置H`+37d=1`，注册成功时在admin pipe回 **ANY_OK `81 80`，无payload**。不认识的host／gate会记日志，不能把ACK本身当作上述表项都已建立。

`ReceiveOpenPipeNotifyCmd` `0x503ac`要求前置成功、context／params有效且ins03；撤销该pipe的一次command注册，发同pipe response ins00、msgType2、**payload单字节00**，即 `[80|pipe,80,00]`。发送pending后，若该pipe不同于H`+330`的APDU pipe，再注册type1的通用pipe-event handler `0x50ad4`；APDU pipe的事件有独立注册路径，不可一概用通用event handler。

本路径是NFCC先通知创建、再向host的动态pipe发OPEN；没有在OpenAdminPipe中观察到host主动发送ADM_CREATE_PIPE opcode10。后端必须维护真实pipe生命周期并按注册顺序投递，不能先返回admin OPEN成功就跳过创建／动态OPEN。

## 管道清除、事件与Session恢复边界

admin command ins13直接进入ANY_OK发送路径；ins14/15进入ClearAll分支，再回ANY_OK。当前实际clear代码先要求payload[0]==c0且H`+3c0`有效；当L`bb0!=1`时将H`+330`的u32置`ffffffff`，并设H`+37b=1`。同函数虽有UICC清表日志块，但host!=c0的入口直接去unknown日志，不能按日志宣称02一定执行清表。未修复或运行这些分支。

这类清除通知不是HCI event：它们走type0 command并由host回type2 ANY_OK。`ReceiveAdminNotifyEvt` `0x5023c`则按type1处理ins01（End of Operation→`0x9e3e8(L)`）、ins20（OS reset→条件调用`0x9db68`）、ins03（HotPlug日志）。不能把这些ins混作NCI notification OID。

当前child的SessionID读取／清除实际走 **NCI CORE_GET_CONFIG／CORE_SET_CONFIG**，不是上述HCI GET_PARAMETER。配套[child完成报告](comet_hci_child_completion_20261023.md)恢复了Session参数、EoOp标志和末项callback：动态pipe仍为ff会进入清Session／重新初始化分支；本报告只证明这些pipe字段如何由通知从ff建立或重新失效。

**admin OPEN成功 ≠ 动态pipe有效 ≠ Session有效 ≠ eSE可用 ≠ LoadStack已完成。** 最小无RF后端需要逻辑连接／credit、HCP分片与消息分类、admin注册／allow-list、真实pipe创建与OPEN／清除、Session配置及通知时序；本轮没有执行原生LoadStack，也没有制造成功trace。

## 验证与遗留

纯算法重组仅检查HCP/NCI单包长度和type/ins位切分，保存在 `admin/hcp-wire-shapes.json`；不是控制器响应实测。`direct-callers.json`保留Get/Set/Open直接caller及原function-pointer索引引用。定向反汇编和primary NCI source摘录同放 `.build/validation/comet-hci-20261023/admin/`，目录0700／文件0600。

尚未恢复或验证完整五字段语义、所有vendor host／gate profile、管道删除的完整映射、异常通知重入／乱序、NCI credit与HCP双重分片的全部错误恢复，以及ATR／APDU应用行为。所有定制实验产品实现需要具名编译宏可停用／移除的用户规则在本轮未被触发：此处只有研究文档和静态证据。
