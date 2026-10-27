# 23G90 Comet：初始API回调注册、event75／76与一次性消费

2026-10-23；仅离线读取现有同版Comet及状态表证据。未执行库、VM、HAL／SE API或后端，未修改产品／系统／门槛、绑卡或新增空编译宏。

**初始初始化API的回调槽是 `L+17d8/17e0`；在正常pending初始化事务中，event75／76确实可以到达它的消费点。** 该消费者先清空槽，再按`(driver,user,status)`调用保存的函数。`Main_InitTransComplete`里的`1aa8/1ab0`属于RawCtrlMsg事务，不能按函数名误认为同一个初始化回调。

## 证据身份与调用约定

对象：Comet UUID `AAD82B14-9985-3582-9A57-22047E668A31`；Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313`；`__text` SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`。VA均为本版未滑动用户态地址，只用于研究，未使用旧otool错误stub标签恢复导入。

MCP读取 [Arm官方AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst)用于核对寄存器参数传递；实际参数来源、存取偏移和间接调用逐条依据当前机器码，不据ABI文档补造Apple typedef。下文L为Lib context，S为该NFCC对应的主状态记录；S不是L内结构。

## Mgt_Initialize：从API入参到槽

`phLibNfc_Mgt_Initialize` `0x2a2f74ee8–75658`入口保存：

| 原入参寄存器 | 保存／用途 | 可直接证明的含义 |
| --- | --- | --- |
| x0 | `sp+28`，查对应NFCC／Lib／ioctl context | driver handle |
| x1 | x20 | 初始化options指针 |
| x2 | x21 | 初始化完成callback函数指针 |
| x3 | x19 | 调用者user/context，允许NULL |

`74fe4–75014`要求options、callback、driver非NULL，options `u32@0≤0f`、`u32@18≤1`、`u32@1c<3`，另有NFCC/profile组合检查。若已有L且`L+17d8`非NULL，`75038–75084`同步返回`6f`，不覆盖旧callback。已有但完成的实例还受下载模式／已初始化状态限制，不是每次调用都重新注册。

新建L的路径在`75384–75434`分配并清零`0x2650`字节，保存driver至`L+bb8/+2628`。`754f8–75508`调用 `SM_StateHandler(driver,event=05,status=0,data=&driver,extra=NULL)`。

**仅这个调用返回pending `0d`时**，`75514`写`L+17d8=原API x2`，`75518`写`L+17e0=原API x3`，然后返回`0d`。返回pending仅证明异步事务已接收，不是初始化成功。

SM同步返回其它状态时走`75580–755d0`，释放／解除L映射；`b3`专门转`b4`，其它转ff，不注册这两个回调槽。参数错误、资源失败、busy等也走同步返回；不能假设所有API调用均承诺后续callback。本轮没有执行或验证注册前后的并发／重入时序。

## event75／76如何变回原初始化操作05

完整主表恢复见[状态路由报告](comet_event75_state_routing_20261023.md)，本轮已交叉读取其 `routing/0x2a2f02a34.txt` 和 `main-tables.json`。只复述与callback相关的必要边：

1. 当前main state1的表 `0x2b1491470`，event05项`0x2b14914a0`指向`SM_InitTrans 0x5d2fc`，target state3。
2. 该操作返回pending时，`MainStateHandler 0x2a2f02a34`的`2d60–2d6c`保存`S+4=target3,S+8=1,S+c=原event05`，current仍为state1。
3. 后续event75在state1查到项`0x2b1491510`，event76查到`0x2b1491520`，两个函数指针都指向`IdleTransComplete 0x5e59c`。
4. event75在`2c30–2c40`提交current=原target3、清pending，并将用于调用的event读回`S+c`，即05。event76在`2c50–2c68`清pending、读回同一原event05；它不提交current3，并对初始化失败另写target12。
5. `2d38–2d4c`实际间接调用表项函数时，x1=恢复的原event05，x2保留输入status，x3保留data。因此完成函数看到的不是x1=75／76。

