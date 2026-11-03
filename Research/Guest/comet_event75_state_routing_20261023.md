# 23G90 Comet：event75/76 到初始管理 callback 的状态路由

日期：2026-10-23。结论：**正常 Idle1 上 event5 返回 pending 的初始化事务，event75/76 会命中 Idle 完成表项，并把完成函数的 event 参数恢复为5；并非直接按75调用 InitTransComplete。** 这是离线可达性证据，不是 VM/真实 NFCC 已完成 LoadStack 的运行结果。
本轮仅读取现有 Comet 指令、常量和保留的原 DSC 小段；未执行库/VM/后端、未改系统/门槛/产品代码、未绑卡。纯研究不添加实验编译宏。

## 对象、指针与证据

- 同版23G90原版 `libNFC_Comet.dylib` UUID `AAD82B14-9985-3582-9A57-22047E668A31`；Mach-O SHA256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`。
- 已逐字确认原 DSC /重建 `__text`；`__AUTH.__data` 与 `__DATA_DIRTY.__data` 同样由此前 `comet-config-20261023/raw/section-comparison.json` 确认相同。
- 本轮证据目录 `.build/validation/comet-event75-20261023/routing/`：函数完整摘录、`main-tables.json`（12主状态的全部表项，保留原 encoded word/VA/目标）、官方指针定义摘录。
- 当前表使用 shared-cache encoded 指针，不能将 `8020000122f5e59c` 当实际调用 VA。[Apple 官方 fixup-chains.h](https://raw.githubusercontent.com/apple-oss-distributions/dyld/main/include/mach-o/fixup-chains.h)的 `dyld_chained_ptr_arm64e_shared_cache_{auth_,}rebase` 给出低34位 runtimeOffset；本对象 cache base=`180000000`，目标为 `base+(raw&3ffffffff)`。
- 数据例：`0020000131491470→2b1491470`；函数例：`8020000122f5e59c→2a2f5e59c`，auth1、IA key、addrDiv0、diversity0；`8260000122f5e59c` 同目标，区别来自链 next 元数据，不是另一函数。
- 本次父任务原DSC独立读取 `comet-event75-20261023/integration/native-main-state-directory.bin`（VA`2ae0f7da8`，496B）与 `native-idle-event75-76.bin`（VA`2b1491510`，32B）均与重建逐字相同；目录SHA256 `5f4d58d4b203678b123481a7f926f42f64100fc4445f1573c1534eeb6a67cd55`，见`native-state-table-validation.json`。本文不把 ordinal、链 next 位或函数近邻当事件索引。方法名来自当前日志字符串/函数边界。

## 外层事件与每 NFCC 状态记录

`SM_StateHandler 2a2f022e0`：`x0=driver/type`、`x1=event`、`x2=status/参数`、`x3/x4=附加上下文`；75、76指十六进制内部 event，不是 NCI opcode。
普通 driver 通过 `G=2b1490c00 + i*70`、`i=0/1` 两项查 handle，相等后读 `G+8` 的 NFCC type（`23374–3b8`）。event1 特例以传入 type 工作。
主状态记录 `S=(type==1 ? 2b1491550 : 2b14915c0)`，这两处为运行时零填充区域，不能从磁盘 raw 推断当前运行状态：

| S偏移 | 本次由实际读写证明的含义 |
|---|---|
| `+0` | current state（主表选择依据） |
| `+4` | pending target state |
| `+8` | pending/busy 标志 |
| `+c` | 保存的原操作 event |

`23330–36c` 使用 event减1的无符号范围判断：主事件1..7e进入 `SM_MainStateHandler 2a34`；81..ae进入SE handler916d0；b1起进入下载 handler91bec（先有cd上界）；缺口返回93。
`ValidateSMState 27e0` 在 current<=2/target3/pending1 的初始化中，`28dc–8f4` mask31允许71、75、76；所以普通 pending 初始化的75/76不会被“Stack Not Initialised”过滤。
`MainStateHandler 2b08–34` 对75..7e也放行，不套用普通外部 event 的 pending→6f拒绝分支。

## 主表取址、线性查找与调用公式

当前指令给出的公式（不是按 event 直接取数组）：

```text
state = u32(S+0)
if state < 12:
    table = ptr64(2ae0f7e18 + state*16 + 8)   // 2b60–6c
    row = table
    while u32(row+0) != event && u32(row+0) != cf:
        row += 16                           // 2bb4–bc8
    handler = ptr64(row+8)
