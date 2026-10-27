# 23G90 Comet：SE record生命周期与后置控制面对象条件

2026-10-23；只读既有同版二进制、反汇编与保留小段。未执行Apple库／VM／HAL／后端，未修改产品、系统、门槛或卡状态，也未重新提取DSC。

**SE列表中的非空句柄、接口状态1和后置SE子状态，属于不同层。** 当前eSE记录由NFCEE通知关联；removed后句柄可继续非空，而Session／pipe和Lib接口状态已经失效。event87只按接口状态归一软件状态，不读取record、建立pipe或证明APDU可用。因此后置控制面就绪必须核对一组相互一致、仍有效的对象条件。

## 来源与前轮更正

Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`，Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`，`__text` SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。VA为本版未滑动用户态地址，不是补丁／运行时偏移。复用已核对二进制，不信任旧otool外部stub标签。

**更正：当前`UpdateSeInfo`把eSE NFCEE ID识别为`c0`，不是`80`。** connected分支`0x2a2f0695c–06974`的`cmp80/b.gt`只是查找树界值；随后`06a94/06a9c`分别比较81／c0，c0才进入`06ef4`的eSE关联。removed分支`06a18–06a24`同样比较81／c0。ID80在这组Lib分派中走unknown；旧报告将比较界值当eSE ID是误读，不是物理ID发生迁移。

MCP核对 [NXP固定版本NCI定义](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)只用于NFCEE管理和active／inactive／removed通用术语。Apple当前c0／81分类、内存对象及条件均以机器码为准。

已先读[发现报告](comet_nfcee_discovery_20261023.md)、[供电与枚举](comet_ese_power_enumeration_20261023.md)、[child／Session](comet_hci_child_completion_20261023.md)；不重复其完整线上配置和SE路由表。L=Lib context，N=NCI context，H=HCI context，R=单条NCI NFCEE record。

## NCI记录由谁拥有、怎样创建

`NfceeDiscNtfHandler` `0x2a2f6c33c`从`62 00`通知payload读ID、wire status、protocol列表与TLV。ID0／ff和未知status拒绝；正常status0／1进入connected路径，status2走独立removed路径。

记录不是逐个malloc的独立SE对象：**`R=N+f80+i*68`，i最多0..4，内嵌于NCI context。** `NfceeGetDevIndex` `0x0e58c`以mode1按R[1]查ID，未找到再mode0找R[1]==0的空槽；查找最多5槽。新设备成功后`6c764–6c76c`增加N[f68]，与发现RSP的预期数量N[f69]不同。

| R字段 | 正常创建写入／所有权 |
| --- | --- |
| byte0 | `6c534–6c538`先置ff；是内部标记，**不是“record不存在”判据** |
| byte1 | NFCEE ID；当前eSE需与Lib分派的c0一致 |
| u32+4 | wire status0→1；wire status1→0（`6c544–6c55c`） |
| byte+8／+9起 | protocol数量／列表；合法值及上限见发现报告 |
| byte+e／ptr+10 | TLV数量／已分配并复制保存的TLV区（`6c6f4–6c754`） |
| +18起 | 解析后的TLV描述；普通tag0／1的value指针指向保存区内部（`StoreTlvInfo 6ca10`） |

在成功通知路径`6c640–6c670`，传给Lib的是临时事件结构`{connectedFlag@0,ID@1,recordPtr@8}`，其中recordPtr指向N内嵌R，不是接收payload指针，也不是独立分配给Lib所有的对象。N[e8]必须有上层callback才会投递；没有callback不等于N表未解析。

`InitializeComplete` `0x55d38`的`55e1c–55e38`把`SENtfHandler 0x05cd8`以selector2注册到`0xb6660`，在此之前的Host合成条目与NCI记录相互独立。

## Lib槽：借用record、类型、mode与连接状态

Lib内部槽为16字节`{recordHandle@0,type:u32@8,activationMode:u32@c}`。所见布局如下；index是Lib内部索引，不是wire ID。

