# 23G90 PN548：eSE 对象生命周期、就绪检查与数据请求前置条件

2026-10-23；仅离线核对已保留同版 PN548／Comet 字节、函数索引和修正后的反汇编。不执行 Apple 库／VM／HAL／后端，不改系统／门槛、不绑卡、不解包大 DSC、不写产品代码。未运行 APDU 或取得就绪 trace。

## 结论

**PN548 的“已枚举”只检查对象指针非空；“OS Ready”也可能是默认允许或读取缓存。** 枚举成功、eSE 对象存在、removed 已清、Comet SE 状态机完成、数据请求被接受、实际 APDU 往返必须分别验证。

本轮修正一处前轮控制流误读：`_NFDriverEnumerateSecureElements` 内，removed eSE 的 power-cycle 恢复失败**记录错误后继续遍历，仍可能返回0**，且对象 removed 标志保持1；不是在此处直接返回1。下文给出完整地址，避免与其他 `...5f...` 函数混淆。

来源：PN548 UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`，使用已按原 DSC 核对导入的 `nfcc-protocol-20261023/integration/pn548-annotated-disass.txt`；Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`，SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。新证据 `.build/validation/comet-se-post-init-20261023/pn548/`（0700／0600）。VA 均为未滑动地址；字段偏移均为十六进制。

配套：[后置 SE 状态机](comet_se_post_init_routing_20261023.md)、[最终成功判据](comet_final_success_predicates_20261023.md)、[child／Session／pipe](comet_hci_child_completion_20261023.md)、[电源／枚举及型号绑定](comet_ese_power_enumeration_20261023.md)。本报告对上文指出的恢复失败分支优先于旧报告措辞。

## 从 Comet 缓存到 PN 对象的实际连接

令 P 为 PN548 driver，D=`*(P+18)` 为 PN 内部 context，E=`*(D+210)` 为 eSE 对象。D+218／220 分别为 UICC／Host，不能把这些 PN 对象与 Lib context 的 slot 混用。

`_NFDriverEnumerateSecureElements @0x2a306ed60` 是 LoadStack step6 的实际调用目标。它先清 D[2fb]，申请最多3项、每项16字节的列表，并在 **D+230 队列**通过 dispatch_async_and_wait 执行 block `0x2a306fc48`。

block 在 `0x2a306fc64–fc80` 调 Comet `phLibNfc_SE_GetSecureElementList`，保存16位 status；该调用读取已有 Lib 缓存，不发新的 NFCEE_DISCOVER。Comet 普通条目为 `{handle:u64,type:u32,state:u32}`，Host 可为 NULL handle、type5；来源见前轮 GetList `0x2a2f5ef9c` 分析。

| 枚举条件 | 原控制流／结果 |
| --- | --- |
| API status 非0 | `0x2a306ee50–ee58` 分支；`0x2a306ef70` 返回1 |
| 输出 count>3 | `0x2a306ef78–ef84` 拒绝；错误路径返回8 |
| type1 eSE | `0x2a306f56c–f5d0` 获取 controller info、选择实现、把 `state==4` 编码为 removed，传 handle 给对象协调 helper |
| controller info 获取失败 | `0x2a306f584→fba0` 专门错误路径，不等同“没有eSE” |
| type2 UICC／type5 Host | 分别更新 D+218／220；重复已见类型记录日志后忽略，未知 type 记录后继续 |
| 正常协调结束 | `0x2a306fb3c–fb44` 释放临时列表，返回0；没有“至少一项eSE”的最终断言 |

GetList 的 state 是 Lib 列表字段。Comet 后置 SE FSM 的 current 是另一张状态表；二者不能因同为数字而视为相同状态。

## 对象如何生成、更新与绑定

`0x2a306fc90` 接收 slot 地址及 driver／实现 type／removed／Comet handle：已有对象时在 `0x2a306fca4–fcc4` 直接尾调 `_createSE @0x2a305ad84`；否则在 `0x2a306fcd8–fce4` 调 Create并存入 slot。

Create `0x2a305a95c` 在 `0x2a305a9b8–a9dc` calloc 0x78字节并调用 `_createSE`。creator 返回false时 `0x2a305aa90–aa98` free并返回NULL。这只是对象分配／方法绑定，不是读硬件确认。

`_createSE` 在 `0x2a305add8–ade0` 写入：

| E 偏移 | 内容 |
| --- | --- |
| +0，u64 | P driver |
| +8，u64 | 本次 Comet 列表 handle |
| +10，u32 | PN API SE编号；eSE实现映射为1 |
| +14，u32 | 具体实现 type（普通2或 Eos6等），由 creator 写入 |
| +18，u32 | 本次 `Lib list.state==4` 的布尔值 removed |
| +20..68 | creator 设置的各方法指针；+20 SetPower，+68 IsOSReady |