```

row字段为 `{u32 event,u32 nextState,authenticated function ptr}`。sentinel cf的handler为0；空handler→93。state>=12或无表的另一分支返回0，也不能仅以返回0证明 callback 被调用。
函数目标经 dyld rebase/PAC恢复后由 `2d38–4c` 的 `blraaz x8` 同步调用，入参保留原driver、x2、x3、x4，event可能按下节被替换。

## 12主状态中75/76的真实表项

slot从0开始，**行VA=table+slot*10(hex)**；表项 next 为磁盘初值，75路径会用运行时 target 改写75行的 next，不能把初值当固定完成目标。

| current | table VA | 75/76 slot | 75/76 行VA | 两行handler VA（名称来自日志） |
|---|---|---|---|---|
| 0 | `2b17bc930` | 无 | cf@`2b17bc940` | null，75/76不会命中callback |
| 1 | `2b1491470` | 10/11 | `2b1491510` / `1520` | `2a2f5e59c` IdleTransComplete |
| 2 | `2b17bc950` | 27/28 | `2b17bcb00` / `b10` | `2a2f63e14` TestModeTransComplete |
| 3 | `2b1490f90` | 75/76 | `2b1491440` / `1450` | `2a2f11ebc` InitTransComplete |
| 4 | `2b1490930` | 42/43 | `2b1490bd0` / `be0` | `2a2f0fb08` DiscTransComplete |
| 5 | `2b1490290` | 42/43 | `2b1490530` / `540` | `2a2f648c4` PollDiscoveredTransComplete |
| 6 | `2b1490560` | 56/57 | `2b14908e0` / `8f0` | `2a2f661d8` PollActiveTransComplete |
| 7 | `2b17bcb30` | 44/45 | `2b17bcdf0` / `ce00` | `2a2f66814` ListenActiveTransComplete |
| 8 | `2b17bce20` | 41/42 | `2b17bd0b0` / `d0c0` | `2a2f66bc8` ListenReceiveTransComplete |
| 9 | `2b17bd0e0` | 41/42 | `2b17bd370` / `380` | `2a2f66f88` ListenSendTransComplete |
| 10 | `2b17bd3a0` | 40/41 | `2b17bd620` / `630` | `2a2f67238` ListenSleepTransComplete |
| 11 | `2b1490230` | 3/4 | `2b1490260` / `270` | `2a2f6748c` ShutdownTransComplete |

重要原始字节（均little endian u32/u64逻辑展示）：

| VA | event,nextState,raw handler |
|---|---|
| `2b14914a0` | `00000005,00000003,8020000122f5d2fc` |
| `2b1491510` | `00000075,00000001,8020000122f5e59c` |
| `2b1491520` | `00000076,00000001,8260000122f5e59c` |
| `2b1491440` | `00000075,00000001,8020000122f11ebc` |
| `2b1491450` | `00000076,00000001,8040000122f11ebc` |

## pending event5为何最终仍进入Idle完成函数

1. Idle current1的event5查 `2b14914a0`：handler=`SM_InitTrans 5d2fc`，nextState3。它选择初始化 sequence并返回其状态（普通序列表`2b17bc6c0`，`5d3b4–3fc`）；并非在此入口直接提交current3。
2. handler返回pending `0d` 时，`MainStateHandler 2d60–6c` 只写 `S+4=row.nextState=3`、`S+8=1`、`S+c=event5`，**不写S.current**。因此异步期间current仍1。
3. `staticFeatureCfgComplete 57d80–98` 在既有 SE/status 校验通过后以 `x0=L[2628],x1=75,x2=0,x3=&L[2628],x4=L` 调SM；其SE校验条件见同轮电源研究，不因状态表闭合而消失。
4. SM此刻按current1查Idle表的75行，先取handler5e59c（`2c0c`），不是按pending target3查Init表。
5. **75分支 `2c30–40`：**把 `S.target` 写row.nextState并写S.current，清pending，`x1=S.saved_event=5`。随后 `2d38–4c` 保留x2=status0、x3/x4并调用已经选中的Idle handler。
6. **76分支 `2c50–68`：**清pending，`x1=S.saved_event`；若原event5则把S.target设为c；不在该分支提交S.current。仍调用Idle handler，x2保留调用者传入的失败值，不能自称已转换为43。
7. 完成handler返回0时，`2d74–78` 将当前row.nextState写S.current；75此前已将该值改为3，76正常仍用Idle行初值1。其他返回/pending会按通用分支处理，可能重入另一个事务，不能无条件省略。

state0表event1→`SM_ConfigDriverTrans 5cf7c`、next1，是普通配置驱动到Idle的表证据；它不代替运行时driver映射或本次实际状态快照。

## 初始callback的同步消费与后续SE事件

`IdleTransComplete 5e59c` 保存x1为event、x2为status。`5e644–648` 对event5跳 `5e7a4`：

- 取 `L+17d8` callback 与 `L+17e0` user，`5e7ac–7b4` 清16字节，防止沿同一保存槽重复消费；callback为空则不调用。
- `5e8f8–904` 同步调用 `callback(driver=L[2628], user=原17e0, status=原x2)`；函数本身 `5e960` 返回status。
- 这个保存槽来自初始 `Mgt_Initialize 74ee8` 的pending注册；不是 `InitTransComplete` 使用的`1aa8/1ab0`。注册、清理、不同槽用途见[初始化callback契约](comet_init_callback_contract_20261023.md)，由同轮独立恢复。
- 因此正常75/status0事务中，callback发生于 `SM_StateHandler` 返回之前；`staticFeatureCfgComplete 57da0` 见返回0后才调用 `SM_SE_Initialize 6b5b0`。
- 6b5b0派82/87/93/98进入SE状态机；这是callback之后的调用顺序，不能称已等待所有SE状态机异步工作完成。本报告不扩解SE子表。

## 可验证条件与边界

- 已闭合静态控制流：**event5/pending且current1、同driver/type映射、保存event仍5、75/status0、有效callback槽 → Idle初始callback(status0)，主状态提交3。**
- 75并非普遍的“LoadStack成功”标志：不同current会调用表中不同handler；无表分支也可能返回0；缺callback、保存event被替换、状态/映射不同均不满足上述条件。
- 本轮无guest状态快照、真实callback trace或原库执行；未证明中间NFCC/HCI/Session/SE条件在vphone均满足，未证明APDU、SE内应用/密钥或Wallet绑卡可用。
- 以上只读恢复可用于后续离线状态约束；不能靠手工派75、填成功响应或跳过前序状态，冒充原版LoadStack验证。
