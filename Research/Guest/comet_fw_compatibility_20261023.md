# 23G90 Comet：FW 类型、接口兼容性与控制器字段来源

2026-10-23，仅离线读取现有提取物；未启动／挂载 VM，未执行库／HAL，未修改系统、门槛、驱动或绑卡。下文是当前字节约束，不是固件加载成功证明。

## 结论与证据范围

**无 RF 仍须维持控制器能力、厂商信息、FW 类型及接口版本的一致性。** CORE_INIT 可声明 RF interface 数量为 0，但后续按实际 manufacturer info／feature byte 选择 FW 查询与兼容版本；不能只返回空能力或固定成功状态。

对象为同版 23G90 IPSW 的 `/usr/lib/libNFC_Comet.dylib`，UUID `AAD82B14-9985-3582-9A57-22047E668A31`；提取 Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。原 DSC 与重建 `__text` 已逐字核对，SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`；本轮未重新挂载实例核对 guest Comet。

私有方法名来自当前函数区间内日志字面量；地址均为未滑动 VA。完整反汇编复用 `nfcc-protocol-20261023/user-frames/comet-disass.txt`，函数索引复用 `init/comet-functions.json`；本轮小片段及常量证据在 `.build/validation/comet-config-20261023/fw/`，目录 0700、文件 0600。未上传固件。

通过 MCP 查阅 NXP 官方 [nci_defs.h](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h) 仅核对通用 NCI 命名；以下 Apple 分支、阈值与私有 opcode 全由当前二进制恢复，不借用 Android／Linux 的芯片版本表。

## 内部 descriptor 到 wire：已闭环并纠正上轮常量读取

当前 `0x2a2fc36a8` 精确 8 字节为 `01 00 00 00 00 00 00 00`，即两个 LE32 `{1,0}`；`0x2a2fc3550` 为 `01 00 00 00 0f 00 00 00`，即 `{1,15}`。上轮将前者记为 `{3,1}` 是按相邻常量误读，本轮已通知主任务修正。

CoreIfTxRx `0x2a2f0a880` 在 `...a910` 检查 descriptor[0]=1，再经 NCI mux index=2；CmdTx 保留 descriptor。CoreBuildCmdPkt `0x2a2f0cc94` 在 `...ccd8` 读 descriptor `+4`=GID、`+8`=OID；`...ce24` 取 OID 低 6 位，`...ce30` 写长度，`...ce70` 写 `h0=0x20|GID`。这是调用链与字段读取证据，非直接把内部枚举当 wire MT。

| 操作 | 当前构造入口／关键指令 | NCI 命令（不含 transport CRC） | 对应 RSP header |
| --- | --- | --- | --- |
| CORE_RESET | InitReset `0x2a2f458c8`，构造 `...45be8–45c40`；descriptor `{1,0}`，OID0，payload=context+24、长度1 | `20 00 01 r`；`r` 来自当前 reset 状态，不能统一写死 | `40 00 len` |
| CORE_INIT | Init `0x2a2f45dec`，`...45e3c–45e80`；同 descriptor，OID1、长度0 | `20 01 00` | `40 01 len` |
| GetFwType | NCI Cmd `0x2a2f1ed04`，`...ed58–ed70`；descriptor `{1,15}`、OID6、NULL payload／长度0 | `2f 06 00` | `4f 06 len` |
| GetFwInterfaceVersion | Cmd `0x2a2f466a8`，`...466fc–4671c`；同 descriptor，OID0x19；上层入口先清空 payload pointer／length | `2f 19 00` | `4f 19 len` |

两条 FW 命令通过 CoreIfTxRx 的 timeout 参数均为 `0x7d0`；它是内部超时参数，非线上字段。`0x19` 恰好既出现为线上 OID 也可能出现在其它 ioctl／enum 中，必须按此构造链区分；本段未把 ioctl 编号映射为线上 opcode。CRC 是否附加取决于已协商传输状态，见 [帧与 CRC](pn548_user_frames_crc_20261023.md)。

## CORE_RESET／INIT 的字段与失败条件

令 `P` 为已去除 NCI header／CRC 的响应 payload；`N` 为 NCI context，`L` 为 Lib context，二者不能混用。

| 处理器 | 当前检查与消费 |
| --- | --- |
| ProcessResetRsp `0x2a2f45c88` | context NULL→1；上游 status=0x2c 或 payload 长度不为3→0xff；`P[0]!=0`→0xff。成功后 `P[1]`→`N+1c`（日志明确为 NCI version），`P[2]!=0`→`N+20`（reset configuration boolean）；另有 CRC 状态调整／ioctl，其结果仍可能失败 |
| ProcessInitRsp `0x2a2f45f48` | 长度<17→0xff；`P[0]==0xf1`→0x51（日志：Suica/VAS express／transaction in progress）；其它非零→0xff。`n=P[5]`，0合法、>8标记失败；能力与后续变长字段仍被读取；成功还调用 core 配置／通知 timer 相关方法 |

CORE_INIT 成功分支的来源链（`...45fa8–46118`）：

| payload 字段 | NCI 保存位置／含义 | Lib 消费 |
| --- | --- | --- |
| `P[1..4]` | `N+0..3`，4字节 NFCC features | `P[4]` 经 GetNfccFeatures 输出→`L+c40`；参与平台子类与兼容版本选择 |
| `P[5]` 与 `P[6..6+n)` | `N+4` 与 `N+5...`，RF interface count／列表 | 数量0不会阻止继续解析其它字段 |
| `b=6+n; P[b]` | `N+d`，max logical connections，日志 `...43de8` | 控制器能力仍需内部一致 |
| `P[b+1..b+2]`（LE16） | `N+e`，max routing table size，日志 `...43e2c` | GetNfccFeatures 另导出该值减5（`...b724c–54`） |
| `P[b+3]` | `N+10`，max control packet payload，日志 `...43e6c` | 后续命令包长约束 |
| `P[b+4..b+5]`（LE16） | `N+12`；本轮只确认存储，不强命名 | 未完整恢复全部消费者 |
| `P[b+6]` | `N+14`，manufacturer ID（日志 `...43e90`） | 非零才复制下列4字节；0不会合成有效 FW 身份 |
| `P[b+7..b+10]` | `N+15..18`，日志明确 manufacturer-specific info Byte0..3 | 经 `phNciNfc_GetNfccFeatures 0x2a2fb7180` 与 Lib GetNfccFeatures `0x2a2f59930`：info0→`L+bdc`；info1→`L+c01`；`BE16(info2,info3)`→`L+bd4` |
| RESET `P[1]` | `N+1c`，NCI version | 同上述 getter→`L+be1`，不是厂商接口版本 |

实际入口仅做长度>=17的固定检查，不能将它当作任意 `n` 的完整长度验证：manufacturer ID非零路径读至 `P[16+n]`，离线合法结构约束应要求长度>=`17+n`，并检查字段自洽。不能利用残留 context 内容替代省略字段。`info0` 是程序用来分类的平台代码；当前没有把它强命名为商业芯片型号，也没有取得实例真实值。

## GetFwType：查询、推断和回退是不同结果

Lib Cmd `0x2a2fad944` 按以下优先级判断：

1. `L+cc0==1`，或 `L+ba9==1 && byte(L+bd4)>0x0a`，或 `L+baa==1`，或 `L+bb0==1`：调 `phNciNfc_GetFwType 0x2a2fba704`，使用 sequence `0x2b17bbef0`。
2. 否则，在 `byte(L+bd4)&0xfd==0xfc` 时本地归类3；若 ba9或ba8 为1，则该 byte 在 `0xa0..0xdf`→2，其余→1；没有这些分类→3。写 `L+c7c`，立即返回0。
3. 这里读取的是上述 BE16版本值在宿主小端存储中的低字节；不能把它直接叫 FW major。类型1／2／3的业务名称本轮未确认。

NCI GetFwTypeCmd／Rsp／Complete 分别为 `0x2a2f1ed04`／`...1edf4`／`...1f148`：

| 路径 | 响应约束与后果 |
| --- | --- |
| 简短响应 | 长度恰2且 `P[0]==0`；复制 `P[1]` 为 type，返回0 |
| 扩展响应 | 长度>=22且 `P[0]==0`；type=`P[1]`，额外4字节 info=`P[2..5]`；`P[6..9]`更新 NFCC features、`P[10]`为 RF interface count；之后用 `b=11+n`读取与 INIT 同结构的能力／manufacturer info。到末尾调用 core 配置，返回其状态 |
| 失败 | NULL context→1；非零上游状态保留；NULL response、其它短长度、非零 `P[0]`→0xff。扩展路径对 count>8打印错误；本轮不把打印错误等同即时停止，须保留实际后续状态 |
| Complete 的回退 | status非零且 `N+1930==0` 时，改status为0、type为3；若该flag非零则先清flag并保留失败。未在该函数发现重发命令循环；flag含义与所有写入者未闭环 |
| Lib Proc `0x2a2fada74` | wrapper内type为1／2则保留，其余归3，写 `L+c7c`。失败时也写3但保留输入status；异常空buffer／长度0有写3并保留status的路径。故type3或函数返回0都不独立证明查到了真实 FW 身份 |

扩展响应会再更新控制器能力／manufacturer info；离线验证必须保证它与先前 INIT 的身份有一致的状态模型。其 manufacturer非零路径读到 `P[21+n]`，合法结构应有至少`22+n`字节，而非仅满足固定22字节门槛。

## MwFwCompatibilityChk：真实接口版本比较

Lib入口 `0x2a2f54838`：context NULL→0x31。正常代码中，以下分支立即返回0而不发0x19：`L+c28!=0`；`u32(L+bd4)&0xfd==0xfc`；ba8==1且 `((u32(L+bd4)&0xe0)-0xa0)`无符号<0x40；或 ba9／baa／bb0任一为1且`L+c7c==2`。这里只陈述已有路径，未更改或执行这些条件；`c28`完整来源尚未恢复。

其它路径调用 `phNciNfc_GetFwInterfaceVersion 0x2a2fb5948`，先清 `N+370/378` payload pointer／length，再使用 sequence `0x2b17bc2f0`；立即pending值为0x0d，异步完成不是立即成功。

Rsp `0x2a2f46784`：context NULL／上游错误保留输入status；response pointer NULL→0xff。`P[0]==1或5`→0x80（日志称 Rejected/Syntax error，OLD FW）；`P[0]==0 && len==3`才复制 `P[1..2]`到`N+12b0/12b1`并返回0，其余→0xff。Complete `0x2a2f468a4` 仅在status0时把该两字节指针传上层，否则传NULL。两字节是 `BE16`接口版本，不是 RESET 的NCI version或INIT 的manufacturer版本。

Lib Process `0x2a2f54948` 在 `...54990/549b8`读16位并rev16；按当前分类选择期望值：

| `info0`分类来源（`0x2a2f59930`） | 实际 Lib flags／优先条件 | 期望接口版本 |
| --- | --- | --- |
| `0x42` | ba8=1 | `0x0015` |
| `0xa2..0xa4` | ba9=1 | `0x002f` |
| `0xb1/0xb2` | baa=1；若 `P[4]==2` | `0x002c` |
| `0xb1/0xb2` | baa=1；其它 `P[4]`，且未命中特别flags | `0x0037` |
| `0xba` | baa=1；由feature byte选bae或baf，二者都走该值 | `0x002c` |
| `0xd0` | bb0=1，bb1=bb2=0 | `0x0003` |
| `0xd1..0xd3` | bb0=1，bb1=1 | `0x0025` |
| `0x60` | bb0=1，bb2=1 | `0x0008` |
| 未分类 | 无匹配优先条件 | `0xff`，Invalid platform |

在完整上下文中应按flags优先级执行（ba8→ba9→baa→bb0/bb1/bb2），上表仅展示 getter新建分类的对应关系。比较相等→保留传入status；实际更高→0x81（FW TOO NEW）；更低→0x80（FW TOO OLD）。本函数未重发、降级或启动下载；不能把“较高接口版本”视为兼容，也不能自行挑一个期望值伪造控制器身份。

## 可以独立离线验证的边界

- 常量精确偏移、descriptor字段与encoder路径可以验证4条命令头；FW查询各自的 RSP长度、status、字节序可形成解析约束。
- RESET NCI version、INIT manufacturer info版本、vendor0x19接口版本是三组不同来源；测试数据必须分别建模，不能互相替代。
- 可对每个已观察分类列出“相等／过低／过高／无字段／未分类”的负向约束；这只能验证离线模型与分支理解，不是向原生栈喂成功响应。
- 当前只恢复正常 NCI FW身份／兼容检查；download协议、镜像签名／SVN、anti-rollback、恢复状态、所有NCI通知与外层重试／下载决策未在本报告闭环。`GetFwType`回退3不证明无需真实FW或无需后端。
- 无RF也不删除这些非射频初始化要求。厂商配置、EEPROM、NFCEE与最终 LoadStack completion 仍由主任务分别整合；当前未声称完成原生LoadStack、SE会话或Wallet绑卡。
