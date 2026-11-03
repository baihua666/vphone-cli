# 23G90 Comet：一笔 eSE APDU 的 DATA event、结果与回调契约

2026-10-23；仅离线读取现有机器码、状态表和已保留的原DSC小段。未执行Apple库、VM、HAL／SE API或后端，未改产品、系统、门槛或绑卡，未解大缓存。本轮无产品实现，无需新增空编译宏。

**普通eSE APDU是HCI `msgType=1,ins=10` 的DATA event；正常回答也是DATA event，不能用HCI `ANY_OK` response代替。** Comet最终普通回调是六参；发送完成、credit恢复、HCP分片完成与APDU业务完成是不同边。

## 对象与证据

Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`；Mach-O SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`，text SHA256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。VA均为本版未滑动地址，文中省略共同前缀`0x2a2f`的函数地址。

L=Lib context，H=`L+200` HCI context，D=下载eSE context，I=ioctl context；四者不可混用。复用MCP已读的[Arm官方AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst)核对寄存器调用约定；Apple字段、分支和协议值全部以当前机器码为准。

定向反汇编、下载状态行和静态字段检查位于`.build/validation/comet-apdu-20261023/data/`，目录0700、文件0600。状态行同时交叉核对既有`comet-se-post-init-20261023/routing/se-tables.json`；原DSC区段与重建库一致性沿用`comet-config-20261023/raw/section-comparison.json`。未依赖旧otool错误的外部stub名字推断调用。

## API注册、状态和请求对象寿命

`phLibNfc_eSE_Transceive 79e2c–7a1b0`原始入参为`(driver,SEhandle,request,mainCallback,wtxCallback,user)`，保存原x3/x4/x5分别为主callback／可选WTX callback／user。

`79ef0–79f18`要求request、SEhandle、主callback非NULL；`79f1c–79f58`检查恢复`L22b`及下载／切换占用`L17bf/17c3/17c2/17c0`，相关值为1返回`6f`。普通路径扫描`L198/1a8/1b8/1c8`四个16字节Lib槽匹配handle，保存匹配槽指针至`L230`。非NULL handle不能替代ready／mode／FSM条件，见[record生命周期](comet_se_record_lifecycle_20261023.md)。

`7a0b4–7a100`的选择为：

| 原条件 | event／实际入口 | 边界 |
| --- | --- | --- |
| 匹配槽type≠1 | `86` | 当前六张SE表没有86行，不能冒充eSE APDU通路；通过busy检查后仍可能同步`93`。 |
| type1，request byte`+28`≠1 | `8d` | Apdu子状态3表`2b1490d00`项`2b1490d90`→`684e0`。 |
| type1，byte`+28`=1，槽mode`+c`≠0 | `8d` | 同上。 |
| type1，byte`+28`=1，mode=0 | `8e` | Virtual子状态2表`2b17bd6b0`项`2b17bd7a0`→**同一`684e0`普通发送**，不是独立Raw API。 |
| `L17be=1`特殊下载分支且handle等于`L1b8` | `ba` | 独立下载FSM，见末节。 |

`684e0`先`CheckTransOnApduPipe 9a5f0`检查未占用；成功后`68568–68574`浅复制request的`0x30`字节至`L260..28f`，并调用`99c58`。指针指向的发送／接收buffer没有在这一步深复制，调用者须保持其寿命；不能因API返回pending就释放接收buffer。

普通request映射：`ptr@0→L260`发送数据、`u32@8→L268`发送长度、`ptr@10→L270`接收buffer、`u32@18→L278`接收容量／完成长度、`u32@20→L280`超时输入、`u32@24→L284`目标OS／pipe选择输入；`byte@28→L288`影响上述event选择。

`7a100`提交`SM_StateHandler(driver,event,0,request,NULL)`。**仅返回pending `0d`后**，普通路径`7a178–7a188`才写`L18c8=主callback,L18d0=user`，可选WTX写`L18f8/L1900`。同步拒绝不承诺后续callback。本轮未以静态代码证明多线程注册时序安全。

