# M0宿主无RF原型：真实jCardSim执行与故障恢复

2026-10-23；承接[原型方案](nfc_no_rf_minimum_prototype_plan_20261023.md)。本轮已实现并运行M0，
范围仅宿主自有协议模型＋真实jCardSim测试applet。未启动／挂载目标VM、改guest／系统／VM门槛或绑卡；
没有执行原Comet、HAL、PN548或nfcd。M0结果不能提升为原生LoadStack／Wallet可用。

## 结果与实际链路

**真实SELECT、双nonce echo、未知INS，以及credit、分片、超时和断连恢复已通过，最终108项断言检查通过。**
链路为Swift契约驱动器→内存NCI/HCP子集→完整APDU TCP adapter→Java瘦wrapper→真实Simulator／
HelloWorldApplet→实际R-APDU→同pipe DATA重组→模型completion。NCI/HCP在宿主内存中运行，
外部TCP传输的是上游VSmartCard长度帧；没有向Apple原库投喂这些报文。

| 验收项 | 实际结果／证据边界 |
| --- | --- |
| SELECT | `00a4040008f05650484f4e4501`，真实返回`9000` |
| 两次nonce | 各次独立UUID文本nonce，INS01／P1=01；实际回应分别为对应nonce＋`9000`，逐字验证 |
| 错误指令 | `80ff0000`→真实`6d00`；模型完成为transport成功，保留applet错误SW |
| credit | 0不提交、0增量不推进、错误CID拒绝；匹配单pair补1仅发一片，`ff→fe`；溢出／多pair明确拒绝 |
| 分片 | 模型1..4096B、多种MPS与流7B拆包；固定字节核对253／254B HCP边界及独立NCI PBF |
| 真实长echo | 248／249／255B nonce；C-APDU253／254／260B，R-APDU250／251／257B，17B MPS双向正确重组 |
| 真实后端超时 | Tests暂停本工具拥有的Java进程，0.15秒monotonic deadline触发；关闭流／清状态／增代次 |
| 断连与恢复 | Tests终止真实Java后端产生EOF；新Simulator→reset／ATR屏障→SELECT→真实echo成功 |
| 旧代次 | 恢复期间向模型注入旧generation帧，不能完成新请求；这项为模型故障注入，非实测Apple并发行为 |
| 其它失败 | busy、Off拒绝、容量不足、credit等待超时、cancel和重复pump不重复完成 |

probe及测试的响应均来自Simulator；Swift只比较预期值和重组，不补SW／成功数据。故障信号只在Tests，
正常probe不包含延时、伪造回答或故障注入。无WTX进度源，因此未实现或伪造WTX。

## 实现与接入边界

源码：[独立模块](../../Integrations/NFCNoRF/README.md)。主要文件为：

- [编解码与credit](../../Integrations/NFCNoRF/VPhoneNFCResearch/NFCFraming.swift)：有界NCI流、HCP重组、分片及有限credit。
- [会话模型](../../Integrations/NFCNoRF/VPhoneNFCResearch/NFCSession.swift)：明确open连接／mode、单请求、deadline、接收容量与generation屏障。
- [真实后端adapter](../../Integrations/NFCNoRF/VPhoneNFCResearch/VSmartCardBackend.swift)：loopback listener、短读写／EINTR、deadline、所拥有子进程的退出／回收。
- [Java wrapper](../../Integrations/NFCNoRF/Java/com/vphone/research/NFCNoRFCard.java)：直接install上游applet，复用Simulator及TCPProtocol，无reloader。
- [正常probe](../../Integrations/NFCNoRF/VPhoneNFCResearch/NFCResearchProbe.swift)与[所属测试](../../Integrations/NFCNoRF/Tests/NFCIntegrationTests.swift)。

当前没有接入VMKit、vphoned、GuestAPI、CoreKit、Launchpad、helper或任何产品target／资源stage。
M0复用仓库独立`swiftc` runner模式而非为本研究新增Xcode工程target：只需要系统Swift／Darwin／Foundation，
没有改变现有CLI的Xcode架构或创建SwiftPM app。未来M1仍先证明14项TML ABI／合法绑定，不能因本轮模型通过
便认为存在原Comet可注入transport入口。

