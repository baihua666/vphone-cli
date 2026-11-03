# 同版 PN548／Comet 的 NFCC 初始化阶段与无 RF 边界

2026-10-23。离线读既有 23G90 副本；不启动／挂载 VM、不执行 HAL、不加载驱动、不改系统／门槛、不绑卡。以下是实际字节分析，不是抓包或运行成功证明。

## 结论

**NFDriverOpen 成功仅是 transport／middleware 上下文准备；完成 CORE_RESET／CORE_INIT 也只跨过第一段。** 原生 LoadStack 还要求芯片能力／FW、CRC、EEPROM／vendor 配置、NFCEE 初始化，以及 PN548 的条件步骤。最小无 RF 后端必须真实维持这些状态与错误，不能拿几帧固定成功回复宣称 SE 初始化可用。

已有代码确有无 RF 产品门控与 no-RF boot 分支；但用户“不需要射频”不等于这些当前产品／控制器判定自然成立。本轮没有修改或执行任何判定。

## 对象、来源和符号可信度

| 对象 | 身份与来源 |
| --- | --- |
| libPN548_API | 实例先前提取并与 23G90 原版逐字核对；UUID `B8EB4BF4-8EDC-3359-89DE-F7D1F5CB2FF9`，source 366.9.1 |
| libNFC_Comet | 本轮从同一 23G90 IPSW 原始 DSC 定向提取；UUID `AAD82B14-9985-3582-9A57-22047E668A31`，Mach-O SHA-256 `6503712f79f71f304061c8a53b1094afaa62d902ddee2a38b60d48b46a5f3313` |
| Comet 原始 text | DSC 与重建产物逐字一致，SHA-256 `852ae02b2369b5ff4c5cda0a5302b5d502b5d1182e0bfc57dacce6a576d624bf`；没有重新挂载实例核对其 Comet |

PN548 导入真正中间件 `/usr/lib/libNFC_Comet.dylib`。otool 对提取产物的部分 stub 注释错误；本轮使用父任务按原 DSC 恢复的 `integration/pn548-island-to-symbol.json`、`pn548-annotated-disass.txt`，不采信把 dispatch／Comet 调用误标成 NFDriverAntennaSelfTest 的旧注释。

私有函数名由所在 LC_FUNCTION_STARTS 区间内日志字面量识别，序列表由实际 data 指针解码；不是原始完整私有符号表。DSC 指针的 34 位 runtimeOffset 语义参考 Apple [fixup-chains.h](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h)，再核对全部 24 个 PN548 step target 均落本版 function start。以下地址为离线未滑动地址，不用于修改。

## 外层准备 → MW 初始化

| 阶段 | 实际入口／调用点 | 已核对行为 |
| --- | --- | --- |
| Open | NFDriverOpen `0x2a30708ec` → block `0x2a308634c` | 分配上下文、选择 primary／secondary／UART／SPMI 等 transport、创建队列；取 middleware 版本并等待异步结果；失败可报 Hardware not supported／SPMI comms error |
| LoadStack | NFDriverLoadStack `0x2a3054d5c` | 检查 loaded 状态、保存 load flags，正常路径调用 `_NFDriverLoadMW` |
| Load MW | `0x2a3055a40` → queue block `0x2a3056754` | 构造 init 参数、通知 callback 与能力模式，发起异步初始化并等待真实状态 |
| 进入 Comet | block 的 `0x2a3056824` → island `0x2a351f080` | 原 DSC 证实目标为导出 `phLibNfc_Mgt_Initialize`，实际入口 `0x2a2f74ee8` |
| 接受 pending／完成 | block 比较返回 `0x0d`，callback `0x2a3056940` | pending 走异步完成；立即错误走 completion／唤醒等待方；不等于 controller 初始化成功 |

Mgt_Initialize 会检查参数与上下文、已有 init callback、download／SMB 模式状态；可因 stack busy、资源不足、NFCC power-on、Hsu baud 等错误退出。正常路径启动库状态机（`0x2a2f75508`），保存上层 callback。底层库的 `phLibNfc_Initialize` 为 `0x2a2f53e70`，在 `...53f0c` 调 `phNciNfc_Initialise` `0x2a2fb4fa0`。

## 真正的 reset／init：已定位代码与解析入口

`phNciNfc_Initialise` 在 `0x2a2fb50dc`／`...5148` 将 NCI sequence `0x2b17bc2c0` 装入上下文，再启动 sequence engine。实际表顺序：

| 发送／执行 | 处理响应 | 下一阶段 |
| --- | --- | --- |
| `phNciNfc_InitReset` `0x2a2f458c8` | ProcessResetRsp `0x2a2f45c88` | Init |
| `phNciNfc_Init` `0x2a2f45dec` | ProcessInitRsp `0x2a2f45f48` | CompleteInitSequence `0x2a2f46354` |

