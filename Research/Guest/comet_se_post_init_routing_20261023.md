# 23G90 Comet：初始callback之后的SE状态机四事件

日期：2026-10-23。结论：**`82/87/93/98` 在这里是同步的软件子状态归一，不是一轮新的 NFCC/HCI 初始化或等待SE就绪。** 其派发函数忽略每次状态并固定返回0，因此不保证四类SE均可用。
本轮纯离线，只读已有 Comet/反汇编/原DSC小段；未执行Apple库/HAL/VM/后端、未挂载VM、未改系统/门槛/产品代码、未绑卡。纯研究不添加实验宏。

## 对象与原字节核对

- 同版23G90原版Comet，UUID `AAD82B14-9985-3582-9A57-22047E668A31`；重建Mach-O SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。
- 指令已与原DSC text逐字确认；本轮表从保留原DSC目录 `comet-event75-20261023/integration/native-main-state-directory.bin` 与 `native-auth-data.bin/native-dirty-data.bin` 读取，再与重建逐项比较。
- **6个SE状态表、98个16B行及6个目录指针均一致**，本代理记录 `comet-se-post-init-20261023/routing/{se-tables,static-validation,constants}.json`；父任务亦独立复核同98行，见其 `integration/independent-se-tables.json`。
- 函数完整定向摘录保存在本轮 `routing/0x<VA>.txt`；函数名来自本版日志字符串和函数边界，不借用旧版私有符号。
- cache encoded指针按低34位runtimeOffset加base `180000000` 恢复；例如 `8020000122f675d4→2a2f675d4`。[Apple官方fixup-chains.h](https://raw.githubusercontent.com/apple-oss-distributions/dyld/main/include/mach-o/fixup-chains.h)定义该布局；原指针和索引均保存在JSON，未把链next/PAC元数据当函数VA。

## 调用顺序：callback已经先发生

[上一轮主状态路由](comet_event75_state_routing_20261023.md)已证明正常pending event5收到75/status0，进入Idle消费者、清初始callback槽并同步回调，然后SM返回。
`staticFeatureCfgComplete 57da0` 仅在上述SM返回0后调用 `SM_SE_Initialize 6b5b0`。
后者从常量 `2a2fc3738` 读取4个u32：`82000000 87000000 93000000 98000000`（little endian）。
`6b5f8–60c` 顺序调用 `SM_StateHandler 022e0(driver=L[2628],event,x2=0,x3=&L[2628],x4=L)`；`6b610–618` 不检查返回值，继续下一项；`6b638` 固定返回0，连L为空亦如此。
四event均为十六进制内部事件，**不是线上NCI GID/OID、NFCEE ID或新增wire命令**。

## 独立状态记录、初始化与busy门

`SM_SEStateHandler 916d0` 沿同版两项driver映射 `G=2b1490c00+i*70` 查NFCC type。
定义 `S=(type==1 ? 2b1491550 : 2b14915c0)`，与L不同；四记录：`R_k=S+10+k*10`，这里偏移均为十六进制。

| k / 本轮event | R_k.current | target | pending | saved original event |
|---|---|---|---|---|
| 0 / `82`，通用SE槽 | `S+10` | `+14` | `+18` | `+1c` |
| 1 / `87`，eSE槽 | `S+20` | `+24` | `+28` | `+2c` |
| 2 / `93`，UICC槽 | `S+30` | `+34` | `+38` | `+3c` |
| 3 / `98`，SE2槽 | `S+40` | `+44` | `+48` | `+4c` |

`SM_Init 913cc` 在对应主状态尚0时，加载常量 `2a2fc3bd0={1,c}` 与 `3bd8={0,6}`，给主current1/targetc；4个SE记录均current0/target6/pending0（`91430–44`或`9148c–a0`）；未在此循环证明saved event一并清零。
这些状态在运行时零填充/可写区域，磁盘零值不是当前guest快照。

`917f4–91810`：主 `S.pending==1` 时，仅9f..ae及8d/8e获例外；四init事件不在例外内，返回6f。
`91874–918e8`：四事件都在81..9c范围；**任一** `R0..R3.pending==1` 也返回6f。普通无pending时，`918fc–91a08` 选择上表对应k和该记录current。
因此回调或其他代码重入后仍可能busy；派发函数没有重试/聚合这些失败。

## SE表目录与实际四行

目录公式来自 `91a50–5c`：`table=ptr64(2ae0f7ed8 + current*16 + 8)`，**索引是所选SE记录current，不是event或SE种类**。
`91aa0–ab4` 逐16B扫描 `{event,nextState,handler}` 到匹配event或cf sentinel；`91ad4–d8` 空handler→93。表为空另一分支可返回0，不能以此证明已处理事件。
该入口未见对current先做小于6的检查；本轮只对原目录提供的合法0..5状态下结论。

| SE current | 目录pointer slot | 原encoded pointer | table VA | 四行的slot |
|---|---|---|---|---|
| 0（SM初始值） | `2ae0f7ee0` | `00200001317bd650` | `2b17bd650` | 1/2/3/4 |
| 1（Off） | `2ae0f7ef0` | `0020000131490e30` | `2b1490e30` | 1/2/3/4 |
| 2（Virtual） | `2ae0f7f00` | `00200001317bd6b0` | `2b17bd6b0` | 1/2/3/4 |
| 3（Apdu） | `2ae0f7f10` | `0020000131490d00` | `2b1490d00` | 1/2/3/4 |
| 4（PwrOff） | `2ae0f7f20` | `00200001317bd820` | `2b17bd820` | 1/2/3/4 |
| 5（Removed） | `2ae0f7f30` | `00200001317bd8d0` | `2b17bd8d0` | 1/2/3/4 |

1..5的状态名称由各表ModeSetFrom/To日志与相应nextState交叉识别；0仅能从SM初始化证明为初值。
**六表四行完全同义**，`row VA=table+slot*10(hex)`：

| event / slot | nextState初值 | handler VA / 本版名字 | current0表行VA / 原handler word |
|---|---|---|---|
| `82` / 1 | 1 | `2a2f5f0f0` CommonTrans | `2b17bd660` / `8020000122f5f0f0` |
| `87` / 2 | 1 | `2a2f675d4` SE_eSEInitTrans | `2b17bd670` / `8020000122f675d4` |
| `93` / 3 | 1 | `2a2f67680` SE_eUiccInitTrans | `2b17bd680` / `8020000122f67680` |
| `98` / 4 | 1 | `2a2f6772c` SE_eSE2InitTrans | `2b17bd690` / `8040000122f6772c` |

## 四个handler究竟做了什么

| handler | 直接读取/判断 | 返回与状态副作用 |
|---|---|---|
| Common `5f0f0` | 仅保存传入x2并记录日志 | `5f144` 返回原x2；本轮输入0，所以同步成功。 |
| eSE `675d4` | `67620` 读 `L[16e]` | 值1保留原x2；值2调用 `SetSECurrState(driver,k1,state5)` 后返回d6；其他值/无L→ff。 |
| UICC `67680` | `676cc` 读 `L[16d]` | 同上，值2写k2 current5，返回d6。 |
| SE2 `6772c` | `67778` 读 `L[16f]` | 同上，值2写k3 current5，返回d6。 |

`SetSECurrState 9257c` 重新查driver映射，在 `92610–14` **仅写 `S+10+k*10` 的current**，固定返回0；不改L[16d/e/f]、List句柄或PN548对象。
后三个handler对值3也走ff；不能把HCI/Lib记录中的“已发现/活动”数值直接当这个入口接受的值1。
这些handler没有新NCI发送、HCI请求、timer注册或异步回调，返回集合在本轮输入0下是 `{0,d6,ff}`，不是pending0d。
值1路径由通用状态机提交row.next1（Off）；值2路径先直接置Removed5，后通用错误分支仅清pending，保留5；ff不提交row.next，保留原current。
所以哪怕全部返回0，四记录也只是归到软件Off状态；不是切入Apdu状态3或证明wired APDU可用。

## 通用同步/异步转换：存在，但不能套给四init事件

`91b80–88` 同步调用选中handler；后续分支：

- 返回0：`91bbc–bd0` 提交 `R_k.current=row.nextState` 并清pending。
- 返回0d：`91b9c–bb4` 保存 `R_k.target=row.nextState`、pending1、原event，不在此提交current。
- 返回其他：`91bd8–be4` 清pending，不通用提交current；handler本身的直接修改（如Removed5）继续保留。
- a0/a4/a8/ac成功完成族在 `91b58–7c` 将target写current和row.next、清pending、恢复saved event；a1/a5/a9/ad失败族只清pending并恢复saved event，再交对应完成handler，x2保留原status。
- 这是selector/转换代码支持的通用族；保留6表中没有ac/ad行，故不能声称所有SE2异步完成均已闭合。完整98行见JSON，本轮不扩解后续ModeSet/transceive全部协议。

`SM_SE_TransComplete 67b5c` 是多个真实异步行的handler，会按恢复后的原event消费ModeSet、Transceive、ATR等各自callback槽；**不是初始管理callback槽17d8/17e0**。本轮四init handler不走pending，因此无须假设它们会等到该消费者才完成。

## 忽略return的实际影响与可验证边界

1. 正常无busy且四槽原状态合法：82将通用槽归1；87/93/98按相应L字节归1、5或保留原值；这是本轮精确恢复的最小软件契约。
2. `6b5b0` 不检查0/6f/d6/ff，不因某项失败停止后续项，也不将失败汇总成自身错误；它的0不能代替四次SM结果。
3. 初始管理callback已先同步发出，后置结果在此链没有回流去改写那个已消费的callback；不能把d6/ff自动转换为LoadMW的43。
4. 本链不写SE列表来源字段、不直接更新PN548枚举缓存、不创建SE硬件或SE应用；这些与FSM软件状态相互独立，record生命周期由同轮独立研究承接。
5. 无运行时状态快照/原库执行/真实trace；未证明vphone具备对应NFCEE/HCI/SE后端，未证明APDU、凭据或Wallet绑卡可用。
