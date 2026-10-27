# 23G90 Comet：eSE 电源状态、初始化与 PN548 枚举

2026-10-23；仅离线读取现有同版 Comet 重建库、function-start／指针表及已核对原始岛的 PN548 反汇编。没有加载／执行库、启动／挂载VM、运行后端、加载驱动、改系统／VM门槛或绑卡。所有VA为用户态未滑动地址；状态值按所在层说明。

## 结论

**eSE上电请求、NFCEE异步发现、Comet静态配置校验和PN548列表枚举是不同完成条件。** `GetSecureElementList`本身读取Comet已保存的状态，不发出新的发现命令；PN548枚举返回0、列表非空，都不足以证明实体eSE存在或已完成HCI初始化。

已有电源相关内部ioctl／配置selector不能当作NCI opcode。当前可证的真正NFCEE ModeSet应沿Comet下层编码与通知链判断；初始化还可能经过HCI child初始化、eSE重初始化和静态收尾sequence。本文不把任一局部成功提升为LoadStack、APDU或Wallet成功。

配套：[初始化总序列](pn548_nfcc_initialization_20261023.md)、[EEPROM配置](comet_eeprom_protocol_20261023.md)、[厂商配置与CRC](comet_vendor_initialization_20261023.md)、[NFCEE发现与ModeSet](comet_nfcee_discovery_20261023.md)。证据：`.build/validation/comet-nfcee-20261023/power/`，Comet来源仍为前轮SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；PN548使用`nfcc-protocol-20261023/integration/pn548-annotated-disass.txt`，不信任旧otool的统一错误stub标签。

## Comet字段先由配置与通知建立

以下L为Lib context，N为NCI context。不能把L+16d／16e／16f与列表entry的32位state混成同一枚举。

| 来源 | 确切操作／控制流 |
| --- | --- |
| GetNfceeIntfCfgProc `0x2a2f55a34` | `0x55a7c–55a94`默认L[16e]=3、L[16f]=2；L[16d]按L[bb2]==1取2，否则3 |
| 配置接口是否禁用 | `0x55ad8–55b94`读取响应flags及A0EC／A0ED／A0D4值；相应值为0时把L[16d]／L[16e]／L[16f]置2。它们来自CORE_GET_CONFIG，不是测量电压 |
| EnableNfceeDisc `0x2a2f55b9c` | 置L[2e8]=1并清L+228；三状态均2时直接完成；否则还受L+1f8控制，满足原条件才调用`0x2a2fb5a78`，不能假定每次必发同一发现包 |
| eSE connected通知 | UpdateSeInfo中`0x2a2f06ef4–06f4c`：仅L[2e8]==1、L[16e]!=1且L[22b]==0时，增加L[16a]，L+1b8=NFCEE record，L[16e]=1、L+1c0=1、L+1c4=`(record.u32@4!=1)` |
| eSE removed通知 | `0x2a2f06d3c–06d58`清相关标志、保留record句柄到L+1b8并将L[16e]=2；初始化期间还可在`0x06e54–06eb8`增加/保存移除条目，触发等待计时器的停止路径 |

并行NFCEE恢复已核对：NCI记录位于`N+0xf80+i*0x68`，ID位于record+1，status字段在+4；DISCOVER_NTF的wire status0映射record+4=1，status1映射0，status2走独立removed事件。eSE通知ID为0xC0；它不是PN548 API的SE编号1，也不能用routing ID代替。其完整线上长度／protocol／TLV契约见本轮NFCEE专项报告，本文不重复扩展。同日后续复核更正原误写的80：它只是比较分界，实际connected／removed分别在06a9c／06a20比较c0，见[record生命周期](comet_se_record_lifecycle_20261023.md)。

## InitCb与InitializeComplete并不立即完成eSE

