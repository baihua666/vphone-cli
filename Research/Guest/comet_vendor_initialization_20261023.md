# 23G90 Comet：厂商初始化、配置与 CRC 状态迁移

2026-10-23。仅离线分析现有23G90 Comet／PN548证据及只读提取的小片段。没有执行库、启动／挂载VM、加载前端、运行后端服务器、修改系统／VM门槛、绑卡或上传固件。

## 结论与一项前轮更正

**无RF控制器仍需实现真实的私有扩展能力、standby、标准／私有配置库及CRC状态迁移。** 初始化并不只消费`CORE_RESET`／`CORE_INIT`；扩展响应的4字节能力值、SET_CONFIG错误与CRC转换会影响后续分支。这里恢复的是协议契约，没有用固定成功响应验证原生LoadStack。

前轮初始化报告将常量`0x2a2fc36a8`误读为邻近的`{3,1}`。本轮精确按file offset `0xc36a8`读取8字节为`01 00 00 00 00 00 00 00`，即 **`{type=1,GID=0}`**；`{3,1}`实际位于`0xc3690`／`0xc36b0`。这是先前的常量偏移读取错误，不是提取器篡改或内部type3到wireMT1的映射。

下列地址为未滑动用户态VA，来自Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`，`__text` SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`；不作为内核地址或补丁常量。函数名由日志／function-start恢复，未信任旧otool外部stub错误标签。与前轮[帧与CRC](pn548_user_frames_crc_20261023.md)、[初始化序列](pn548_nfcc_initialization_20261023.md)配套阅读。

## 实际线上命令编码已经闭环

内部发送descriptor按偏移为`type:u32@0,GID:u32@4,OID:u32@8,payloadPtr@0x10,payloadLen:u32@0x18`。

1. `CoreIfTxRx` `0x2a2f0a880`：`...a910–a950`检查`type==1`，保持GID／OID并选mux index2；其它type走data mux且清两个字段，不能把任意descriptor直接当NCI command。
2. `phNciCoreMuxNfc_Tx` `0x2a2f0a9a0`的mux2分支调用`CmdTx` `0x2a2f0ab58`，后者复制descriptor进入上下文并启动mux处理。实际BuildCmd调用点`0x2a2f0c458`。
3. `CoreBuildCmdPkt` `0x2a2f0cc94`在`...ccd8`读取`+4/+8`，验证GID0／1／2／15；`...ce70`写`h0=0x20|GID`，`...ce24`取OID低6位，`...ce30`写payloadLen，再复制payload，交TML前按现有flag追加CRC。

| 请求 | 不含可选尾CRC的线上字节 | descriptor／实际发送入口 |
| --- | --- | --- |
| CORE_RESET | `20 00 01 resetType` | InitReset `0x2a2f458c8`，GID0／OID0，payload为context+0x24；初次路径置1，其它reset路径可不同 |
| CORE_INIT | `20 01 00` | Init `0x2a2f45dec`，GID0／OID1，payloadLen0 |
| CORE_SET_CONFIG | `20 02 L count TLVs...` | CoreSetConfig `0x2a2f10c74`；L与count依据实际参数数量／值长度生成 |
| CORE_GET_CONFIG | `20 03 L count IDs...` | CoreGetConfig `0x2a2f1410c` |
| enable proprietary extension | `2f 02 00` | EnableExtnCmd `0x2a2fb0844`，const`0x2a2fc3550={1,15}`，OID2、len0 |
| set standby | `2f 00 01 mode` | SendStandbyCmd `0x2a2f469c4`；SetPowerMode `0x2a2fb6074`分配1字节，按调用值写mode |
| HSU参数 | `2f 03 08 parameters[8]` | ConfigHsuBrCmd `0x2a2f46b44`，实际由3族×9档表选择8字节payload |

FW查询同样走此映射；例如GetFwType的GID15／OID6／len0得到`2f 06 00`，InterfaceVersion在len0条件下得到`2f 19 00`。内部PN548 Ioctl编号（例如`0xe2`）和mux index2都不是线上OID。

## EnablePropExtn：响应不是单字节成功

Lib阶段`0x2a2f54b18`调用NCI入口`0x2a2fb8f00`，后者使用sequence `0x2b17bf2e8`：EnableExtnCmd → EnableExtnRsp → CompleteEnableExtnSeq。