## 普通发送：确切HCP类型与pipe来源

`HciDataSend 99c58`要求L与H存在；`99ca4–99cd0`用`MultiOSGetPipeId(H,L284,&pipe) 50ffc`查pipe，只有返回`93`才fallback `GetPipeId(H,gate=f0,&pipe) 4fb48`。非零结果或pipe=`ff`不能发包；不能把所有实例硬编码为pipe19。

`99d08–99d4c`登记**本pipe、msgType2 response**到`ProcessRspsOnApduPipe 99ed0`，供错误response处理；清`H4d4/H4d0/L2f2`。`99d5c–99d78`真实调用：

```text
Transceive9a054(H, pipe, ins=10, msgType=1,
                len=L268, data=L260, sendCallbackSelector=NULL)
```

`9a054`构造`{pipe:u8@0,ins:u8@1,type:u8@2,len:u16@4,dataPtr@8}`，进入`CoreSend4bc24`。HCP首包头为`[pipe|(last<<7),ins|(type<<6)]`：单个完整普通APDU请求为 **`[80|pipe,50,APDU bytes...]`**。这是参数化公式，不包含实际卡命令、身份或成功回答。

外层NCI DATA是`[(CID&0f)|(PBF<<4),00,payloadLen]`，CID、分片长度、credit及收到数据回调注册必须来自真实已建立连接；不能把HCP的pipe放进NCI GID/OID。详见[transport／credit契约](comet_apdu_transport_recovery_contract_20261023.md)。

`9a054`的x6为0时选`CmdSendCb 4eb38`，非0选`RawCmdSendCb 4ec04`；x6不是此处直接调用的函数指针。普通pending后`99d84–99d90`保存`H+b8=SeSendCb9fa08,H+c0=L`。

`4eb38`收到发送status0只记录成功，**不调用应用callback**；非零转`9fa08(L,ff,NULL)`。后者以H原send字段构造长度0、dataNULL的HCI参数，送`ReceiveHandler9bc6c`，普通event10最终因空数据转ff。credit发送完成不能代替接收回答。

## 接收：DATA、ANY_OK和WTX各走不同分支

HCP收包先按pipe重组，last位完成才提取`{pipe,ins,type,len,data}`；`ReceiveHandler9bc6c`先按msgType选注册表，再按pipe匹配（`9bcb4–9bcf8`）。type2回调项在调用前删除（`9bdb4–9bdd0`）；type1保持注册。这不是按APDU内容或某个通用事务ID匹配。

`ProcessEventsOnApduPipe 9b024`要求H、L、参数存在且下层status0：

| HCI输入 | 当前机器码处理 | 是否完成普通APDU |
| --- | --- | --- |
| type1，ins`10` DATA | `9b084–9b0b4`；通常`9b27c→9b51c→9a1c8(L,0,params)` | 是，但还须通过有效buffer／pending检查。独立Raw在途且`(L291|10)==51`时此DATA会被识别undesired并拒绝。 |
| type2，ins`00` ANY_OK | `99f58–99f74`记录“Not Expected From APDU Pipe”然后返回 | **否**；不能靠`[80|pipe,80]`构造成功闭环。 |
| type2，ins`01..0b`或未知 | `99ed0`跳表`1bb3c`及`99ff8–9a018`→`9a1c8(L,ff,params)` | 错误终止，不把response字节0当NCI status。 |
| type1，ins`11` WTX | `9b204–9b3dc`，延长等待并通知可选WTX callback | 否。 |

WTX若未注册`L18f8`，记录后丢弃。payload指针非空时取**首字节高4位**，`CalcWtxTimeout9b61c`调用`CalcPower9b6d0(2,highNibble)`，再做浮点`/10*1000`转u32；得到值≤`7cf`再加`190`，指针空默认`7d0`。这里未见该分支单独验证len>0，不能以协议常识补上。

