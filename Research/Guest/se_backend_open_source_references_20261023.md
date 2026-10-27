# NFProductIsVM 之后：开源 SE 后端与透传参考

2026-10-23，北京时间。范围仅为公开源码／官方资料及已有取证记录；没有启动 VM、改系统、装 App、绑卡或实现补丁。承接 [运行时 VM gate 验证](nfcd_vm_guard_runtime_probe_20261023.md) 和 [Apple Pay 可行性调查](apple_pay_secure_element_feasibility_20261023.md)。

## 结论

**有可复用的“普通智能卡模拟／APDU 转发”和“NXP 真实控制器／eSE 驱动”代码；没有找到可直接接入 vphone、兼容 AppleStockholm 并让 Wallet 完成真实银行卡 provision 的公开实现或可复现 Demo。** 检索范围内未找到，不等于证明不存在未公开方案。

绕过 `NFProductIsVM()` 仅让 nfcd 进入原来的驱动初始化路径。后面至少还需要：Apple HAL 期待的 provider／控制接口、控制器启动和消息协议、SE 端点与卡 OS／applet，以及可信的 SEP–SE 授权／个性化流程。普通 USB 智能卡透传只解决其中一段。

本次先尝试 MCP `search_service_web_run`，返回 `isError=true` 且无内容；随后用 web fallback 搜索并读取作者／官方文档，以官方 Git 仓库的原始文件核对接口。GitHub REST API 返回 403，但 `git ls-remote` 与固定 SHA 的 raw 文件可读。下列 SHA 是本次实际查询得到的 HEAD，不能解释成这些项目支持本文中的 Apple 接口。

| 项目 | 本次查询到的 SHA |
| --- | --- |
| QEMU | `4f4225874d4d3747ec1142e935dbd314218992fa` |
| vsmartcard | `93286a90d2411120ae17299f9902e1fdd8954185` |
| jCardSim | `41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56` |
| AOSP hardware/nxp/nfc main | `de9117d37cc04014f53deadaf8487dfb1df728fc` |
| AOSP hardware/nxp/secure_element main | `653d11263ae986b972274aed09254dd6dc221d8a` |
| NXP nxp-pn5xx | `5cabbc58ff17f6023b4d0d217cdfb31b63f737c4` |
| NXP linux_libnfc-nci | `449538e5e106666e5263afeaddacc5836fc23d3f` |
| OpenCore Legacy Patcher | `8da38565fa1551a8e5ce8613ea835d04dd97e089` |

## 可参考的接口与实际边界

### 1. QEMU：虚拟 USB CCID + 远端智能卡

