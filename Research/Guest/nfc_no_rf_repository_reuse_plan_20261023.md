# 无 RF NFC 原型：当前仓库复用点与最小接入方案

2026-10-23；只读当前工作树源码、CodeGraph关系和Apple官方文档。不运行VM／server／build，不执行guest API，不改产品／系统／manifest／helper。以下将**已实现事实**与**拟议方案**分开；没有新增服务、协议、target、宏或部署产物。

## 结论

**可以复用已有 VSOCK 设备与host主动连接guest listener的模式，另设独立研究通道；不能把现有guest HTTP/RPC说成已经具备NFCC／SE接入能力。** 最少改动候选是host取到当前VM的socket device后接一个隔离适配器，guest worker启动一个同样隔离的native listener；协议、NFCC模型与生命周期放在研究模块，不增加GuestAPI方法或业务manifest字段。

当前未找到host VSOCK accept/listener实现，也未找到名为`GuestServer`的当前tracked类型；guest主server实际内联在`Daemon/main.swift`的NIO ServerBootstrap。Apple文档提供另一方向的listener API，但它在本仓库仍需新增适配。

新证据 `.build/validation/nfc-no-rf-prototype-20261023/repository/` 保存HEAD／branch、定向源文件SHA-256与官方链接；这是当前工作树调查，不将本地代码冒称已核对上游基线或现用5-20261023已部署能力。

## 已有host调用链

| 复用点 | 当前实现与限制 |
| --- | --- |
| [VM配置](../../VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachine.swift) `VPhoneVirtualMachine` | 第261行配置一个`VZVirtioSocketDeviceConfiguration`；它是通用host↔guest字节设备，不是Stockholm／NFC虚拟硬件 |
| [VM入口](../../VPhoneExecutable/VPhoneVirtualization/VirtualMachineProcess/main.swift) | unentitled CLI启动专有entitlement的`vphone-vm`，后者调用`VPhoneGuestApp.run`；不应把VZ访问搬入Launchpad/helper或外部普通工具 |
| [装配入口](../../VPhoneExecutable/VPhoneVirtualization/UI/VPhoneVirtualMachineAppDelegate.swift) `startVirtualMachine()` | 启动VM后，`!command.dfu`分支在第132行取得`socketDevices.first as? VZVirtioSocketDevice`，给control／camera及可选API proxy。此处在noGraphics窗口分支之前，适合作为VM实例级窄装配点 |
| [直接HTTP客户端](../../VPhoneExecutable/VPhoneVirtualization/UI/GuestCommunication/VPhoneGuestControl.swift) `http()` | 第718行`device.connect(toPort:1339)`，保留`VZVirtioSocketConnection`交给同步HTTP transaction；它只封装HTTP，不能直接当通用NFCC二进制client |
| [相机独立通道](../../VPhoneExecutable/VPhoneVirtualization/UI/HostDevices/VPhoneCameraServer.swift) `connect/attemptConnect/disconnect` | 第198行连接1338，持有VZ connection和FD、连接代次token、断线重连；提供已落地的独立端口模式。其BGRA协议、单向生产、测试画面和发布策略不应复制到NFC协议 |
| [透明relay](../../VPhoneExecutable/VPhoneVirtualization/UI/GuestCommunication/VPhoneAPIProxy.swift) `GuestSocketProvider.attach / ByteRelay` | 第248行连固定guestPort1339；dup FD后交NIO，同时保留VZ connection，处理背压、最后一写完成后关闭。两类均private且绑HTTP admission，尚不是公共任意端口transport API |
| 停止／重启 | AppDelegate的`stopControlServices()`用于终止与重启；camera另在硬件键盘重启中disconnect。新适配器必须在自己的stop路径关FD、取消重试、放弃旧device，不能只在start处注册 |

仅复用`VZVirtioSocketDevice`、FD生命周期与NIO socket接入机制；不需要新增第二个虚拟网卡、TCP/IP网络、manifest网络模式或特权helper动词。