结果写`L2c0/H354`；`9b324–9b33c`五参WTX callback为`(L2628 driver,L1900 user,扫描type1槽所得SEhandle,&L2c0,4a)`。x3直接指向u32超时，不是普通response描述符。随后仅在`H348` timer有效时重新计时；该通知不消费WTX槽，最终完成消费者才清空。

## 普通结果buffer和status

`HciDataSendProc 9a1c8`入口为`(L,status,params)`；正常status0还要求普通`L18c8`非NULL，params长度`u16@4>0`且dataPtr非NULL。`9a2dc–9a2ec`检查`CheckTransOnApduPipe`必须仍返回busy `6f`，否则走迟到数据分支；不是收到任何event10都保证应用成功。

| 条件／VA | 结果 |
| --- | --- |
| dataLen≤容量，`9a5d4..9a5ec` | 复制全部payload到`L270`，`L278=实际dataLen`，status0。Comet此处不解析APDU SW1/SW2。 |
| dataLen>容量，`9a31c..9a348` | status`08`，未见部分复制，也未将L278改成所需长度。 |
| `L270==NULL`或容量0，`9a30c..9a318→9a5cc` | 保持status0而不复制；不能把所有“无buffer”都写成这里报错，PN外层另有结果长度检查。 |
| DATA长度0或dataNULL，`9a3b0..9a3d4` | status`ff`。 |
| 普通错误，`9a3d8` | `L278=0`并保留输入status。 |
| 输入`41`，`9a34c..9a374` | 特殊日志“RECOVERY SUCCESS”但仍保留`41`，不改0，且此分支不清L278。 |
| 输入`d9`且paramsNULL，`9a378..9a3ac` | 若L278非零，复制H4d4的一字节并置长度1；保留d9。不能把此字节当APDU成功响应。 |

清理`9a410–9a4e4`停／删H348计时器，置无效值`ffffffffffff`、H354重置`2710`；注销gatef0所得pipe的type2 response回调，释放该pipe累计接收链，清H3b9。由于发送曾按L284选择其它pipe，不能把这段清理描述成“无条件遍历注销所有pipe”。

`FindSetModeIntEvent9e8cc`按activeSE type生成完成event：type1成功`a4`、非零`a5`；其它type2=`a8/a9`、type5=`a0/a1`、type7=`ac/ad`。`9a56c–9a580`再发状态机，**Proc本身不直接调用主应用callback**。唤醒线配置失败路径可能将status改ff，故不能仅凭前段copy成功认定最终返回0。

## FSM恢复原操作并消费主callback

eSE `8d/8e`进入pending后，SE状态机保存原event；收到`a4/a5`时恢复它，再调用`SM_SE_TransComplete67b5c`，与SetMode共用消费者但分支和槽不同，详见[SetMode契约](comet_apdu_modeset_contract_20261023.md)。

普通原event8d或8e在`67d30–67db8`的精确顺序：

```text
cb=L18c8; user=L18d0;
clear16(L+18c8);                     // 调用前清函数与user
if bb3f4(Lc10)==24 && L2f2==1: L2f2=0; status=da;
if cb:
    cb(x0=L2628, x1=user, x2=0,
       x3=&L270, w4=L284, x5=status);
    clear16(L+18f8);                 // 返回后清WTX callback/user
```

response为`{dataPtr@0,u32 actualLength@8}`，x4是L284的原目标选择字，不是status；普通主status在第六参x5。SetMode的`1a18/1a20`五参、Raw的`18d8/18e0`五参及初始化的`17d8/17e0`三参都不能套用这里。

**该67b5c消费者自身先清后调，重复抵达时不会重调旧槽；这不是全系统严格一次证明。** `InvokePendingCb40cf0`另有`41528–41580`普通fallback，用六参`(driver,user,0,NULL,ff,ff)`调用，**返回后**才清槽；其WTX/raw分支也不是正常完成签名的success trace。不能据此宣称超时后所有晚到路径必然无副作用。