因此同一个 E 指针可在下一次枚举被重新初始化，handle／removed／方法绑定会变化；指针非空不代表它仍对应上一时刻的有效端点。

型号选择在 `0x2a306f594–f5b8`：分类5..12查表 `0x2a308adf8=[2,6,2,2,6,2,2,2]`，范围外默认6。实现 type2不是 Comet列表type2(UICC)。

普通 creator `0x2a305ecc0` 设置 +20→`0x2a305ed70`，+68=NULL；Eos creator `0x2a305bdd0` 设置 +20→`0x2a305be90`，+68→`0x2a305e850`。两条 SetPower最终都可进入 SetEmbeddedSecureElementPower→配置／模式链，不能把对象建立等同物理供电。

## removed、恢复失败与释放

对象协调返回真且 E[18]==1 时，`0x2a306f5dc–f5ec` 进入 `_NFDriverRebootRemovedSE`：

1. `0x2a306f68c–f69c` 调 SetSecureElementPower(P,1,0)，以**返回 bit0**判断；bit0为1进入失败日志。
2. 第一调用 bit0为0才在 `0x2a306f6a0–f6b0` 调(P,1,1)；第二次 bit0为0才到成功路径。
3. 成功在 `0x2a306f88c` 清 E[18]，之后继续遍历。
4. 任一步失败在 `0x2a306f6b4–f7e8` 记录两组错误，`0x2a306f7ec` **直接跳到f890继续遍历**；不清 E[18]，也不在此返回1。仍可到 `0x2a306fb44` 返回0。

这里的 bit0检查是本调用点可证语义；不能把 PN BOOL、Comet NFCSTATUS、NFCEE wire mode统一解释。电源 API参数0／1也不是直接 wire opcode。

| 生命周期出口 | 实际对象处理 |
| --- | --- |
| 本次未见有效eSE／对象协调标志不成立 | `0x2a306f8b0–f8c8` 检查旧 D+210；`0x2a306f974–f988` free旧E并置NULL，随后仍可返回0 |
| UnloadStackAndLeaveHWEnabled 分支 | `0x2a30549b4–49cc` 清恢复标志，free D+210并置NULL；UICC／Host也清理 |
| 异步 context销毁 block `0x2a3071b70` | `0x2a3071bac–1bc0` free并清eSE slot，之后释放其它对象及context |
| 独立 RecoverESE block `0x2a308514c` | 重新 GetList；无type1时 `0x2a30852f8–5320` free／NULL并以0唤醒等待方；有type1时 `0x2a3085434–543c` 更新handle／removed，或创建新对象，removed时另走SetMode恢复 |

所以 step6 return0、RecoverESE等待结果0均必须附带“eSE对象是否存在、handle是否更新、removed是否仍1”的快照。失踪清理后旧 E／Comet handle不应继续当有效引用；本轮没有运行验证其跨线程所有权保障。

## “已枚举”与“OS Ready”实际检查什么

`NFDriverIsSecureElementEnumerated @0x2a3072fcc` 对API SE1仅在 `0x2a307300c–3014` 读取D+210，`0x2a30730f0–30f4` 返回是否非NULL。它不检查 E+8、E+18、Session、pipe、mode或 APDU回应。

`NFDriverSecureElement_IsOSReady @0x2a305bc70`：E==NULL走断言／abort；E+68存在则尾调该方法；**E+68为空在 `0x2a305bcf8` 直接返回1**。普通type2 creator将该槽清空，因此这个“真”是默认策略，不是硬件探针。

Eos `IsOSReady_Eos @0x2a305e850` 不发请求，只读取全局 u32 G=`[0x2b1490210]`，并依据调用参数 OS（Transceive的第三参）决定是否允许：

| 条件 | 返回 |
| --- | --- |
| G为1或3且 OS==0 | 0，拒绝 |
| G为1或3且 OS!=0 | 1 |
| G为其它值 | 1；其中G==0且OS==0记录 unknown-state警告，仍允许 |

原判断在 `0x2a305e878–e89c`，返回在e958；不要把未知缓存默许当“JCOP已确认就绪”。Eos creator `0x2a305bdd8` 每次初始化将G清0；GetOSMode_Eos `0x2a305ceec–cf00` 从其模式缓存更新G。这里的G与D+210对象指针虽然偏移文字相同，但地址域完全不同。定向引用保存在 `global-os-state-xrefs.json`。

## PN数据入口实际前置条件

