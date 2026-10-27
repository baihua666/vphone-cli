# M0 宿主无RF研究原型

独立Swift协议模型＋外置真实jCardSim，未接入guest、Comet、HAL、nfcd、Wallet或产品bundle。
这是一条可运行的普通测试APDU链；不实现Apple SE身份、支付应用、密钥、NFCC完整初始化或RF。

## 构建与运行

要求macOS、Xcode命令行工具和本机JDK17。复用仓库已有独立`swiftc`测试runner模式；本阶段无需修改
手写Xcode工程或产品target，也不引入SwiftPM app target。源码／测试／Java桥各自位于所属独立目录。

```sh
# 默认关闭：仅编译不含实验主体的诊断入口，不下载依赖，不运行Java或监听端口。
zsh Integrations/NFCNoRF/build.zsh

# 显式启用，运行真实 SELECT／双nonce echo／未知INS，stdout为JSON。
VPHONE_EXPERIMENTAL_NFC_NO_RF=1 zsh Integrations/NFCNoRF/build.zsh build

# 同一真实后端，加credit／分片／超时／断连恢复检查。
VPHONE_EXPERIMENTAL_NFC_NO_RF=1 zsh Integrations/NFCNoRF/build.zsh test
```

可用`NFC_JAVA_HOME=/绝对路径/JDK17/Contents/Home`选择JDK17。runner只下载一个固定JAR至忽略的
`.build/nfc-no-rf-m0/dependencies/`并验证SHA-256；直接javac编译瘦wrapper，无Maven／SDK安装。
开启后的可重建程序／class在`.build/nfc-no-rf-m0/enabled/`。默认关闭构建会移除该enabled目录，
不删除依赖缓存；不要与开启构建／运行并发。关闭构建不启动网络或guest操作。

研究工具自行绑定`127.0.0.1:0`临时端口，再启动一个Java client。上游TCPProtocol的connect自带3秒等待；
每次新后端先串行RESET→GET_ATR作为活性屏障，然后由实际SELECT确认applet。ATR是jCardSim默认配置，
不代表Apple身份。wrapper显式安装自有研究AID `F05650484F4E4501`的上游HelloWorldApplet，不启动reloader。

## 固定依赖及与前轮方案的差异

采用`com.klinec:jcardsim:3.0.5.11`（Maven Central发布的ph4r05分支），**不是**前轮仅离线分析的Licel
HEAD `41511ec...`。作者[README](https://github.com/ph4r05/jcardsim/blob/master/README.md)说明该fork及
Maven坐标；固定发布的[POM](https://repo.maven.apache.org/maven2/com/klinec/jcardsim/3.0.5.11/jcardsim-3.0.5.11.pom)
记录SCM、Apache-2.0及其依赖。选3.0.5系列是为复用本轮已核对的TCPProtocol／Simulator／HelloWorldApplet API，
不声称它是最新发布。其API类已包含在发布JAR中，本地仅编译桥，不宣称编译了Licel最新源码。

- 二进制SHA-256：`f6c3b6b8140401a47cf39d7b9dbfc052e381474c6c3b22018051024be1fca97c`。
- 对应sources.jar SHA-256：`a6a0332427b4232d853a5c402cb056d82ebfdb88e765198977c803d950a19240`。
- 源码核对对象为该sources.jar的`Simulator`、`SimulatorRuntime`、`VSmartCardTCPProtocol`、`HelloWorldApplet`；
  不将其它版本源码当本次执行产物。仅验证非加密测试applet路径，不声称全部crypto依赖／算法已验收。

未把JAR、JDK、Maven或Java Card SDK复制到产品；没有更改版本号、签名、helper或VM绑定。

## 协议与运行边界

- 所有Swift实验实现与测试受`#if VPHONE_EXPERIMENTAL_NFC_NO_RF`隔离。唯一默认值位于
  `Configuration/experiment.zsh`；默认0／未定义，只有显式1会给Swift传-D并将Java研究源集交javac。
  Java没有语言预处理器，所以实际编译／产物／启动门控由runner独立执行，不能只靠Swift -D。
- `VPhoneNFCSession`是单线程、单笔在途的契约驱动器／控制器子集；它的completion是模型接口，不是Apple ABI。
  调用者明确open连接、设置Off／Apdu并begin／pump／grant。NFCEE ID、动态CID和pipe不混用。
- 正常APDU往返均同pipe DATA `type1/ins10`，HCP首片payload253／续片254，再按MPS分NCI PBF；无Stockholm
  物理封装／CRC。控制器FW／EEPROM／routing／HCI child及原生LoadStack均未实现，不能用此模型替代初始化成功。
- credit每接受一片扣1，0暂停，`ff→fe`；仅支持匹配CID的单pair通知，0增量不推进，溢出／多pair拒绝。
  探针显式发容量grant，不表示SE完成，也不证明已动态验证原Comet parser。
- 长度帧为上游`u16be || payload`，流读写有界且处理partial I/O／EINTR。最多4096B是模型／运输上限；
  真实HelloWorld短APDU仅测试255B nonce，不能据此声称4096B applet支持。
- 无请求ID的后端流严格串行；超时／取消／错误／移除关闭流、终止本工具拥有的Java进程、增加generation、清模式／连接。
  重开创建新Simulator，再reset／SELECT，不重放旧请求。重建会丢失该模拟器会话，不能声称applet持久状态／事务回滚。
- 标准TCP端点无WTX/progress、POWER_OFF ACK、可中断执行；本版不伪造这些能力。Off只是模型接受状态，
  真正释放资源使用close。RESET的ATR屏障不是Apple硬件复位证明。

## 验收与停用

`build`路径逐字验证真实SELECT `9000`、两个不同nonce各自`nonce||9000`、未知INS `6d00`，均取自Simulator；
Swift／wrapper不追加SW。`test`还验证：

1. HCP阈值、MPS、流拆粘包、非法CID／pipe／type与ANY_OK拒绝；零credit、单pair恢复及有限ff额度。
2. 真实248／249／255B nonce echo，经17B MPS双向分片，覆盖253／254B C-APDU边界及257B R-APDU。
3. 接收容量不足、busy、Off拒绝、重复pump不重复完成。
4. SIGSTOP本工具拥有的真实Java进程，0.15秒deadline超时并销毁旧流；新进程重新SELECT成功。
5. SIGKILL本工具拥有的后端产生EOF，再新建／SELECT／真实echo；向模型注入旧generation帧不能完成新请求。
6. cancel一次收尾及零credit等待超时。故障信号仅在Tests中，正常probe无故障注入。

启动前确认没有此前同任务残留的研究进程；不要杀其它Java／用户VM。每个backend在start前stop自己持有的旧子进程，
主程序及测试在结束／抛错时关闭socket、终止／回收其子进程；wrapper在父进程断开流后退出。
需要中断前台runner时，确认进程退出；本工具没有常驻服务、固定端口或guest清理项。

停用运行默认关闭构建；移除功能只需删除本目录和`.build/nfc-no-rf-m0/`专属可重建产物。
产品没有组装钩子／资源／依赖，不需修改通用代码或系统。真实运行记录见
[M0验收报告](../../Research/Guest/nfc_no_rf_m0_implementation_20261023.md)。