## 超时、移除与独立Raw分支

普通timer初值由`99d94–99db4`选择：若`u16 L2f4≥7d0`取该值；否则取L280，若`L280>>4<271`再取`2710`。该条件不是简单“总是2秒”或“总是10秒”。有效timer在`99e84–99ea4`绑定`9f82c`和L。

超时`9f82c`先核对L/H仍在两组实例映射中，停删timer并设置超时标记；`9f980–9f9cc`通常调用`9a1c8(L,2c,NULL)`，若L2f2=1则清该位并改`da`。普通链清长度／清理／派a5／恢复8d或8e／消费主槽。无效L只记录返回；L仍有效但H无效有继续清理分支，不能承诺对已释放对象仍可回调。timer在发送提交pending后启动，并不等待第一段回答；credit等待另有transport timer。

`ProcessSERemovedNtf9d5b4`优先处理ATR槽；否则只要18c8或18d8存在，`9d624–9d630`调用`9a1c8(L,输入status,NULL)`。发现移除调用者常传41，保留41；不是硬改成成功。下层移除及record失效条件见record报告。

真正Raw API是`SE_RawTransceive7a1b0`：type1才派`8f`，pending后`7a3f8–7a404`注册`18d8/18e0`及可选18f8/1900。Apdu表`2b1490da0`→`689f4`；先`VerifyHciRawInfo9aa7c`，再浅复制0x30至L290。验证当前只接受type1 event，ins41或受payload限制的51；pipe／OS/profile也有检查，不能把它当任意HCI注入接口。

`HciRawDataSend9ae2c`使用`L290 pipe,L291 ins,L292 type,L294 len,L298 data`；按L2b8重新查pipe成功且非ff才覆盖L290。Raw超时来自L2a0；其发送回调4ec04／9fac8和普通发送成功路径不同。

`9a1c8`的非零status、paramsNULL或普通18c8缺失会到`9a22c`；若Raw18d8存在则委托`RawDataSendProc9a6b8`，**不仅2c超时**。Raw接收描述符在`L2a8`保存pipe/ins/type，容量u16在L2ac，dataPtr在L2b0；超容量status8，普通错误清头／长度。最终同样按a4/a5回FSM，原event8f在`67dc8–67e50`取清18d8/18e0，再五参`cb(driver,user,0,&stack{ptr=&L2a8,len=10},status)`。不能套普通六参或把Raw错误缓冲当APDU回答。

## BA下载eSE路径与未证边界

BA经`022e0`分派`DnldStateHandler91bec`，用独立记录`S+50/54/58/5c`。下载目录`2ae0f7f38`六表：state1/2/3的BA项`2b17bdba0/bdc30/bdd60`均指`6b280`，分别next5/5/4；state0无BA项。

`6b280→DnldEseTranscvCmd3a1c0`复制request接收描述符到`D40`，发送字段至`I308..337`，调用`DnldEseCoreIfTxOnlyc0964`，后者调用mux index5；这不是普通mux的HCP event10。pending后原API主callback存D288、userD290，WTX D298/2a0。

`DnldEseTranscvRsp3a428`清L17c0，向下载FSM派`c5,status,response`；下载state4/5的c5分别恢复state3/1并指向`6b03c`。其`6b0dc–6b13c`先取清D288/290，再六参`cb(D0,user,D8,&D40,I334,status)`，之后清D298/2a0和D40；并有d6/d9专用资源清理。本轮未继续恢复mux5最终序列化及下载timer/cancel所有分支，**不能把普通HCP wire或普通APDU timer直接移植到BA**。

本轮已收敛普通eSE一笔数据的静态调用链和拒绝条件；未执行真实APDU、未验证卡应用、Wallet资格、SE密钥或Apple Pay。可验证后端必须让真实连接／pipe承载完整DATA回答、保留长度和错误并进入真实消费者；固定ANY_OK、固定APDU成功数据或只让发送callback成功都不能作为完成证据。