- `EnableExtnRsp` `0x2a2fb0934`：正常成功要求payload长度**精确5**且第0字节status=0。长度1即使status0也记录信息字段缺失并失败；其它长度失败。
- 长度5时，status1／6映射为内部`0x93`，status3或未知值失败；长度1还识别syntax／semantic等错误。不得把所有非零状态翻译成成功。
- `CompleteEnableExtnSeq` `0x2a2fb0b34`把原响应传上层；`phLibNfc_EnableExtnProcess` `0x2a2f54b9c`在status0时将payload[1..4]按BE32组装并OR入Lib context `+0xbd8`。这些是后续依赖的私有扩展能力，完整bit名尚未恢复，不能随意用零或全1填充。
- 上层payload[0]=`0x2c`的专门重试分支会清／重启读请求、回退序列并增加`+0xc89`重试计数；计数大于2停止。此值来自特定失败传递，不是正常成功响应格式。

## DisableStandby：请求、响应、实际状态

Lib `DisableStandbyMode` `0x2a2f54e00`先把pending byte`+1`清0；当前状态byte`+0`非零时发送mode0，否则直接标记`+2=1`并完成。并非每次初始化都必发同一包。

NCI sequence `0x2b17bc350`：SendStandbyCmd → `ProcessCommonNciRsp2` `0x2a2f1a0ac` → CompleteStandbySequence。响应必须payload长度**精确1**、status0才成功；`0xf1`映射内部`0x51`，`0xbd`映射`0xbd`，其它失败。成功后NCI保存请求值`d24→d20`；失败写d20=1。Lib `SetStandbyModeProcess` `0x2a2f54ea8`仅在成功时把pending复制为current，翻转pending并置completed。兼容后端必须把控制器standby状态与后续供电／唤醒行为维持一致。

## InitSetConfig：标准及私有TLV清单

`phLibNfc_InitSetConfig` `0x2a2f55240`构造清零的`0x6e8`字节配置对象，再按产品／平台分类字节与mode填flags和值，调用`SetConfigRfParameters` `0x2a2f16cb4`。**这里的“RF参数”同时包含系统／CRC项；函数名不能作为可全部删掉的依据。**

序列化由`BuildSetConfCmdPayload` `0x2a2f17ca8`及helpers完成。普通ID编码`[ID,len,value]`；`TlvUtilsAddTlv` `0x2a2f189ec`检测ID高字节A0／A1，实际编码`[high,low,len-1,value]`并复制`argLen-1`字节。所以下表private条目的helper argLen2代表线上value长度1，不能把它写成2字节value。

| 初始化可能选择的ID | 线上value／来源 | 生成位置或条件 |
| --- | --- | --- |
| `80`、`81` | 各`01` | cfg+4 bit10、cfg+220 bits2/3，取cfg+227/228；`0x2a2f18374–183b0` |
| `28` | `01` | cfg+4 bit4、cfg+58 bit0，取cfg+5c；`0x2a2f17d1c–17d38` |
| `5b` | `00` | cfg+4 bit8、cfg+17c bit3，取cfg+1e3；`0x2a2f18020–18038` |
| `A0 02` | `01` | cfg+244 bit1，取cfg+24a；`0x2a2f18464–18480` |
| `A0 04` | `0c`或清零值 | cfg+244 bit3，取cfg+24b；`0x2a2f1848c–184a4` |
| `A0 03` | `((cfg[24c]<<3)|cfg[250])&0x0f`，所见初始化值2/1得到`01` | cfg+244 bit2；`0x2a2f184b0–184dc`；只有32位cfg+24c==1时另附A011四字节 |
| `A0 07` | `cfg[25c] | (cfg[260]<<1)`，所见初始化0/1得到`02` | cfg+244 bit6；`0x2a2f18530–18558` |
| `A0 19` | `02` | cfg+244 bit14，取cfg+3a4；`0x2a2f185e0–185f8` |
| `A0 d5` | `0a`或`04` | cfg+244 bit15，取cfg+3a8；`0x2a2f18604–1861c` |
| `A0 37` | `ee` | cfg+244 bit16，取cfg+3ac；`0x2a2f186d8–186f0` |
| `A0 44` | `00` | cfg+4 bit15，NXP discovery子对象+580 bit4，取+58d；helper `0x2a2fb4850` |
| `A0 bf` | CRC enable byte，0或1 | cfg+4 bit16，prop子对象+600 bit14，取+60c；`0x2a2f18dd4–18dec`；初始化CRC阶段单独设置 |

InitSetConfig本身不请求A00F；EEPROM读写阶段另设cfg+244 bit7，见配套EEPROM研究。后端需存储真实被请求的参数和值，并可返回拒绝／unsupported，不能把这些写操作当作只读查询。