`phLibNfc_InitCb (0x2a2f597b0)`先核对Lib context；下层status非0改为0xff。成功且非空buffer时，`0x598a8–598d8`保存NCI handle到L+c10、应用下层设置并调用`0x59930`处理控制器信息。`0x598dc–59918`按平台识别函数`0x31530`返回0x0a将L+c84置1，记录SE300S的No RF启动；这是分类结果，不是允许伪造该值来删去eSE流程。

InitializeComplete `0x2a2f55d38`成功后注册通知处理。`0x55dc0–55dd0`明确建立Host：L[16a]=1、L+198(handle)=NULL、L+1a0(type,state)=[5,1]。const `0x2a2fc3710`在重建库fileoff0xc3710实读8字节`05 00 00 00 01 00 00 00`。**这个Host条目可以在没有实体eSE句柄时存在。**

`0x562d8–56334`还有独立路径：L[cc0]非零时清标记和三状态；否则启动InitComplete watchdog（参数1000），只有L[16d]、L[16e]、L[16f]均2才立刻进入`StaticListenModeRouting (0x5bb28)`。其余路径等待通知推进，不是仅靠发现响应就宣告SE完成。

`StaticListenModeRouting`的名字不能直接解释为又发送一条routing命令。`0x5bbc4–5bc18`设置L+250=100、L[b71]=10，选择sequence `0x2b17bc570`；已恢复指针顺序为：

| sequence地址 | 动作／处理器 |
| --- | --- |
| `0x2b17bc570`／578 | SetStandbyMode `0x57324`／SetStandbyModeProcess `0x54ea8` |
| `0x2b17bc580`／588 | NfceeDisableESE `0x573d4`／NfceeDisableProc `0x575e4` |
| `0x2b17bc590`／598 | NfceeDisableUICC `0x57734`／同Proc |
| `0x2b17bc5a0`／5a8 | NfceeDisableSE2 `0x578f8`／同Proc |
| `0x2b17bc5b0`／5b8 | FlushSramData `0x1131c`／FlushSramDataProcess `0x11a68` |
| `0x2b17bc5c8` | staticFeatureCfgComplete `0x57ac8` |

NfceeDisableESE在`0x5748c–574e4`对无句柄、state1或4直接完成；特定型号且不是指定sequence时在`0x574e8–57530`只更新缓存state。实际需要下发的分支`0x57534–57550`调用`0x2a2fb5db0(N, handle, mode=0, callback, L)`；pending0x0d才保存activeSE=L+1b8，busy0x6f与失败各自返回。不能把这种逻辑禁用与切断物理供电等同。

并行NFCEE定向恢复已闭环该调用的真实wire：Nfcee_ModeSet `0x2a2fb5db0`限制mode≤1，在`0xb5e58–b5e60`复制record[1]为ID、mode为第二字节，长度2；sequence`0x2b17bdfb0`进入ModeSet `0x6b7c4`／Rsp `0x6b8a8`／Complete `0x6b9cc`。`0x6b820–6b824`取descriptor const `0x2a2fc3608={1,2}`、OID1，沿已核对command encoder得到**`22 01 02 ID mode`**。Rsp读取payload[0]，0成功、f1→内部51、其它ff；此函数未见独立长度检查，不能写成“已证明精确1字节”。成功RSP后还可等待异步通知／计时器，不能只回`42 01 01 00`就声称电源生命周期通过。另有NULL record产生ID0分支，普通有eSE句柄的DisableESE应使用真实record ID。

Complete `0x2a2f6b9cc`成功且record非NULL、不是mode1与ID1的组合时，创建N+1238计时器（参数0x7d0）而不立即Notify；计时器回调`0x6c1a4`按型号flags选择内部0x2f或0交保存的callback，不能把所有计时器到期统一归失败。本轮另已恢复正常完成的vendor NTF：EoOp `7f 20`与PowerOFF `7f 18`满足pending callback／mode／ID条件时取消计时器，经保存callback完成；合法最少payload分别2／1字节，细节见NFCEE报告。

## staticFeatureCfgComplete的实际SE状态门槛

