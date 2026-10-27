# 无RF最小原型：可复用后端、真实执行与缺口

2026-10-23；本轮只核对已有报告／定向证据和MCP读取的官方／作者源码。未安装、编译、启动服务／Java／VM、运行Apple库、修改系统／门槛或绑卡，未新增产品代码。遵循research与vphone-development技能。

**建议M0先做宿主研究协议工具＋外置jCardSim现成HelloWorldApplet的真实APDU闭环；M1才接入原生Comet入口。** 已审查项目有可构建复用的卡运行时或主机协议代码，但未找到直接实现Apple 23G90 Stockholm／Comet控制器、HCI child和SE后端的完整开源闭环。M0成功只能证明该研究工具执行了APDU，不能上报原生LoadStack或Wallet成功。

## 来源与“可复用”的准确含义

先读[既有开源后端调查](se_backend_open_source_references_20261023.md)，复用已固定提交和当前23G90契约；未发现本地完整jCardSim／vsmartcard／libcacard checkout或可直接调用的现成后端。本轮MCP复核jCardSim、vsmartcard、NXP仓库HEAD仍等于下表固定SHA。只保存小型源码／license到`.build/validation/nfc-no-rf-prototype-20261023/backend/`（0700／0600），`source-manifest.json`记录来源；没有下载归档／JAR或编译。