分支保留原上下文条件，未将分类字节强行命名成具体芯片：`ba9/baa/bb0==1`的一组走精简配置；其它组预选A019／A0d5／A037，并进一步选择A002／A003／A004／A007。`ba8==1`影响A0d5值和A004值；`c84==1`清除80／81，并跳过28／5b／A044附加项。一些`ba9/baa/bb0`与`c84`组合直接完成、不提交SetConfig。没有运行实际实例选出哪一组，也没有通过改分类缩减协议。

底层`SetConfigRsp` `0x2a2f10e7c`要求payload至少2字节并读取status及失败ID列表；status0成功，1／5／9映射`0x93`，f9→`0x87`，fc→`0x9e`，f1／其它失败。`InitSetConfigProcess` `0x2a2f55580`本身只返回0，不能据此推导底层命令总成功或不需要真实RSP；错误处理已在前置解析器／sequence engine发生。

## CRC配置与响应后状态迁移

`phLibNfc_CrcConfig` `0x2a2f543f8`只有所见分类／firmware／flag组合满足且desired CRC `Lib+154c==1`时才发SetConfig：cfg+4 bit16、cfg+600 bit14、value+60c=desired → private TLV **`A0 BF 01 desired`**。不满足时会跳一个序列阶段并清Lib+b74，不能把“没发包”与“后端忽略命令”等价。

`CrcConfigProcess` `0x2a2f545c0`在上一步失败时返回失败，不切flag；成功后：

1. 将desired传`UpdateCrcChkFlag`（NCI context+1851）。
2. 在desired1且Lib+1808非空时设`skipCRC=1`并保存requested config（NCI+1852／1853）。
3. 接口类型值为6且desired为0/1时，调用TML IoCtl op`0x2f`配置driver CRC option；不是线上NCI命令。
4. 随后的reset响应路径`0x2a2f45d38–45da0`可清skip/requested、调整check，再把check复制到append（NCI+1850）；因此TX追加与RX验证并非在配置发送时瞬间一起改变。

运行时Ioctl路径也恢复：`phLibNfc_Ioctl_PropSetCrcChkConfig` `0x2a2f397c0`要求恰1字节且值<2；`SM_IoctlCrcChkConfigTrans` `0x2a2f629b8`明确写`A0 BF 01 value`，保存desired并提交真实配置序列。完成回调`IoctlSetPropRfCfgComplete`的`0x2a2f11c48–11d78`只在配置成功后处理pending CRC flags；接口6还暂置check1／skip1并把driver CRC option置1，然后进入NCI重新初始化sequence。**不能只实现socketoption即视为控制器CRC配置完成，也不能让响应按错误的旧／新状态随意带尾CRC。** 具体切换必须按这些响应与reset阶段建模。

## HSU：可条件跳过，但保留协议和错误

Lib `ConfigHsuBrCmd` `0x2a2fa2db8`在`bab==1`或`bb0==1`直接完成；否则检查／恢复host baud后调用`PropConfigHsuBr` `0x2a2fb6214`。后者接受9档enum，按NCI context+12ba／12b9选三组表，复制8字节，再发`2f 03 08 ...`。27个原始payload及fixup指针已保存`vendor/hsu-payload-tables.json`；例如第一族enum1为`1a0600550154018a`，第三族enum1为`b60200540100008a`。这些是不同硬件族寄存器参数，不得从其中任一组杜撰通用波特率编码。

HSU sequence `0x2b17bc370`使用`ProcessCommonNciRsp1` `0x2a2f1e920`，仅接受payload长度精确1且status0；完成后释放参数buffer并把状态传回Lib。`ConfigHsuBrResp` `0x2a2fa2f9c`还有retry、更新TML baud、重启NCI读请求和超时失败路径；成功响应不会免除host transport配置。最小SPMI模型可利用原本成立的跳步／HAL无termios路径，但不能修改分类或全局把HSU调用伪造成成功。

## 对无RF最小模型的影响

后端至少应维护：私有扩展能力BE32、standby current/pending、按ID存储的标准及private配置、CRC desired/check/append/skip迁移、所选transport参数及响应／timeout错误。前端主要搬运字节、应用控制面和driver option；不能代后端回固定成功、伪造能力或绕过原库状态机。RF polling／发现不运行可以缩小射频行为，但不授权省略已被原序列实际调用的配置命令。

本轮尚未完整恢复私有能力bit的命名、所有分类值来源、HSU寄存器位的物理含义及全部恢复路径。可据上述契约定义离线parser／状态转移验收；没有声称原生LoadStack或SE生命周期已通过。

证据保存在Git忽略的`.build/validation/comet-config-20261023/vendor/`：精确descriptor字节、HSU指针与payload、各入口／响应／TLV helpers定向反汇编。目录0700、文件0600；未新增产品、驱动、补丁或协议服务器。