[Apple VZVirtioSocketDevice](https://developer.apple.com/documentation/virtualization/vzvirtiosocketdevice)明确区分host的`connect(toPort:)`与`setSocketListener(_:forPort:)`；connection由VZ创建，不能自行构造。[VZVirtioSocketListenerDelegate](https://developer.apple.com/documentation/virtualization/vzvirtiosocketlistenerdelegate)用于guest主动连接时的host接受／拒绝。[connection文档](https://developer.apple.com/documentation/virtualization/vzvirtiosocketconnection)提供FD与close。MCP检索工具本次返回空错误，已回退检索Apple官方页面；本地调用链以源码为准。

## 已有guest调用链与可复用边界

| 文件／符号 | 当前事实 |
| --- | --- |
| [main.swift](../../VPhoneDaemon/Daemon/main.swift) | `vp_native_process_mode()`区分launchd proxy／`--io` worker；proxy启动／监控worker；worker经`vp_native_watch_proxy`确认后才启动服务 |
| [native proxy](../../VPhoneDaemon/Native/vphoned_proxy.c) | `vp_native_run_proxy`用pipe监控worker；proxy死亡后worker的watch线程退出整个进程，避免残留VSOCK持有者。它不是任意研究程序启动器，不应加通用exec动词 |
| [相机native服务](../../VPhoneDaemon/Native/vphoned_vcam.m) | `vp_vcam_start`→pthread_once→listener_thread；第336行`socket(AF_VSOCK,SOCK_STREAM,0)`，bind CID_ANY/1338，listen/accept后`handle_client`。`read_full`示范短读/EINTR处理；BGRA共享内存、detached thread与无限重连不是可直接复用的通用服务生命周期 |
| [VphonedNative.h](../../VPhoneDaemon/Native/Include/VphonedNative.h) | 导出native函数给Swift；现有`vp_vcam_start`由worker main第22行调用。新增研究服务可经一个受宏控制的同类装配钩子接入，协议本身不进入此通用header |
| guest主server | main第97行NIO `.bind(to:VsockAddress(cid:.any,port:1339))`，HTTP与WebSocket upgrade；具体handler为GuestHyperTextHandler／GuestWebSocketHandler／GuestPortForwardHandler，没有可复用的`GuestServer`实例 |
| [APIWire](../../VPhoneDaemon/Daemon/APIWire.swift) | 通用RPC是`{method,params,id}` JSON，派发`GuestAPI.execute`并广播event；不是NCI／HCP／SE时序总线。不要新增`nfc.*`／`se.*`到这里承担研究字节协议 |
| [现有端口转发](../../VPhoneDaemon/Daemon/GuestPortForwardHandler.swift) | `/v1/ports/<port>`只转guest loopback TCP、使用WebSocket binary帧；可供既有网络工具，不等于kernel-control socket、IOUserClient或独立NFCC通道，不建议把本原型再叠成HTTP→WS→TCP→NCI |

相机header明确记录cameracaptured sandbox不能直接建AF_VSOCK，现由root daemon接收后共享内存发布。这是复用root worker模式的证据；不能由此保证任意临时App或新进程有VSOCK权限。独立guest进程仍需自己的启动、签名／sandbox、停止与清理验证。

VSOCK是流，不能假定一写对应一读。APIWire的`closeAfterPeer()`还记录guest close/reset会丢弃排队数据：HTTP保留连接等peer关闭并设30秒兜底。这不是可无条件复制到新协议的规则；研究通道需明确长度边界、flush／ack、超时、EOF与取消，不把close当最后一帧已被消费。

## 方案比较：都不新增通用RPC／manifest／helper协议

| 拟议方案 | 所需最小新增 | 复用程度／代价 |
| --- | --- | --- |
| **A：host connect→guest独立listener（首选）** | 私有研究端口、host双向字节适配器、guest native研究服务；生命周期各一个窄装配点 | 复用已有camera方向和VZ/NIO模式；双向流允许guest发NFCC请求、host回数据／通知，无需host listener。协议不复用camera数据格式 |
| B：guest connect→host listener | host实现VZVirtioSocketListenerDelegate、注册／移除端口；guest新增AF_VSOCK connect | Apple有正式API，仓库尚无此方向；可让guest重连，但当前复用率较低，不能称零成本或已有accept接口 |
| C：独立guest研究helper | 新helper构建／签名／启动／权限和独立清理，加A或B通道 | 可避免改vphoned启动点，但多一个真实产品／部署生命周期，暂不作为最小首期；不能借helper扩权或任意命令接口 |
| D：已有1339 RPC／WS或camera1338塞新消息 | 改通用协议／handler或混合相机格式 | 会耦合业务时序、版本、背压与现有服务；不采用为本原型入口 |

私有研究端口**尚未选定或注册**；不得占用1338／1339，也不能采信camera注释中旧控制1337文字为当前绑定事实。后续在实际端口清单中保留单一常量，两端协商协议版本／上限；本轮不凭研究文档宣布端口可用。

## 拟议的最小隔离与装配

业务／协议状态与回放、NFCC命令／credit／Session策略应在独立研究模块维护，遵守[架构隔离](../../Documents/Guides/architecture-boundaries.md#业务定制隔离)。首期可将host薄适配置于VMKit所属`UI/Experiments/NFCNoRF/`、guest薄适配置于`Native/Experiments/NFCNoRF/`；它们仍属各自现有target，不在View或CoreKit堆业务状态。真正可复用的协议／宿主模型优先放`Integrations/NFCNoRF/`，有实际共享编解码需求再建立独立library，不预建插件平台。

拟议上游装配改动仅：

1. AppDelegate取得本次VM的socket device后，宏内创建／启动adapter；stopControlServices宏内停止、VM重启重新取得device。实例关联由该AppDelegate所有权决定，不使用全局“当前VM”或默认bundle。
2. guest worker main在watch_proxy确认后，宏内启动独立native服务；声明与实现一致受控。失败仅报告研究通道不可用，不令基础1339服务／普通VM操作全局拒绝。
3. 端点字节和异步控制事件的边界在研究协议定义。最少需协议身份／版本、有限长度、请求／回应或序号、断连后的reset语义；NFCC状态与credit不能由VSOCK fd可写直接冒充成功。
4. 关闭宏后不编译有副作用的实现、不注册端口／任务、不改guest状态；已部署的持久补丁和数据另有回退，不因关闭源码宏自动还原。

**VSOCK只补host↔guest运输。** 当前仍缺原HAL期望的kernel-control／UserClient前端、VM gate后真实NFCC／SE后端及异步生命周期；新增listener不会让AppleStockholmSPMI匹配、创建Secure Element或令Wallet可用。不得把研究模型返回固定成功当生产／开发真实硬件。

## 多target宏和构建传播：现状与缺口

建议独立宏名 **`VPHONE_EXPERIMENTAL_NFC_NO_RF`**，默认不定义；与Wallet设置隐藏补丁和未来绑卡实验分离。本轮只提出名字，没有定义或启用它。

| 编译单元 | 当前构建事实／未来必须显式做的事 |
| --- | --- |
| macOS `VPhoneVirtualMachineKit` | Xcode静态library，UI同步目录，依赖NIOCore/NIOPosix；Swift条件只控制该target中host实现／AppDelegate钩子，不能只给vphone-vm executable target传-D |
| iOS Swift `vphoned` | 独立Xcode tool target，SDK iphoneos、Swift6，导入VphonedNative；Swift装配需自身`SWIFT_ACTIVE_COMPILATION_CONDITIONS`，关闭靠移除定义，不能FLAG=0 |
| iOS C/ObjC `VphonedNative` | 独立static library target，Native同步目录；需自身`GCC_PREPROCESSOR_DEFINITIONS`或等效配置，用`#if defined(FLAG) && FLAG`；host/Swift条件不会传播到C |
| 可选guest dylib | [Makefile](../../VPhoneGuestComponents/Makefile)另起iphoneos clang，GUEST_C_FLAGS/COMMON_FLAGS与ARTIFACTS清单；若真需新guest组件，编译、资源stage、签名、安装注册必须一起受宏控制，不能只隐藏调用点 |
| 可选共享SwiftPM library | 现有[Flywheel Package](../../Integrations/Flywheel/Package.swift)是macOS15独立library例子；它不是跨iOS/host实验模块。新library须按实际两端target分别配置swiftSettings.define／平台，不能假定依赖包继承调用target宏 |

当前VMKit与Daemon的pbxproj内直接存Debug/Release设置，**没有绑定现成target xcconfig或统一实验宏**；已存在Launchpad的`Configuration/*.xcconfig`不能当它们的配置来源。未来实现时应按规范给这些owner建立／绑定窄配置文件，再集中定义宏，不伪称只改某个现成全局宏即可覆盖全仓。

[StageBundle.sh](../../VPhoneExecutable/VPhoneVirtualization/Build/StageBundle.sh)第20行`build_project`通过`env -i`调用嵌套xcodebuild；第35行独立构建iOS daemon，第45行另起make。它不显式转传host Swift/C宏，因此host build命令上的-D或shell环境不保证guest实验一致启用。须核对两端实际编译命令／符号及打包内容；默认关闭时新资源也不能无条件进入guest-resources。

现有完整bundle在StageBundle中分别签vphoned与vphone-vm；新增helper／dylib还需本身的合法签名与打包验证。不得引入Python、运行时Homebrew或外部本地源码路径依赖；不能改官方基线版本或伪造local内容哈希。

## 后续最小验证与本轮未执行项

实现前先固定当前profile和前端／宿主分工；第一阶段仅验证独立通道hello、有限长度双向流、断连、重连、取消和两实例隔离，再接真实NCI／credit／pipe状态机。传输成功与原版LoadStack／APDU成功分别验收，不扩大为绑卡结论。

未来至少覆盖宏开／关、host有而guest无／反向缺能力、旧pinned bundle、端口冲突、VM重启换device、服务错误不影响1339／相机、最后写与EOF、资源移除。涉及实际产品改动时运行所属target测试和完整bundle检查；本轮只核对源码／构建文件／官方API，未运行任何测试服务器、VM、build或新实验代码。
