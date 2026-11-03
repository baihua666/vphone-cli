# 23G90 PN548：APDU最终callback、WTX与等待结果

2026-10-23；离线读取保留的同版PN548／Comet，不执行库／VM／HAL／后端，不改系统、不绑卡。没有产品实现或空实验宏。字段偏移与状态均十六进制，VA为本版未滑动地址。

## 来源与边界

PN548 UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`，文件SHA256 `4960bb6a3c44fabd86c6b045aa6049b2047eca2dbb53ba3ab13026522e1ed220`。本轮将保留原DSC text274720B与该文件对应section重新逐字比较，一致，text SHA256 `3cdef11de07715817aa33a3ca91cc16220df2761b2b729d3c78246fcc3542270`。函数边界来自本版function-start，导入使用已核对island的修正反汇编。

证据 `.build/validation/comet-apdu-20261023/integration/`：9个函数完整摘录和`pn-callback-proof.json`；对应原text字节逐段相同。WTX除数常量从当前Mach-O section按VA实读为1000.0，不据日志猜单位。本轮未重新读取guest文件确认部署身份。

配套：[Comet数据与最终consumer](comet_apdu_data_callback_contract_20261023.md)、[模式切换](comet_apdu_modeset_contract_20261023.md)、[对象与就绪前置](pn548_ese_ready_lifecycle_20261023.md)。以下P=PN driver，D=内部context，W=callback等待对象，T=本次tx context，X=transferInfo。

## 发起与缓冲区

`NFDriverSecureElementTransceive 0x2a3073b30`先通过recovery／对象／OS策略等原门控；不能从本节的pending推导这些检查已在vphone实际通过。

| 位置 | 实际动作 |
| --- | --- |
| `0x2a3074714–4738` | 分配T共18字节；T+0初值2c37，T+8为WTX预算29a（十进制666），T+10保存P |
| `0x2a307474c–4754` | 分配2c37字节接收buffer；这不是HCP／NCI单片长度 |
| `0x2a307477c–47c8` | 分配30字节X；X+0/+8为发送ptr/len，X+10/+18为接收ptr/capacity，+28为调用选路字段；+24另由原selector表赋值，不能据此命名为timeout |
| `0x2a3074810–483c` | 调AcquireSE；创建W、增加其引用计数并保存W+10=T。Acquire调用点未检查返回值，不声称已证明取得资源 |
| `0x2a3074840–488c` | 在D+230队列执行block `0x2a3087c58`；后者重新取当前SE对象handle |

block在 `0x2a3087cb0–7cd8` 实际调用Comet `phLibNfc_eSE_Transceive(driver,handle,X,mainCB,WTXCB,W)`：主callback=`0x2a3087de4`，WTXcallback=`0x2a3088120`。Comet立即返回pending0d时等待异步完成；其它返回先清D[2ff]，立即把原status交 `0x2a304ee00(W,status)` 并release W，不能假定所有调用都产生数据callback。

## 主callback：成功条件与六参来源

Comet普通数据consumer的实际调用为 `(driver,user,0,&L270,L284,status)`；user即W，`L270`描述接收指针和u32长度。consumer先清18c8／18d0再调用；完整状态机／wire契约见数据专项。PN主callback只在此入口读取x1=W、x3=response descriptor、w5=status，不把第四参或其它metadata当status。

| `0x2a3087de4`分支 | 实际判定与副作用 |
| --- | --- |
| W为空或当前u64(W)==2c | `7e18–7e24`进入“already signalled timeout”日志分支，跳过正常响应长度处理 |
| 普通路径 | 读取T=*(W+10)，NULL触发原assert；先保存原status |
| status0 | `7ef4–7f04`要求response非NULL且u32(response+8)>1；成功在`8000–8004`将该长度写T+0；否则局部改status为d00d |
| status d9 | 独立reset通知路径，保留d9；它不会变成普通APDU成功 |
| 其它非零status | 保留错误，不写成功长度 |
| 正常收尾 | `80a8–80b4`按T+10取得driver并清D[2ff]；`80b8–80c8`将status交Signal并release W |

**timeout日志分支仍会跳到Signal／release，不是完全丢弃晚到callback。** 不能从本代码宣称全局严格一次或无晚到竞态；本轮没有运行验证其跨线程所有权。正常status0且len>1只是本层接受数据，不证明SW1/SW2代表应用成功。

主callback本身不复制响应bytes；Comet已使用X中的接收buffer，PN在此登记最终长度。兼容实现必须让响应buffer、容量与最终长度一致，不能只回status0或只修改长度。

## WTX不是最终数据callback

Comet WTX consumer以五参 `(driver,user,SEhandle,&timeout_u32,4a)` 调PN secondary，和主六参callback分离。`0x2a3088120`只在w4==4a、x3非NULL且T+8预算非0时读取u32(x3)，**除以1000.0转换成秒**，交 `0x2a304e8d0`更新W的deadline，然后预算减1。

该deadline更新函数在独立mutex下取clock_gettime(id4)的当前时间，再加本次秒数，不是无条件在旧deadline上累加。它只更新等待时间，不给APDU成功结果。

- 无WTX info／错误status：记录相应错误，不写普通响应成功。
- 预算归零：`0x2a30883c4–83dc` Signal(W,2c)并清D[2ff]，不把无限WTX当正常进展。
- 此WTX callback不消费主数据callback；Comet直到最终数据consumer返回后才清WTX槽。其timer与credit wait／HCI command response timer应分别维护。

## 等待、外层返回与错误恢复

`0x2a304ee00`在mutex内写u64(W)=status并signal cond。`NFCallbackMutexWait 0x2a304e970`使用未完成sentinel `0x00000badcafef00d`，进入时调用deadline更新，当前硬编码double60.0秒；WTX随后可重设deadline。等待器核对结果、相对时间和cond返回，不以一次signal当作成功。

等待器超时路径包含serial dump、restore分支、`NFSimulateCrash`、条件延长或排队退出；不能把该外层总等待简单描述成“所有超时统一返回2c”。2c在WTX预算耗尽等明确Signal路径出现。具体运行策略仍须原profile／环境证据。

`0x2a3074890–48b4`等待并release W、signal SE semaphore，再取结果低16位：

| 结果 | 外层路径 |
| --- | --- |
| 0 | `4c30`后按原日志／选项分支到`5858–5864`，以接收buffer和T登记长度建立NFData；分配成功才返回数据，并将错误输出清0 |
| 43 | power-on错误分支，同一请求最多3次尝试；不是所有错误都重发 |
| 41 | `4d00–4d0c`清recovery并重新枚举，然后继续原错误处理；不等于当前请求获得APDU回应 |
| 其它错误 | 原诊断、SPMI查询／恢复与错误映射分支；不得统一改为数据成功 |

返回NFData表示本层收到并包装了bytes；应用协议／SW1-SW2判断归相应调用者和真实SE端点。超时、重试、移除后的旧回应不得拼接到另一次事务。本轮没有发起请求、模拟APDU答复或验证原库并发行为。