`0x2a2f57ac8`先停止／删除初始化watchdog；输入status非0会根据L[b73]==1选0x89，否则0xff，再调用ReleaseLibNfcContext。输入成功才进入内联`VerifySEStatus (0x57be8–57ca8)`。令s=L[16e]，F=u32(L+1e8)，I=(L+17d8非NULL)：

| 条件 | 可通过的s；其余走失败 |
| --- | --- |
| I且F==0 | 全部；该分支直接越过比较 |
| I、F!=0且F bit1=1 | s=1或2 |
| I、F!=0且F bit1=0 | s!=1 |
| 非I且F bit1=1 | s=1 |
| 非I且F bit1=0 | s!=1 |

原控制流`0x57c14–57c38`显式优待s=2，不能简单改写成“始终必须eSE connected”。失败在`0x57c58–57c6c`再次选择0x89／0xff并释放上下文；此处没有直接生成0x43，也没有调用底层硬件读电源操作。F在EEPROM验证中也决定SWP参数期望，须与实际配置一致。

`NfceeInitializeComplete (0x2a2f5bc78)`还处理HCI child结果：非零时按b73选0x89／ff清理；成功但L[22d]==1时进入eSE重初始化sequence `0x2b17be9a8`。否则置L[172]=2，按activeSE type、型号及UICC状态选择`0x9d69c`的后续初始化分支，或再调用StaticListenModeRouting；0x0d表示等待异步完成。**该回调名称本身不证明所有层都已完成。** HCI child／session／pipe的完整协议仍是独立未闭环项。

## 0x43从哪里来，哪些链没有证明

PN548 `_NFDriverLoadMW`在`0x2a3055b90`比较**十六进制0x43**并记录eSE power-on failed，最多3次尝试；这个值不应写成NCI线上status0x43。

Comet有可证的SE mode错误来源：UpdateSeInfo的`0x2a2f071ac–07208`仅当L+1a18存在时，清sequence，调用若干下层状态取消函数，然后以`w1=0x43`调用SetSeModeSeqComplete `0x2a2f9c378`。该函数`0x9c414–9c42c`对非零status只保留43／51／8f，其它归ff；`0x9c464–9c490`根据activeSE type计算内部SM完成事件并原样传status。

FindSetModeIntEvent `0x2a2f9e8cc`给type1/2/5/7的成功event为a4/a8/a0/ac，失败为a5/a9/a1/ad。它们是内部事件，不是wire opcode。**目前没有证明上述mode错误43能进入LoadMW的初始化callback，也没有发现“VerifySEStatus的89自动转43”的证据**；不能用同一个数值把两条链强接。

ReleaseLibNfcContext `0x2a2f5b2fc`会移除不应保留的SE缓存、必要时请求NFCC power off；向SM派event0x76并传入原status。b73分支保留不同的重初始化处理；其它分支还做NCI释放／Lib释放。函数名虽为Release，具体清理程度受分支控制，不应称为普通成功callback。

## PN548的枚举是缓存快照与对象协调

`_NFDriverEnumerateSecureElements (0x2a306ed60)`在PN内部执行队列上同步运行block `0x2a306fc48`。该block仅调用`phLibNfc_SE_GetSecureElementList`，输出status与count；函数没有在每次GetList时启动一次线上NFCEE_DISCOVER。输入buffer为3×16字节，count初值3；status非零返回1；输出count>3记录Unexpected count后返回8。

Comet公共API `0x2a2f79874`验证handle和输出指针，L[17bf]/[17c2]/[17c3]==1返回0x6f；特定状态／17c1分支返回0x93；L[17be]==1派download SM，否则正常SM event8。实际 `SM_GetSEListTrans (0x2a2f5ef9c)`遍历L+198开始的5个槽，输出16字节entry：

| entry偏移 | 内容 |
| --- | --- |
| +0，u64 | NFCEE／SE handle，可为Host特例NULL |
| +8，u32 | Lib type；PN548识别1=eSE、2=UICC、5=Host |
| +12，u32 | Lib state；PN548 eSE路径特别检测4 |