模型同步、单线程且单请求；接收容量和deadline有界。取消／超时／EOF销毁无ID旧流和Java进程，清mode／连接并增代次；
重连创建新Simulator后重新SELECT，不能保留原applet状态或宣称执行回滚。后台运行中的APDU没有可中断保证，
因此不自动重放／复用未知状态。模型4KiB上限不等于真实applet支持4KiB数据；实际applet只验到255B nonce。

## 依赖来源与本机工具链

实际使用Maven Central的`com.klinec:jcardsim:3.0.5.11`发布JAR，不是前轮Licel HEAD `41511ec...`的本机重建。
Licel固定源码构建需要缺失的Java Card API；本轮选择作者发布的兼容3.0.5分支，审查对应sources.jar中的
Simulator、SimulatorRuntime、TCPProtocol及HelloWorldApplet，避免把另一个版本的源码当执行证据。
通过MCP读取[作者README／Maven说明](https://github.com/ph4r05/jcardsim/blob/master/README.md)，
发布[POM](https://repo.maven.apache.org/maven2/com/klinec/jcardsim/3.0.5.11/jcardsim-3.0.5.11.pom)
给出SCM及Apache-2.0；依赖与Java Card API许可不因仓库本体许可而被概括。未在产品中分发任何JAR／SDK。

| 固定产物 | SHA-256 |
| --- | --- |
| jcardsim-3.0.5.11.jar，499643B | `f6c3b6b8140401a47cf39d7b9dbfc052e381474c6c3b22018051024be1fca97c` |
| 对应sources.jar，153519B | `a6a0332427b4232d853a5c402cb056d82ebfdb88e765198977c803d950a19240` |

本机实际使用Microsoft JDK17.0.15 arm64；Swift6语言模式、strict concurrency complete，由Apple Swift6.4编译。
初次调用Maven默认选择JDK26.0.1，JVM在启动阶段SIGBUS；此后显式使用本机JDK17，最终runner不依赖Maven。
错误日志已移到忽略证据目录，不改系统Java默认值。上游TCPProtocol每次connect含3秒等待，未修改其实现。

## 宏关闭与复现

独立宏`VPHONE_EXPERIMENTAL_NFC_NO_RF`，默认未定义／0；默认值集中在
[Configuration/experiment.zsh](../../Integrations/NFCNoRF/Configuration/experiment.zsh)。
Swift所有实验主体／测试均受`#if`控制；runner仅在显式1时传-D、编译Java研究源集并启动后端。
Java的编译／产物／启动也在此门控，不是靠Swift -D自然传播或JVM运行时bool。

```sh
zsh Integrations/NFCNoRF/build.zsh
VPHONE_EXPERIMENTAL_NFC_NO_RF=1 zsh Integrations/NFCNoRF/build.zsh build
VPHONE_EXPERIMENTAL_NFC_NO_RF=1 zsh Integrations/NFCNoRF/build.zsh test
```

默认关闭只生成说明已停用的原生入口，不下载JAR、不调用Java或注册listener；清除enabled专属产物。
启用程序、wrapper classes及依赖仅位于忽略的`.build/nfc-no-rf-m0/`，无常驻服务、固定端口或guest安装项。
结束后默认关闭构建，核对无wrapper class／实验符号及残留子进程；依赖缓存保留供复现。
删除本目录及其专属可重建输出即可移除，产品没有需要撤销的组装或系统补丁。

## 验证记录

证据位于`.build/validation/nfc-no-rf-m0-20261023/`：`probe.json`为独立命令实际执行结果；
`final-tests.json`为最终所属测试输出；`dependency-provenance.json`记录真实依赖／哈希；
`final-validation.json`记录静态检查、关闭构建／符号／资源、进程收尾及源文件哈希。
只对独立研究工具构建与运行，不以此声称产品完整bundle、原生Comet或系统集成已验收。