Reset 构造位于 `0x2a2f45be8–...45c40`：内部 descriptor 从 `0x2a2fc36a8` 取 `{type=1,GID=0}`，opcode 字段为 0，payload 指向 context `+0x24`，长度为 1，经 `phNciCoreMuxNfc_Tx`（`0x2a2f0a9a0`，NCI mux index=2）提交。初次上下文在 `...b51d4` 设置该 reset 状态字段；重初始化可能保留不同状态，不能把单一 payload 值当所有路径。

Init 构造在 `0x2a2f45e3c–...45e80`：同内部 descriptor、opcode=1、payload 长度=0，经 CoreIfTxRx `0x2a2f0a880`，超时参数 `0x7d0`。后续定向核对纠正了此前按邻行误读的 `{3,1}`：精确常量为 `{1,0}`，原DSC与重建文件相同；沿真实encoder已恢复 Reset `20 00 01 r`、Init `20 01 00`（均不含可选CRC）。详见 [本轮厂商编码证据](comet_vendor_initialization_20261023.md) 和 [同版帧分析](pn548_user_frames_crc_20261023.md)。

已恢复的最低响应检查：Reset 处理器要求 payload 长度为 3、status 成功，读取 NCI version 和 reset type，并有 keep-config／reset-config 与 CRC 调整路径；Init 处理器最低 payload 长度为 17，并检查 status（包含特定 `0xf1` 分支）、RF interface count 上界 8、能力／包长等字段。RF interface 数可为 0，不代表其它能力字段可省略。对应 RSP 必须通过帧层与响应匹配后才到这些检查。

当前已证基本序列消费上述 RSP；**尚未证明每条初始化分支都必须额外收到 CORE_RESET_NTF，也未完整列出所有 vendor／download NTF 的最小字段**。代码确实注册错误、reset／固件等异步通知，CompleteInitSequence 还含 CRC 配置失败、损坏包后 flush／重发读请求的恢复路径。不能把“只需两个 RSP、没有任何异步通知”写成整套 Comet 契约。

## Lib 层配置与 NFCEE

实际 Lib sequence 表 `0x2b17bc6c0–0x2b17bc800` 包含以下阶段；SPMI reset-delay callback 也在 `...59db4–...59df0` 设置此表并按 16 字节 process／response pair 计数：

| 按表中顺序分组 | 函数／边界 |
| --- | --- |
| 初始 NCI、传输设置 | Initialize／InitializeProcess；ConfigHsuBr／ReApplyHsuBr；CrcConfig；ReInitialize |
| FW 与私有能力 | GetFwType；MwFwCompatibilityChk；EnablePropExtn；DisableStandbyMode |
| 控制器配置 | GetEepromParams；InitSetConfig；SetEepromParams；SetListenModeRouting；mapping |
| 再初始化／SE 接口 | ReInitialize；EnablePropExtn；SwpIntfControl；GetNfceeIntfCfg |
| NFCEE discovery | EnableNfceeDisc `0x2a2f55b9c`／ProcessNfceeDiscRsp `0x2a2f55c5c` → InitializeComplete `0x2a2f55d38` |

**这是实际序列表，不是所有产品都无条件逐项执行的保证。** 已见依据 EEPROM 的 MW log 标记跳过 set-config 的分支（`...551e8–...55214`）、SPMI client reset／NACK 计时重试、recovery 状态，以及不同 SE 类型／no-RF boot 的配置选择。尚未完整重建各产品全部跳步条件与每个 vendor 参数的响应语义。

EnableNfceeDisc 还检查多个接口配置字节及上下文标志，符合特定组合会直接完成而不发 discovery；其发送路径在 `...55c28` 调 `phNciNfc_Nfcee_StartDiscovery` `0x2a2fb5a78`，再进入 NFCEE sequence `0x2a2f6c110`／NfceeDiscover `0x2a2f6bbf8`。**NFCEE discovery 是内部 SE 枚举，不能与对外 RF polling 混为一谈。**

Lib 的 `InitCb` `0x2a2f597b0` 有实际 `Force No RF boot in case of SE300S` 路径，依赖其解析到的设备类型；没有证明 vphone 当前后端自然满足该分类，也没有改分类。PN548 的 step 6 随后通过 `_NFDriverEnumerateSecureElements` `0x2a306ed60` 查询 Comet 保存的 eSE／UICC／Host 列表；已定位 GetSecureElementList 导入，并有移除 SE 后 power-cycle／重新枚举失败处理。

## PN548 的 24 步与 RF 条件

MW 成功后，LoadStack 使用实际表 `0x2b2414540`，stride 24 字节，循环上限 index 23。重要条件：step flag `0x8` 会在 `NFProductHasNFCRadio()` 为 false 时跳过（`0x2a3055158–...5160`，岛符号已核对）；另有 primary／secondary、load flags、loaded 状态及硬件支持门控。**用户的无 RF 目标不授权更改这些条件。**