`0x5f04c–5f084`对首槽handle=NULL且type5的Host仍输出条目；其它非空槽复制handle及type/state，count随实际输出更新。API本身不验证“至少存在eSE”，也不是APDU可用性探针。

PN548在`0x306f0a0–306f0c8`按type分派；重复eSE／UICC／Host记录日志后忽略该重复项，未知type记录Unknown SE后继续。UICC／Host在`0x306f3dc–3f8`／`0x306f4a4–4c4`构建或更新PN内部+218／+220对象。eSE在`0x306f56c–5d4`先获取controller info，按实际型号选择对象实现，再以state==4传“removed”参数，保存+210对象。

eSE对象创建／更新成功且object+18==1时，`0x2a306f5dc–6ac`尝试恢复：调用NFDriverSetSecureElementPower(driver,1,0)，返回bit0清零后再调用(driver,1,1)。任一步bit0置位会记录Failed to recover SE，但`0x2a306f7ec`跳到`0x2a306f890`继续枚举，最终仍可在`0x2a306fb44`返回0；只有恢复成功分支在`0x2a306f88c`清object+18。这更正了前轮“恢复失败直接返回1”的误读。这里调用的0／1是PN API参数，不能直接改称NFCEE线上mode。完整分支见[PN548就绪与生命周期复核](pn548_ese_ready_lifecycle_20261023.md)。

遍历完成后，若本次未见eSE而旧+210非NULL，`0x306f8c0–988`记录“eSE did not re-enumerate”、free旧对象并置NULL；UICC／Host对旧+218／+220有同样清理。**这些失踪清理最终仍可在`0x306fb44`返回0。** 所以“step6返回0”只能证明这次快照协调流程没有命中显式错误，不能证明eSE对象存在。

## PN548电源入口与待闭环边界

`NFDriverSetSecureElementPower (0x2a307b7a0)`检查driver内部+300限制，按API SE编号选择对象（1→+210、2→+218、4→+220），再经 `NFDriverSecureElement_SetPower (0x2a305b170)` 调用对象+20的函数指针。不同型号实现可能不同；不能跳过这个分派直接替它构造一条固定NCI命令。

`NFDriverSetEmbeddedSecureElementPower (0x2a3073604)`的栈上第二个配置对象首u32是**eSE期望模式：disabled时6，enabled时1**，后续字段零；它不是“configuration type6”、ioctl6或线上opcode6。x1另一个配置对象清零；以两对象调用NFDriverSetConfiguration，返回非零的enabled路径sleep 2000µs并返回1。此前按首字面量将其称为type6的措辞应以此处字段读取及日志为准。

### 追加：eSE对象的实际SetPower绑定与普通链

`NFDriverSecureElementCreate (0x2a305a95c)`分配0x78字节对象；`_createSE (0x2a305ad84)`保存driver、handle、ID与removed字段，再按creator表`0x2b2414780`分派。直接按现有PN548 Mach-O的当前LC_SEGMENT映射读64字节，得到以下绑定；旧info JSON的cache fileoff不适用于重排后的文件，未重解DSC。

| 内部实现type | creator | object+20 SetPower目标 | 本层行为 |
| --- | --- | --- | --- |
| 2 | `0x2a305ecc0` | `0x2a305ed70` | 取object[0]的driver，直接尾调SetEmbeddedSecureElementPower |
| 6 | `0x2a305bdd0` | `0x2a305be90` SetPower_Eos | 记录power cycling，`0x5bf60–5bf68`同样调用SetEmbeddedSecureElementPower |
| 4 | `0x2a3051110` | `0x2a3051188` SetPower_UICC | 记录Not supported；不是eSE实现 |
| 5 | `0x2a3089580` | `0x2a30895f8` SetPower_Host | Host实现；不是eSE实现 |