`NFDriverSecureElementSendCommandToOS @0x2a30737d0` 构造命令数据后调用 `NFDriverSecureElementTransceive @0x2a3073b30`；它不是“只要对象存在就发”的独立旁路。

| Transceive检查／执行 | 确切位置／含义 |
| --- | --- |
| recovery拒绝 | `0x2a3073b78–3c3c`：D[2fb]==1，记录SE in recovery；有错误输出指针时写4，返回无数据 |
| 控制器信息 | `0x2a3073c54–3c5c` GetControllerInfo必须成功；失败走错误输出1／无数据 |
| OS策略 | `0x2a3073c60–3c80`：load flags D+250 bit1未设时，取对应对象并调用IsOSReady(E,OS)；返回bit0为0拒绝 |
| 对象／底层handle | `0x2a3073c84–3c98` 重新取对象，要求非NULL且E+8非NULL；否则No SE for transceive，走错误输出4／无数据 |
| 并行使用协调 | `0x2a3074810` 调 AcquireSE，后者 `0x2a306764c–7654` 等待 D+228 semaphore；本调用点未用返回值分支，不能把“调用了Acquire”说成已证明获得资源 |
| 实际发起 | `0x2a3074840–488c` 将请求提交到D+230队列的block `0x2a3087c58`，然后等待callback结果 |
| block再次取handle | `0x2a3087c98–7cd8` 重新按SE编号取对象，传E+8（对象已无则NULL）及transferInfo给 Comet `phLibNfc_eSE_Transceive` |
| 等待与失败 | `0x2a3074890–48b4` 等待原结果、释放等待对象、signal semaphore，再按低16位status选择成功／恢复／错误路径；pending不是数据成功 |

这些入口局部检查没有把 E[18]==0作为统一直接门槛；它们仍可被下层 handle验证、Comet状态机、传输与回应校验拒绝。不可因此宣称 removed对象可用，或默认IsOSReady就能让APDU走通。

Comet真实导入由 island `0x2a351f260`核对到 `phLibNfc_eSE_Transceive @0x2a2f79e2c`。其入口另检查Lib context／busy状态、SEhandle／transferInfo／主callback非空；`0x2a2f79f1c–79f58` 的 L22b／17bf／17c3／17c2／17c0等标志可返回6f。一般路径在 `0x2a2f7a074–7a0b4` 将handle与Lib的四个slot匹配并保存activeSE；特定分支还单独要求匹配L+1b8。随后按type及transfer字段选择内部event，只有实际SM返回pending才保存数据callback（`0x2a2f7a12c–7a188`）。此处不展开后续APDU报文／pipe执行，不从API名推断成功。

## 与后置四个 SE 事件及并发顺序的边界

[后置路由专项](comet_se_post_init_routing_20261023.md)已恢复：82进入Common；87／93／98的handlers `0x2a2f675d4/67680/6772c` **读取**L16e／16d／16f。状态1返回输入0；状态2设置独立SE FSM current=5后返回d6；其它返回ff。SetSECurrState `0x2a2f9257c` 不写Lib list状态／handle、不调用PN枚举或通知、不发NCI包。

因此目前可证连接是 **Comet先维护Lib列表 → PN GetList快照 → 对象创建／更新**；四个后置事件只是基于相同Lib状态归一独立SE FSM，不能冒充“自动创建PN的E对象”或新的发现通知。

event75同步消费初始callback时，PN callback在 `0x2a304ee28–ee60` 写W结果并signal cond、解锁；回到staticFeature后才派四事件。PN等待线程因signal可以继续；step6 GetList又通过D+230的dispatch_async_and_wait调用。**仅凭这些可见顺序，本轮未证明四事件与PN后续所有访问之间的跨线程／队列完成屏障；也不能推断必然竞态。** 尚需结合Lib调用锁、回调执行线程、队列串行属性和实际trace，核对当前profile的先后保证。

## 最小验收记录与遗留

至少分别记录：GetList status/count与type1条目；E是否存在及本次handle、实现type、removed；OSReady的具体实现／参数／缓存来源；实际Lib SE FSM状态、Session／pipe／mode；数据请求是否仅pending、最终status、真实回应与超时／移除恢复。任何一项局部0／1均不能代替其余项。

同日后续已补齐[普通APDU静态契约](comet_apdu_minimum_contract_20261023.md)，含模式、数据、credit、WTX与最终callback。仍未验证：所有通知／RecoverESE组合的完成顺序、完整对象并发所有权与销毁屏障、各型号OS值含义、全部raw／下载边界及真实SE数据事务。报告没有尝试绑卡、伪造SE身份或实现模拟后端。