| 项目／本轮源码基线 | 可以复用什么 | 当前缺口／许可与运行依赖 |
| --- | --- | --- |
| jCardSim `41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56` | 上游Java Card运行时、Simulator、现成RMI接口及vsmartcard TCP端点；适合作为**外置研究工具构建候选**。 | 本体[Apache-2.0](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/README.md)，[NOTICE](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/NOTICE)含Bouncy Castle说明；需Java，构建依赖详见下节。没有Comet／NCI／IOKit前端。 |
| vsmartcard `93286a90d2411120ae17299f9902e1fdd8954185` | C `vicc_*`控制／APDU socket协议、PC/SC IFD reader；Python vpicc／Relay可作实现参考。 | 本轮核对的[vpcd.c](https://github.com/frankmorgner/vsmartcard/blob/93286a90d2411120ae17299f9902e1fdd8954185/virtualsmartcard/src/vpcd/vpcd.c)、IFD及Python文件均GPL-3.0-or-later。C reader依赖PC/SC或其lightweight替代，Python卡端不进入产品；不需要为M0引入整套reader。 |
| libcacard，维护者历史镜像 `c56862568055b0245ab2c30d6b47f2e30e11649f`（2015） | C VCard／VReader卡与reader对象、APDU分派、power、插拔；可构建的原生库候选。 | 当前[官方上游](https://gitlab.freedesktop.org/spice/libcacard)和cgit源码本轮MCP读取失败；以下仅是[维护者固定旧版](https://github.com/elmarco/libcacard/tree/c56862568055b0245ab2c30d6b47f2e30e11649f)，不称最新。源码LGPL-2.1-or-later，configure要求glib≥2.22和NSS≥3.12.8；默认CAC模型与Apple SE不相同。 |
| NXP linux_libnfc-nci `449538e5e106666e5263afeaddacc5836fc23d3f` | Apache-2.0的标准[NCI头编码／解析定义](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/hal/include/nci_defs.h)、主机credit／响应关联处理可参考，纯头定义可有选择地移植。 | [Makefile](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/Makefile.am)依赖Linux链接参数pthread/dl/rt，LLCP1.3可选OpenSSL。整栈是驱动真实芯片的host stack，不是NFCC emulator，更不能原样编入Darwin产品。 |

这里“可构建复用”指上游有实现和构建入口，**本机未编译验证**；没有任何一项是复制到VPhone.bundle即可获得Comet后端。vsmartcard／libcacard完整链接会扩张依赖；M0不选它们作为必需运行时。

## jCardSim已有的真实执行接口

[Simulator.java](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/base/Simulator.java)提供：

| 接口 | 实际行为／适配边界 |
| --- | --- |
| `loadApplet`、`createApplet`、`installApplet` | 分别加载／实例化／组合安装研究applet；不是支付安全域／Applet自动存在。构造Simulator会resetRuntime并按配置**只loadApplet**，不能将其等同已安装。 |
| `selectAppletWithResult(AID)` | 构造SELECT APDU交`runtime.transmitCommand`，返回真正响应；`selectApplet()`只折成boolean，研究trace应保留原字节。 |
| `transmitCommand(byte[])` | 持有runtime同步锁执行`runtime.transmitCommand`，返回实际APDU字节。不是预设9000的桩。 |
| `reset()` | 调用runtime.reset；与`resetRuntime()`分开。不能把reset自动解释成擦除persistent计数器或重新安装applet。 |
| `getATR()` | 返回可配置ATR；默认ATR字符串是模拟器属性，不是Apple受信任eSE身份。 |
| `changeProtocol(String)` | 选择Java Card传输protocol；不能当Apple NFCEE_MODE_SET或Comet Off/Virtual/Apdu状态的实现。 |

[JavaCardRemoteInterface](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/remote/JavaCardRemoteInterface.java)与[RemoteServer](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/remote/JavaCardRemoteServer.java)是现成Java RMI服务：创建Registry并bind `jCardSim.rmiServer`，公开load/create/select/transmit/reset/getATR/changeProtocol。Swift没有本轮可复用的Java RMI client，不能写“Swift直接调用Simulator”。

更窄的现成桥是[remote.VSmartCard](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/remote/VSmartCard.java)＋[VSmartCardTCPProtocol](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/remote/VSmartCardTCPProtocol.java)：

- **Java端主动连接**配置`com.licel.jcardsim.vsmartcard.host/port`，APDU端不是Java监听server；Swift研究工具须做本地listener，或增加另一个明确的桥。
- 双向帧为`u16be长度 || payload`。长度1是控制字；`01 POWER_ON`和`02 RESET`都执行`sim.reset()`，无独立ACK；`04 GET_ATR`有ATR回复。普通APDU进入`CardManager.dispatchApdu`，真实reply按相同长度帧返回。
- 常量有`00 POWER_OFF`，但当前IOThread switch**没有POWER_OFF case**；不能把发送00当已完成poweroff。没有请求ID／cancel／WTX／remove ACK。
- main还自动启动默认8099的ReloadThread，作为配置重载／断开入口。此线程不是Comet移除协议，也不是APDU端点；若M0原样复用须记录这个额外端口，若裁剪main则明确属于新增的外置sidecar改动。

配置安装边已核对：[jcardsim.cfg](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/jcardsim.cfg)给出`com.licel.jcardsim.card.applet.0.AID/Class`的HelloWorld例子；Simulator构造只load。[CardManager](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/base/CardManager.java)可识别其模拟器专用`80 B8` CREATE，调用`createApplet`后才有可SELECT实例。这不是GlobalPlatform或Apple安装命令。

M0不默认启动带reloader的完整main。**最小新增项为外置瘦wrapper**（目标约100行以内，尚未编写）：直接`Simulator(new SimulatorRuntime())`，`installApplet(研究AID,现成HelloWorldApplet.class)`，复用`VSmartCardTCPProtocol`连接Swift loopback listener，只保留reset／ATR／APDU循环与关闭流程；不创建ReloadThread。这样无需发模拟器专用CREATE，也无须新增socket协议或自写Java Card applet。可复用原源码不等于该wrapper已经ready。

## build／运行依赖不能被“有JDK”掩盖

[pom.xml](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/pom.xml)当前版本`3.0.5-SNAPSHOT`，Java source/target1.7；依赖Kryo5.6.2、Bouncy Castle1.71、ASM7.2及Java Card API3.0.5，JUnit为test依赖。构建插件从`JC_CLASSIC_HOME/lib/api_classic.jar`安装Oracle API，后续处理其class及shade配置；必须核对真实构建产物／依赖许可，不能按仓库本体Apache许可证概括Oracle SDK或所有依赖。

父任务只读看到本机`/Library/Java/JavaVirtualMachines/ms-17.0.15`目录。本轮未运行Java、核对CPU架构、Maven、JC_CLASSIC_HOME或本地依赖缓存；这些都是未来构建前置检查，不据目录存在宣布可编译。不得为演示把Java、Maven、Python、Homebrew库或其自动下载流程加入VPhone.bundle。

## 后端最小接口：哪些是真实执行、哪些必须新增

以下是**拟实现研究适配契约**，不是上游已提供的统一ABI；只保留一笔在途事务即可，无需通用插件平台。以`sessionGeneration + requestID`追踪适配层结果，连接重建增加generation。

| 操作 | jCardSim已有能力 | M0 adapter应承担／不能声称 |
| --- | --- | --- |
| `reset` | `sim.reset()`，TCP02无ACK | 串行执行、更新研究会话状态；由wrapper调用完成或下一次选择行为验证，不能凭写入TCP02就提前ACK成Comet reset已执行。 |
| `setMode(Off/Apdu)` | 没有对应接口 | 仅研究front-end维持mode并据此接受／拒绝APDU；Off须停止接受新请求。仅在资源／连接准备完成后报告本模型状态，不称物理SE上电成功。Virtual／BA／SWP／RF行为不在M0能力集。 |
| `transceive` | 同步applet执行和真实reply | 验证长度、记录请求对应关系、原样保留reply和SW1/SW2；transport failure独立于applet状态字，不将错误补9000。 |
| `cancel(requestID)` | 标准接口无中断／回滚方法；runtime有同步锁 | 最小版只可标记已取消并抑制旧generation交付；必要时关闭／重建外置进程。执行过的applet状态可能已改变，不能谎报回滚，也不能将下一笔APDU接在未知状态上。 |
| `remove`／EOF | 无Comet通知；socket可断开 | 终止pending、清mode/pipe关联、增加generation；保留断连原因。重连须重新reset/select，不沿用旧在途结果。 |
| `WTX` | 这两套标准远端接口没有进度／WTX事件 | M0使用能在deadline内完成的自有applet；耗时过长真实timeout。未来需新增applet/sidecar进度事件后才能映射HCP11，不能定时凭空发送WTX证明SE还活着。 |

如需要可确认的reset／poweroff／cancel结果或真实进度，应增加**一个明确外置sidecar adapter**，复用Simulator方法、串行执行和有类型结果；这属于新增代码，不能说原VSmartCard已具备。无需一开始同时实现RMI、PC/SC和第二种自定义网络协议。

## 第一笔闭环：保留真实状态，不编造SE身份

M0建议路径：`Swift宿主研究工具 → 已复核的HCP/NCI编解码模型 → APDU adapter → 外置瘦wrapper／jCardSim → 现成HelloWorldApplet → 原路reply`。整个路径先离开guest运行；不调用Apple库，不声称是在真实Comet内执行。

1. 复用上游[HelloWorldApplet](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/samples/HelloWorldApplet.java)和[SimulatorTest](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/test/java/com/licel/jcardsim/base/SimulatorTest.java)的install／SELECT方式，使用明确研究AID，不使用支付AID／身份。第一版无需新写applet。
2. 通过原applet的`INS01,P1=01` echo或`INS03`，同一会话发送两个不同、长度合法的nonce；必须返回各自payload及运行时产生的SW，而不是adapter追加9000。再发未知INS，保留applet抛出的`SW_INS_NOT_SUPPORTED`。选择、APDU执行和瞬态接收buffer均由真实Simulator管理。
3. nonce echo及错误分支证明动态执行／关联，不宣称防重放安全协议。只有以后需要检验持久状态或reset差异时，再在该模式上增加自有counter applet，并分别定义持久／瞬态语义；counter不是首轮闭环前提。
4. 只将**实际reply**包成同pipe HCP `type1,ins10` DATA，再包NCI DATA；检查credit、分片、长度和容量由模型实态驱动。普通Comet当前发送是`[80|pipe,50,APDU...]`、正常回答也是DATA；`ANY_OK`不完成，依据[23G90数据回调契约](comet_apdu_data_callback_contract_20261023.md)。
5. 短接收buffer、EOF、cancel／迟到数据、deadline应产生可区分失败；无progress源不生成WTX。M0模型回调只验证模型契约；进入真实Comet六参consumer仍属M1验收。

HCI pipe/CID、NFCEE协议标号、型号／固件／EEPROM回答、SessionID均不是jCardSim提供的Apple控制器数据。M0只在研究模型声明软件卡端点，不向guest发布能力。23G90原栈使用的`c0`是普通NFCEE协议ID；未来兼容模型按本版使用该标号本身不等于克隆硬件可信身份。不能据此宣称拥有Apple UID、支付applet、密钥或SEP配对，也不能把默认ATR或虚构GetConfig结果当成其证据。必要厂商请求尚无真实语义时停在“unsupported／未完成”，不把固定success拼成LoadStack通过；协议测试fixture只能留在测试，不能作为dev/prod后端事实。

M1另需先落地guest可访问的兼容前端，承接真实23G90初始化、NCI credit／CID、HCI admin／pipe／session、NFCEE发现和mode、移除／超时，再由实际backend状态驱动对应回答。NXP定义只能核对标准字段；Apple厂商TLV、握手、硬件身份和原生调用可达性仍由现有反汇编与后续真实入口验证约束。当前M0不完成这些层。

## 其它项目为何不能补齐剩余Comet层

vsmartcard的`vicc_poweron/off/reset/getatr/transmit`和PC/SC接口提供卡端生命周期；其[Python卡实现](https://github.com/frankmorgner/vsmartcard/blob/93286a90d2411120ae17299f9902e1fdd8954185/virtualsmartcard/src/vpicc/virtualsmartcard/VirtualSmartcard.py)通过卡OS对象的`self.os.execute(msg)`执行卡模型，Relay连实体PC/SC卡。它不会生成Apple NFCEE/HCI/Session握手；M0用jCardSim的同类TCP端点即可，增加它不减少Comet缺口。

libcacard旧版[vcard.h](https://github.com/elmarco/libcacard/blob/c56862568055b0245ab2c30d6b47f2e30e11649f/src/vcard.h)有`vcard_reset/new_applet/process_applet_apdu`；[vreader.h](https://github.com/elmarco/libcacard/blob/c56862568055b0245ab2c30d6b47f2e30e11649f/src/vreader.h)有power/xfr_bytes/insert_card/card_is_present。它能作为将来的原生卡模型框架，但新applet、异步cancel／WTX和Comet封装仍需实现，GLib/NSS依赖也不会因无RF而消失；因此当前不选它替代已存在的jCardSim测试模式。

NXP[nfc_ncif.c](https://github.com/NXPNFCLinux/linux_libnfc-nci/blob/449538e5e106666e5263afeaddacc5836fc23d3f/src/libnfc-nci/nfc/nfc/nfc_ncif.c)明确从**host角度**发送命令、接收／关联RSP/NTF与处理credits；把这个client栈放到后端并不会自动变成NFCC固件。AOSP NXP eSE T=1 WTX／SPI transport与Apple HCI11是不同封装，继承[前轮固定源码核对](se_backend_open_source_references_20261023.md)的边界。未找到这些项目现成的23G90 Comet完整初始化＋真实APDU Demo，结论限定本次核对范围。

## 宏、产物与验收范围

未来若实现，Swift研究入口、协议adapter及组装点都须受一个具名实验编译条件控制，关闭后不编入／注册该后端；具体名字由实现时沿用项目规范。Java瘦wrapper使用独立、显式的研究构建profile／源集及产物目录，默认不进入编译／打包；不能只用JVM运行时boolean。Swift的`-D`不会自动作用于Java，必须分别验证未启用时不构建／复制／启动它。正式bundle不携带或自动安装这些依赖。

当前交付仅为有源码支撑的选择与接口缺口：M0需新增Swift研究adapter与外置瘦wrapper，标准TCP收发和HelloWorldApplet直接复用上游；复杂生命周期进度接口按后续真实需要补。未来验收应分别记录“上游构建”“动态applet执行”“宿主协议模型”“原生Comet回调”“系统／Wallet能力”，不能跨层替代。本轮没有任何一项运行成功证据。