[官方 CCID 文档](https://www.qemu.org/docs/master/system/devices/ccid.html) 给出两条完整配置路径：`ccid-card-emulated` 使用 libcacard；`ccid-card-passthru,chardev=...` 配合客户端 vscclient，通过 chardev 转发读卡器／卡事件和 APDU。libcacard 的软件卡模型是 CAC，不是 Apple Pay SE。

已核对固定版本 [hw/usb/ccid-card-passthru.c](https://github.com/qemu/qemu/blob/4f4225874d4d3747ec1142e935dbd314218992fa/hw/usb/ccid-card-passthru.c)：

- `ccid_card_vscard_send_apdu()`（93 行）发送 `VSC_APDU`。
- 接收路径分别处理 `VSC_ATR`、`VSC_APDU`、`VSC_CardRemove`（214、234、238 行），再通知 guest 的 CCID 层。
- `passthru_realize()`（354 行）建立 chardev；没有后端则报 `missing chardev`。

**可借鉴**：区分前端设备模型与后端卡、连接／断开、ATR、APDU 请求／响应和错误的协议设计。**不能直接接入**：这里的 guest 前端是 USB CCID，线上协议是 VSCard；当前 vphone 是 Apple Virtualization.framework guest，nfcd 的前端不是 PC/SC 或 USB CCID。QEMU 设备源码不能直接装进该宿主成为 Stockholm 设备。上述官方示例只证明智能卡虚拟化链路有可运行设计，不证明 Apple Pay 或 AppleStockholm 兼容。

### 2. vsmartcard：PC/SC 虚拟读卡器、软件卡及实体卡 relay

[作者文档](https://frankmorgner.github.io/vsmartcard/virtualsmartcard/README.html) 说明 vpcd 向 PC/SC 提供虚拟读卡器，vpicc 提供软件卡；支持通用 ISO 7816、eID／ePassport 等卡模型。不是通用支付 SE 模型。

固定版本源码已核对：

- [src/ifd-vpcd/ifd-vpcd.c](https://github.com/frankmorgner/vsmartcard/blob/93286a90d2411120ae17299f9902e1fdd8954185/virtualsmartcard/src/ifd-vpcd/ifd-vpcd.c)：`IFDHTransmitToICC()`（426 行）调用 `vicc_transmit()`（444 行），并单独处理 power、ATR。
- [src/vpcd/vpcd.c](https://github.com/frankmorgner/vsmartcard/blob/93286a90d2411120ae17299f9902e1fdd8954185/virtualsmartcard/src/vpcd/vpcd.c)：`vicc_getatr()`、`vicc_poweron()`、`vicc_poweroff()`、`vicc_reset()`（427–456 行）定义卡生命周期消息。
- [VirtualSmartcard.py](https://github.com/frankmorgner/vsmartcard/blob/93286a90d2411120ae17299f9902e1fdd8954185/virtualsmartcard/src/vpicc/virtualsmartcard/VirtualSmartcard.py)：socket 长度前缀消息；控制消息分别驱动 power/reset/ATR，普通消息调用 `os.execute()`。`card_type == "relay"` 选择 RelayOS。
- [cards/Relay.py](https://github.com/frankmorgner/vsmartcard/blob/93286a90d2411120ae17299f9902e1fdd8954185/virtualsmartcard/src/vpicc/virtualsmartcard/cards/Relay.py)：`RelayOS.execute()` 通过实体读卡器的 `session.sendCommandAPDU()` 收发并拼回 SW1/SW2。

**可借鉴**：无 RF 的普通 ISO 7816 卡端点、APDU 与实体卡转发分层、reset／断连语义。**缺口**：它不提供 Apple HAL 前端、NFC 控制器固件行为、SE–SEP 配对或 Apple 支付 applet。实体 iPhone SE 也不是这个项目直接可枚举的 PC/SC 卡。其 Python 卡实现只能作为外部研究参考，不能进入本仓库产品运行时。

### 3. jCardSim：Java Card applet 的软件运行环境

固定版本 [base/Simulator.java](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/main/java/com/licel/jcardsim/base/Simulator.java) 提供 `loadApplet()`、`installApplet()`、`selectAppletWithResult()`、`transmitCommand()`、`reset()`、`getATR()`；APDU 实际交给 `runtime.transmitCommand()`。

[SimulatorTest.java](https://github.com/licel/jcardsim/blob/41511ec2a3d3dfa7a5fe2d07f5b4e56bc9c8dd56/src/test/java/com/licel/jcardsim/base/SimulatorTest.java) 包含安装／选择 HelloWorldApplet、发送命令并校验 `9000` 的测试，是已有可参考的最小闭环；本轮未构建或运行它。

**可借鉴**：在宿主独立验证自己拥有源码的研究 applet 和 APDU 处理。**不能推出**：Java Card 方法可调用，不代表具有 Apple Pay 管理 applet、发行方 applet、安全域管理密钥或设备可信身份；可配置的 ATR 字符串也不等于受信任的 SE。

### 4. NXP / AOSP：真实 NFC 控制器与 eSE 的 HAL

这类代码比 PC/SC 更接近底层 NFC／SE 通路，但仍是另一套平台接口。

**NFC 控制器层**：[AOSP snxxx/halimpl/hal/phNxpNciHal.cc](https://android.googlesource.com/platform/hardware/nxp/nfc/+/de9117d37cc04014f53deadaf8487dfb1df728fc/snxxx/halimpl/hal/phNxpNciHal.cc) 的 `phNxpNciHal_open()`／`phNxpNciHal_write()`（974／1146 行）通过 TML 层访问设备；默认设备节点 `/dev/nxp-nci`，初始化调用 `phTmlNfc_Init()`。源码包含 NCI CORE_RESET／CORE_INIT 失败、重试及恢复处理。是驱动真实芯片的 HAL，不是控制器 emulator。

**独立 eSE 层**：[AOSP snxxx/aidl/SecureElement.cpp](https://android.googlesource.com/platform/hardware/nxp/secure_element/+/653d11263ae986b972274aed09254dd6dc221d8a/snxxx/aidl/SecureElement.cpp) 提供 `getAtr()`（185）、`transmit()`（257）、`openLogicalChannel()`（334）、`reset()`（885）；调用 `phNxpEse_open/init/getAtr/Transceive/reset`，选择 `ESE_PROTOCOL_MEDIA_SPI_APDU_GATE`。这是 Android AIDL 服务到 eSE 库的适配，不是 Apple `NFDriver*` ABI。

**传输与帧层**：

- [EseTransport.h](https://android.googlesource.com/platform/hardware/nxp/secure_element/+/653d11263ae986b972274aed09254dd6dc221d8a/snxxx/libese-teq1/nxp-ese/pal/EseTransport.h) 定义 `OpenAndConfigure/Read/Write/Ioctl/Close`，包含 power、access、cold reset、trusted access 等 ioctl。
- [EseSpiTransport.cpp](https://android.googlesource.com/platform/hardware/nxp/secure_element/+/653d11263ae986b972274aed09254dd6dc221d8a/snxxx/libese-teq1/nxp-ese/pal/spi/EseSpiTransport.cpp) 的打开路径实际 `open(..., O_RDWR)`，Read/Write/Ioctl 访问真实设备。它没有凭空生成 SE 卡响应。
- [phNxpEseProto7816_3.cpp](https://android.googlesource.com/platform/hardware/nxp/secure_element/+/653d11263ae986b972274aed09254dd6dc221d8a/snxxx/libese-teq1/nxp-ese/lib/phNxpEseProto7816_3.cpp) 有帧级 LRC、S-frame、WTX 等处理，可参考传输状态机；不能未经对照假设 Apple SE 使用完全相同变体。
- [VirtualISO.cpp](https://android.googlesource.com/platform/hardware/nxp/secure_element/+/653d11263ae986b972274aed09254dd6dc221d8a/snxxx/aidl/VirtualISO.cpp) 虽名为 VirtualISO，仍通过 `phNxpEse_open()` 和 endpoint context 1 调用真实 eSE 库；不能把文件名当作软件虚拟 SE 的证据。

**Linux 驱动对照**：[NXP pn5xx_i2c.c](https://github.com/NXPNFCLinux/nxp-pn5xx/blob/5cabbc58ff17f6023b4d0d217cdfb31b63f737c4/pn5xx_i2c.c) 注册 Linux misc 字符设备，使用 I²C、GPIO IRQ、VEN／firmware 控制及 regulator，并从 DT 读取相应资源。[NXP 官方 AN11697](https://www.nxp.com/docs/en/application-note/AN11697.pdf) 说明 Linux NFC stack 的 service/core/HAL 分层；[官方 linux_libnfc-nci](https://github.com/NXPNFCLinux/linux_libnfc-nci/tree/449538e5e106666e5263afeaddacc5836fc23d3f) 是 PN71xx NCI stack。

**可借鉴**：真实控制器的总线／电源／中断、控制器初始化与 SE APDU 是不同层；普通 APDU relay 不能代替所有这些职责。**不能照搬**：Linux I²C misc driver、Android AIDL/HIDL 以及其 ioctl，不等于 Darwin IOKit／kernel control／AppleStockholm 接口；移植这些文件本身不会让 Apple HAL 匹配到 provider，也不会模拟控制器固件。

### 5. OCLP / T1：最接近 Apple 原栈的恢复案例

[Dortania issue #1103](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1103) 是维护者的一手分析：T1 在目标 Mac 内部经 USB 2.0 连接，由 KernelRelayHost 接到 IOKit；Apple Pay 的查询链包括 NearField、libnfshared、nfcd、libPN548_API 和 AppleSSE。维护者在 2023-10-15 将问题标为 v1.1.0 已解决。

本次固定 SHA 读取了 [t1_security.py](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/8da38565fa1551a8e5ce8613ea835d04dd97e089/opencore_legacy_patcher/sys_patch/patchsets/hardware/misc/t1_security.py)：`present()` 以真实 `t1_chip` 为条件；patch set 明列 Apple Pay 所需的 `libNFC_Comet`、`libNFC_HAL`、`libnfshared`、`libnfstorage`、`libnfrestore`、`libPN548_API`，以及 `nfcd`、`nfrestore_service`、多种控制器固件；较新系统还合入相应 NearField 组件。**这是复用原配真实 T1 硬件、恢复配套软件栈的代码证据，最适合参考依赖清单与逐层排障；不是虚拟支付 SE 的实现。**

不能据此把 Mac T1 的 KernelRelayHost／AppleSSE 分支当作 iPhone Stockholm 分支的通用 USB 透传接口；也未见此补丁将物理 T1 或配对关系转移给一个虚拟 iPhone。此轮只读了配置源码和维护者 issue，没有运行 patcher 或获取驱动／固件二进制。

## 为什么“可透传 APDU”仍不足以绑卡

Apple 官方说明 NFC controller 还负责 AP 与 SE 之间的通信；去掉 RF 使用场景不自动去掉内部控制器／传输职责。[组件说明](https://support.apple.com/guide/security/apple-pay-component-security-sec2561eb018/web)

Apple 当前授权文档说明 SEP 与 SE 在工厂持有对方长期公钥，私钥由硬件保存，运行时通过 ECDH 生成共享秘密；交易授权还绑定认证方式、contactless／e-commerce 类型及 AR。**判断**：将普通卡、宿主 SE 或另一个设备的 SE 接到 APDU 通道，不会自动建立当前虚拟 SEP 的可信授权关系。[Payment authorization](https://support.apple.com/guide/security/payment-authorization-with-apple-pay-secc1f57e189/web)

同文档说明支付 applet 的个性化密钥参与 cryptogram 运算，App／网页交易包含 Apple Pay 服务器 anti-replay 值。**判断**：软件卡返回某个 SELECT 成功或 `9000`，不能替代个性化与发行方／网络验证。此处没有提出获取、导出或伪造任何支付密钥的方案。

## 下一步只读验证应解决什么

1. **先确定 Apple 边界，再选参考库**：继续对当前 23G90 的 `libPN548_API`／`libNFC_HAL` 做离线符号、导入、调用图核对，列出 Open、LoadStack、GetSecureElementInfo、Transceive 分别期待的 provider／control 接口。26.1 反编译只作导航，不冒充当前版本实现。
2. **把接口分成完整生命周期**：设备匹配、power/reset、固件／NCI 初始化、SE 枚举与 APDU、错误与断连；逐一标注能从已知二进制和源码确认的项，未知不填入猜测常量。没有必要先开发通用 relay 平台。
3. **判断最小实验范围**：未来若单独授权宿主实验，可先运行 jCardSim 的已有 HelloWorld 测试，或 QEMU 官方 CCID Demo，验证普通 APDU 后端职责；这些实验与现用 vphone 分离，不触及支付卡，也不能作为 Wallet 成功验收。本轮没有执行。
4. **明确停止条件**：只有普通 APDU 后端而没有 Apple 前端适配／真实可信 SE 的证据，就应保持“协议研究可继续，真实绑卡无可运行依据”。不要以伪造能力返回值或静态卡信息冒充后端完成。

检索覆盖 QEMU／libcacard、vsmartcard、jCardSim、NXP 官方 Linux NFC、AOSP NFC／eSE HAL 和 Dortania OCLP T1 patch set，并以 Apple 官方安全资料核对支付边界；补查 AppleStockholm／libNFC_HAL／Apple Pay VM 相关公开关键词。没有把搜索结果中的第三方宣传文章当作能力证据，也没有对所有 GitHub 分支／闭源商业产品作穷尽审计。此前记录的 QEMUAppleSilicon／qemu-sptm 线索仍须按各自硬件前提理解，不能合并为一个已经打通的 VM 支付方案。