| 对象／内部index | Lib槽 | type | 接口byte | 来源 |
| --- | --- | --- | --- | --- |
| HCI network／0 | L+188 | 4 | L[16b] | NFCEE ID01通知；保存R并绑定HCI连接对象 |
| Host／1 | L+198 | 5 | 不用eSE的16e | 初始化合成；handle=NULL、type/state=`{5,1}` |
| UICC／2 | L+1a8 | 2 | L[16d] | ID02 connected通知 |
| eSE／3 | L+1b8 | 1 | L[16e] | IDc0 connected通知 |
| SE2／4 | L+1c8 | 7 | L[16f] | ID81且满足原ba8分类条件 |

`UpdateSeInfo`内eSE正常connected `06ef4–06f4c`要求L[2e8]==1、L[16e]!=1、L[22b]==0；它清Session完成flag L[228]、增加L[16a]，保存`L[1b8]=R`。R非NULL才置L[16e]=1、type L+1c0=1、mode L+1c4=`(R.u32@4!=1)`。mode是转换后的Lib枚举，不应直接复制wire status。

这条关联仅借用R；没有在该分支malloc或复制整条NCI record。若L[172]==2，还会调用`LaunchChildDeviceSequence(L,index3)`，启动后更新L[171]；不满足原门控的重复／恢复中通知会被忽略或另走恢复，不能每收一个connected就无条件新建对象。

HCI network ID01的`06ba8–06c30`要求L[2e8]==1，先清L+1a8开始的`0x40`字节槽区，保存R到L+188，置type4、连接状态1，并将H`+318=N,+320=HCI network record,+3c0=L`。因此重新建立HCI network可以影响后面的SE关联，不能把旧L+1b8跨这一阶段当永久有效。

child启动进一步要求选中槽handle非NULL、相应接口byte不为2；L+230只保存当前选中槽的地址，不是另一个拥有record的分配。Session／pipe查询与缺失pipe后的清会话重发现详见child报告；单条R关联成功没有跳过这些步骤。

## Host synthetic与GetList快照

`InitializeComplete 55dc0–55dd0`直接置L[16a]=1、L+198=NULL、L+1a0=`{5,1}`。常量`0x2a2fc3710`精确为u32`[5,1]`；此Host无需任何NFCEE通知或实体SE句柄。

`SM_GetSEListTrans` `0x5ef9c`普通路径从L+198起最多扫描5个16字节槽：Host即使handle=NULL，只要type5仍会输出；其它条目handle非NULL才复制。**它不检查L[16e]、Session、pipe或后置SE子状态，也不发重新发现命令。** 特殊下载分支还会直接输出eSE槽，必须与普通快照区分。

所以非空列表、count≥1、Host state1，均不能证明有eSE；removed后仍保留handle的条目也可能出现在快照。输出16字节handle只是本进程借用N记录的指针，不能跨释放、重启、重建或其它context当稳定设备身份使用。

## 后置82／87／93／98：软件状态归一的实际要求

`SM_SE_Initialize 0x6b5b0`在初始API callback之后，按常量`0x2a2fc3738`依次派82／87／93／98，均带status0；不检查四次返回值，最终固定返回0。完整SE表由同轮路由研究恢复，本报告只接对象条件：

| event／对象 | 实际handler／读入条件 | 正常无pending的结果 |
| --- | --- | --- |
| 82／Host | Common handler只透传输入0 | 子状态变软件state1；不需要真实NFCEE record |
| 87／eSE | `0x675d4`只读L[16e] | 1→返回输入0，提交state1；2→设state5 Removed、返回d6；其它ff |
| 93／UICC | `0x67680`只读L[16d] | 同上 |
| 98／SE2 | `0x6772c`只读L[16f] | 同上 |

这些handler没有读取槽handle、R[1]、protocol／TLV、Session、HCI pipe或NCI能力，也没有发NCI初始化。故仅观察event87成功／软件state1，会漏掉record失效或控制面其它环节。state1在该表中是Off软件状态，不能解释为实际测得物理断电或APDU会话已经打开。