枚举eSE分支`0x306f594–5b8`对型号识别函数`0x304f548`结果5..12查u32表`0x2a308adf8`，原值`[2,6,2,2,6,2,2,2]`：结果6／9选实现6，其余表内结果选2，范围外默认6。实现type2／6均由`_seTypeToID (0x305ac50)`映射PN SE编号1；不要把实现type2与Comet列表type2=UICC混淆。

普通type2和Eos type6因此都会进入以下**可条件跳步的实际模式链**，不是直接输出一条物理供电ioctl：

| 跨层步骤 | 确切数据／调用 |
| --- | --- |
| PN SetConfiguration `0x2a304b7cc` | `0xb830–b840`从x2第0字段取eSE模式、第4字段取Host模式；日志`eSE=%d host=%d`。已有配置／变更检查可令请求不产生新包 |
| SetSecureElementRouting `0x2a304facc` | 在routing变更分支由`0xc4e4`／`0xca58`调用；eSE期望6且当前6可跳；否则非零期望可先调用SetSEMode(SE1,3)尝试fully power off。期望1在`0xfc08–fc14`调用SetSEMode(SE1,2)，日志称wired mode；期望2的分支请求mode0 virtual |
| PN SetSEMode `0x2a3086c6c` | 取真实SE handle，构造执行队列block`0x2a3087324`；该block在`0x87350–87374`调用Comet `phLibNfc_SE_SetMode(handle, SEhandle, requestedMode, callback, context)`，pending等待callback，成功/失败各自处理 |
| Comet公共SetMode `0x2a2f79a88` | 查真实缓存handle，保存activeSE=L+230；mode2映射内部event8c（FindSetModeTransEvent `0x9db10–9db28`）；pending才保存L+1a18/1a20回调。mode3可按型号降为mode1，不能假定始终真的切电 |
| Off／PwrOff→Apdu | `0x2a2f67ad0`／`0x68df4`把L+238设1，选择sequence`0x2b17beb98`；Off→Apdu还有型号／状态拒绝0x93分支 |
| sequence执行 | SetPowerModeSeq `0x9bde4`／End、SetModeSeq `0x9c09c`／End、SERecoveryGetPipeStatus／Proc，最后SetSeModeSeqComplete。首项可能按缓存与型号跳过；下发时调用`0xb6074`，为standby命令`2f 00 01 desired` |
| 真正NFCEE mode | `0x9c160–9c184`读activeSE handle与L+238交`0xb5db0`，因此上述APDU开启分支为`22 01 02 ID 01`；原mode2并未原样成为wire mode2。Off→PwrOff `0x67fe0–67ff4`将L+238清0，使用同sequence时为wire mode0 |

状态43已额外闭到PN的**SetSEMode**重试：`0x3086fd8`比较43、最多3次；block callback`0x3087498`把输入status原样交结果对象。它与本文前述Comet SetSeModeSeqComplete保留43相容；仍不据此把同值强接到另一条LoadMW初始化callback。

这里保留原函数返回语义：SetEmbedded返回BOOL式0/1，而枚举移除恢复代码按“零后尝试下一步、非零进错误”分支；没有运行验证解释这两个调用点之间的语义差异，不能静态把所有非零一概视为同一层NFCSTATUS成功或失败。

最小无RF后端需要让真实配置、NFCEE发现／移除与mode响应／通知、保存的SE record、HCI初始化及列表快照互相一致；前端只提供transport与控制面不能替后端凭空制造SE身份。未来验证应分别记录原生初始化callback、eSE条目/状态、旧对象清理与恢复结果；Host条目或return0不能单独判成功。

遗留：LoadMW 0x43到具体线上失败事件的端到端来源；完整HCI child/session/pipe与eSE重初始化；所有配置组合的SetPower命令顺序与返回语义差异；移除恢复后真实异步再发现时序；设备断电与持久化语义。本文没有执行任何供电、枚举或APDU操作，也没有证明原生LoadStack通过。