| index | 函数地址（统一前缀 `0x2a305`，特别标注除外） | 实际语义 | 有 `0x8` RF 门控 |
| --- | --- | --- | --- |
| 0 | 6998 | 注册 NCI／FWDL 通知 | 否 |
| 1 | 6ccc | controller／stack 信息 | 否 |
| 2 | 6f40 | baud 配置 | 否 |
| 3 | 72ac | CRC 配置 | 否 |
| 4 | 7508 | EEPROM 验证／eSE 上电检查 | 否 |
| 5 | 7870 | write counters | 否 |
| 6 | 7aa4 → `0x2a306ed60` | 枚举 SE | 否 |
| 7／8 | 7ad8／7ae4 | HCE Type A／B 配置 | 是 |
| 9／10 | 7af0／7d88 | LPCD assist／dynamic BBA | 是 |
| 11 | 7f4c | RF logging | 是 |
| 12／13 | 815c／83cc | 温度通知／AIO temperature restriction | 是 |
| 14 | 8c50 | generic A Tx standby timeout | 是 |
| 15 | 9238 | 当前函数只返回 0 | 是 |
| 16／17／18 | 9240／93a8／9608 | ECP／VAS shortcuts／ISO15693 调制配置 | 是 |
| 19 | 9ae4 | 私有条件设置，未完整命名 | 是 |
| 20 | `0x2a306307c` | SERM power save | 是 |
| 21 | 6748 → `0x2a3070120` | virtual-mode routing（表有失败标签） | 是 |
| 22 | 9b90 | 当前函数只返回 0 | 否 |
| 23 | 9b98 | standby 策略 | 否 |

RF 门控为 false 也不会自动跳过通知、controller info、CRC、EEPROM／eSE 检查和 SE 枚举。反之有 RF 能力的原生路径仍可在“不实际发射”的需求下配置 RF 参数；它不等于执行天线收发。应保留当前真实条件，而非把表全部裁掉。

step flags 还区分错误处理：`0x80` 且该 step 返回 `0x0d` 可触发卸载／重新 LoadMW／从头执行；重试计数达到 7 退出并记录 Max retries reached；`0x40` 允许该 step 的其它错误继续。缺少这些标志的失败会终止加载并清理。此处是状态机分析，不是建议触发或跳过检查。

## 下载与失败恢复的条件

- LoadStack 先查询 `NFProductAllowsWiredInDLMode()`；只有此能力与调用 flags 的相应组合成立，才会进入 DL-only 路径，或在 LoadMW 返回特定 2／14 错误后继续 download 模式。**不能把所有初始化错误都转成 download 成功。**
- DL-only 路径设置待执行 index=24，从而不跑普通 0–23 配置表；但它与正常 loaded／SE 可用状态不同。单独 `_NFDriverConfigureSEInDownload` `0x2a3056240` 经已核对 `phLibNfc_Mgt_eSeCfgDnldMode` 控制 SE download 状态，不能替代普通 NFCEE 初始化。
- LoadMW 有 eSE power-on 专门重试分支（最多 3 次尝试）、FW/API 不兼容、需要 reboot、DL session already open、SPMI follower 不响应等分别处理。失败路径可调用 TML power 操作／UnloadStack；错误码含义必须结合所在层，不能把所有 `0x0d` 都解释成同一事件。

## 目前可以验证到哪一级

1. **离线协议／CRC 层**：核对 header、长度、CRC、reset/init 构造与解析器边界、分片及错误；不需要 guest，也不证明 vendor 状态机通过。
2. **独立无 RF 控制器状态模型**：真实维护 reset→init→capabilities→所选 vendor/EEPROM 配置→NFCEE／SE 生命周期→data exchange，正确处理 timeout／reset／通知／恢复；未完成 vendor 回复语义前应显式失败，不能发送假成功。
3. **原生 LoadStack／wired APDU**：还需 guest 前端、真实 transport、当前产品门槛与完整后端；本轮不进入。NFCEE 枚举和普通 APDU 成功仍不能证明支付 eSE 可信身份、个性化或 Wallet 绑卡可行。

后续 [Comet命令与LoadStack核对](comet_no_rf_loadstack_commands_20261023.md) 已恢复主要vendor配置、正常FW接口兼容检查及EEPROM日志／配置修复子循环。仍未闭环全部参数／持久化、download固件传输／签名、所有条件通知及完整HCI／SE wired状态机；没有声称能用固定payload通过这些步骤。

证据在 `.build/validation/nfcc-protocol-20261023/init/`：24 步原始小片段与 steps-expanded.json、Comet 两层 sequence 小片段、command descriptors、function-start／字符串／调用索引与关键函数反汇编。原始大 DSC 可在父任务收尾清理；保留上述最小证据，不需要运行 middleware。仅新增本报告及忽略的研究产物。