## 移除、失效与释放并非同一动作

IDc0 removed且H有效时，`06a18–06a90→06d3c`先清L[228]，置H[330]/H[332]=ff，仍把通知里的R保存在L+1b8，置L[16e]=2。随后按APDU事务／mode／discovery／恢复状态选择通知、终止或恢复；`22b`表示恢复在进行，会影响后续connected接受。初始化期间另有`06e54–06e80`保存removed条目、type1／接口2和L[2f0]=1的路径。

**removed不等于立即free(R)，也不保证R+4统一写成2。** 已有ID的removed分支`6c434–6c4ec/6c514–6c524`可在旧R上处理reason并投递removedFlag；Lib按该事件更新失效状态。因此R非NULL或旧R+4仍像active，都不能覆盖L[16e]=2／Session0／pipeff的事实。

`ReleaseNfceeCntx 0x6f6f4`按N[f68]遍历，从N+f90（即R+10）释放保存TLV区并清指针；**本函数未清R的ID／数量字段，也不释放内嵌R或N本身**。StartDiscovery `b5aec`先调用它，不能仅凭函数名声称整个NFCEE表已清零。GetDevIndex的mode2另有删ID／释放TLV／递减数量逻辑；本次removed通知的直接调用未用mode2，不应强接成同一步。

完整NCI释放`0x6f798`在`6fa94`调用上述TLV清理，最后`6fd70–6fd84`free(N)并清全局NCI映射；所有借用R指针随owner失效。Lib `ReleaseLibNfcContext 0x5b2fc`则按Session flags分别撤销eSE／UICC／SE2槽：例如L[228]==0且L+1b8非NULL时减少L[16a]，清handle与type；它不是free该R。

非保留错误分支还执行NCI reset/release（type2）、清L+c10，再由`ReleaseMemory 0x5bea0`释放HCI及其它Lib资源，最后`5c0f0–5c0f8`free(L)，并清Lib全局映射；b73等恢复分支可保留不同资源，不能把所有错误都概括为已free。异步callback／快照中的旧handle须随这些生命周期重新核验。

## 可只读核验的eSE控制面对象条件

以下是证据约束的验收组合，不是新造的单个Apple ready flag：

1. 正确实例／NFCC映射中的N和L均存活，L+c10指向当前N；eSE槽type1且handle指向当前N的有效R，而非仅Host type5／NULL。R[1]=c0、protocol／TLV与本次发现一致，不能用比较界值80或旧地址替代。
2. L[16e]=1由本次接受的connected关联建立；R活动值、Lib mode、Session／EoOp以及实际配置相互一致。不存在removed／pending恢复失效，不能仅检查handle非空。
3. 当前profile真实完成child／Session／pipe与HCI逻辑连接／credit。HCI callback和应用SE通知注册是不同层：`SE_NtfRegister 0x7a438`在event0d获准后才存L+1a28/+1a30；Unregister `0x7a564`在event0e获准后清这16字节。这是监听回调注册，不创建或认证SE。
4. 后置event87在正确子状态记录中完成预期软件归一，未停留pending／Removed；另三对象按其实际存在／禁用条件核对，不能从总函数固定返回0推导四者全成功。
5. APDU API还要求当前已枚举handle匹配：`eSE_Transceive 0x79e2c`普通路径`7a070–7a0b4`扫描槽并保存activeSE，`7a0b8–7a100`按type1、rawflag／mode选8d／8e，否则86；入口busy／下载门控另在前面。通过后置87没有代替这些前置条件，更没有证明SE应用、密钥或Wallet能力。

证据目录 `.build/validation/comet-se-post-init-20261023/records/`保存上述函数的定向反汇编及静态字段关系；0700／文件0600。没有创建guest探针或模拟成功数据。遗留：所有乱序／重复NTF的覆盖和释放、各恢复profile的完整对象重绑、回调并发与悬空指针动态验证、APDU事务和SE内部应用，均不能由本轮离线图谱宣告通过。