这条可达性以**正确NFCC映射、当前仍为state1的pending event05事务、表项和事务字段未被其它流程改变**为条件。不能将任意时刻注入event75都解释为初始化完成，也不能把75这个事件编号自身当成status0的强制转换。

## IdleTransComplete：实际消费条件、status和签名

`IdleTransComplete` `0x2a2f5e59c–5e978`入口把x1存x22（原管理操作event）、x2存x19（status）、x3存x21（data），并从driver重新查L。函数本身不重新判断main-state编号；它依赖上面的状态表路由。

- L为空时不调用任何管理callback，尾部仍返回输入status。
- `5e63c–5e650`明确只对**原操作event05**进入`5e7a4`的初始化槽分支。其它操作走shutdown／测试／ioctl等不同槽，未知event直接结束。
- 非零输入status先传给`0x487fc`的记录路径；零status走`0x10070(...,0)`。随后x19仍是原status，不在初始化分支改为成功、ff或43。

初始化槽的准确顺序是：

```text
5e7a4  savedCallback = L[17d8]
5e7a8  savedUser     = L[17e0]
5e7b4  memset(L+17d8, 0, 16)   // 一条str q0，先清函数和user两槽
5e7b8  driver        = L[2628]
5e7c0  if savedCallback == NULL: skip
5e8f8  x0 = driver
5e8fc  x1 = savedUser
5e900  x2 = originalStatus
5e904  blraaz savedCallback
```

所以签名在本调用点为 **`callback(driverHandle, userContext, status)`**，没有第四个response／data参数。上层输入data不由这条callback传出。completion函数自身`5e960`返回同一status。

当前staticFeature成功派发路径给event75的status是0，则该回调收到0；event76若带错误89／ff或其它原状态，这里按原值交出，不能凭函数名或通用错误表改成0／43。状态生成及最终PN548返回仍由配套完成链报告核对，不能用本槽替代整个后端成功证据。

**在此consumer内一次性消费成立：调用前清空16字节，重复进入会读到NULL而不再调用旧函数。** 这不等于全系统的并发／重入安全证明，也不声称其它错误清理消费者采用相同顺序。

## 为什么1aa8不是初始初始化回调

`Mgt_RawCtrlMsgTransceive` `0x2a2f7b1e0`入口保存原API x3为callback、x4为user；`7b374–7b388`提交 **event46**。pending后`7b39c/7b3a0`写`L+1aa8/1ab0`，与`Mgt_Initialize`的event05和17d8槽分离。

`Main_InitTransComplete` `0x11ebc`使用`event-6`索引跳表`0x2a2f126b8`；本轮对event46精确读取signed32元素（fileoff`127b8`），以ADR基址`0x2a2f11f64`计算目标，结果为 **`0x2a2f12054`**。该分支读取／先清`1aa8/1ab0`，在`120b4–120c4`实际调用四参 **`callback(driver,user,response,status)`**。

因此“InitTransComplete中有callback”只能说明该状态下某项操作完成；它不能证明初始API callback已经被消费。字段相似、日志名称含Init、以及都返回NFCSTATUS，都不足以把这两条契约合并。

## 另一个pending错误消费者及验证边界

`InvokePendingCb` `0x40d00`附近也会优先检查17d8，`40d7c–40dd4`按同样三参调用，再于`40dd8`清空槽。**这条是调用后清空，与Idle consumer调用前清空不同。** 本轮只保留这项可见差异，没有扩展所有异常恢复调用者，亦未以“全局严格只调用一次”概括所有路径。

证据在Git忽略目录 `.build/validation/comet-event75-20261023/callback/`：两个API、两个completion完整定向反汇编，InvokePendingCb小片段及`init-vs-raw-callback.json`的寄存器／跳表静态复核。目录0700、文件0600。静态复核只校验本版地址与字段关系，未运行Comet或创建控制器成功trace。

本轮补齐“event75／76能否到原始API callback”的离线可达路径；实际型号/profile是否走到这些表项、通知乱序／超时／恢复组合、真实异步调用次数、PN548最终结果和Wallet能力仍需分别验证。本报告没有声称原生LoadStack已通过。
