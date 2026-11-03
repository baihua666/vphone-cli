# vphone 钱包绑卡：Secure Element 模拟与透传可行性

调查日期：2026-10-23（北京时间）。目标：不需要 NFC 碰一碰支付，但希望虚拟 iPhone 自身能在 Wallet 绑定真实银行卡，并用于 App／网页 Apple Pay。

后续实测：[VM gate 与实际 nfcd 身份](nfcd_vm_guard_runtime_probe_20261023.md) 确认指定实例 `NFProductIsVM() = 1`，客体 nfcd 与同版原始文件同完整摘要／UUID；结合既有 unsupported 状态，强力支持显式 VM 门槛解释。该补充不改变本文对支付 SE 后端缺口的判断。

后续源码分析：[绕过 VM gate 后的驱动／SE 依赖](nfcd_after_vm_gate_dependencies_20261023.md) 与 [固定版本开源参考](se_backend_open_source_references_20261023.md)。分别核对原生 provider／transport、NFCC 初始化、eSE wired mode、支付身份与 SEP 配对，未实施绕过或部署任何后端。

## 结论

当前项目没有支付 Secure Element（SE）实现，也没有找到可直接复用、已证明虚拟 iPhone 能真实绑卡和付款的开源 SE 模拟／透传方案。这个结论限定于本次公开资料及源码检索，不是证明所有未公开方案都不可能。

Java Card、APDU 和智能卡网络转发有开源实现；缺口在 Apple Pay 管理／支付 applet、受信任的个性化与发卡流程，以及 SE 与 Secure Enclave（SEP）的配对授权。纯软件模拟不能仅靠实现指令集取得这些能力。裸 SE 透传也不能只解决传输而忽略配对。

真实设备代为完成完整 Apple Pay 授权，比裸 SE 透传更有落地依据。官方已有跨设备网页付款，但这不等于 VM 自身绑卡，也不是任意第三方 iOS App 的透明替代。

## 调查范围与证据等级

- 只读源码、项目研究记录及公开一手资料；没有启动、停止或修改 VM，没有输入卡号、绑卡或发起付款。
- 本地 HEAD：`b4f124bbd496089ba791cc18732bf9eed526d2a7`；工作区已有大量其它改动，相关 VM 文件也有未提交修改，本轮不触碰。
- 本地 `upstream/main` 指向 `dfcfae9c608c432a9a63f846d5cda8272fde0b82`，它不代表远程最新 SHA。本次读取了官方 GitHub `main` 的相关源文件，但 GitHub API 返回 403，未取得最新分支 SHA；在线链接为可变化分支，不能冒充固定版本审计。
- 按要求先尝试 MCP `search_service_web_run`，返回 `isError=true` 且无内容；随后通过 web 工具检索、抓取 Apple 与项目作者官方内容。代码定位先调用了根 CodeGraph，再定向检索。
- “已确认”指来源直接说明或源码可见；“判断”指基于这些事实的工程推论；“未找到”不等于不存在。

## 本项目现状

1. [VM 配置源码](../../VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachine.swift) 约 294–303 行仅建立 `_VZSEPCoprocessorConfiguration(storageURL:)`，载入 SEP ROM 并通过 `_setCoprocessors([sepObj])` 加入 VM。[官方 main 同一文件](https://github.com/Lakr233/vphone-cli/blob/main/VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachine.swift) 也可见该配置；未见支付 SE 的组装。
2. 定向检查 Virtualization、Daemon、GuestComponents、Kit 和 Command 中的 `secure element / ApplePay / PassKit / nfcd / Stockholm` 等词，未找到支付 SE provider 或宿主 SE 转发。固件设置行代码只是隐藏 Wallet 入口；vendored restore C 的 `PAIR_STOCKHOLM`／`UPDATE_STOCKHOLM` 是恢复阶段消息常量，不是已实现的 SE 模拟器或可用透传通道。
3. [既有客体设备树研究](signin_and_vm_feature_hiding.md) 记录有 SEP、缺少 NFC/Stockholm；[特定旧实例记录](post_setup_signin_and_appstore.md) 还移除了 Wallet 主程序。这些是历史实例证据，不代表所有当前镜像状态。本轮没有读取运行中实例验证。
4. `SEPStorage` 属于虚拟 SEP 的持久状态；其存在不能证明有 Apple Pay SE、支付 applet、SEID 或可用支付凭证。

## 为什么不需要 NFC 仍有硬性缺口

### SE 与 SEP 是两个角色

Apple 将 SE 描述为运行 Java Card 的认证芯片，SEP 负责用户认证和交易授权。认证评估证明芯片／平台安全属性，不能把 EMVCo 的平台证书直接等同于每台设备的 Apple 绑卡身份。[Apple Pay component security](https://support.apple.com/guide/security/apple-pay-component-security-sec2561eb018/web)

SE 内有 Apple Pay 管理 applet 和发行方／卡组织 applet；支付数据受安全域密钥保护。模拟 Java Card 运行环境，并不同时获得这些 applet、密钥或发行方 provision 能力。[How Apple Pay keeps users’ purchases protected](https://support.apple.com/en-ca/guide/security/seccb53a35f0/web)

### 绑卡不仅下载一张卡面

Apple 的 Link and Provision 同时下载 Wallet pass 和把卡绑定到 SE；卡面文件还有“SE 是否完成个性化”等状态。发行方 App 推送绑卡也仍走受保护流程，不会因为改用银行 App 就绕过 SE。[Adding credit or debit cards](https://support.apple.com/guide/security/adding-credit-or-debit-cards-to-apple-pay-secdc2567239/web)

官方 In-App Provisioning 指南列出证书、nonce 和 SE 计算的 `nonceSignature`，发行方以公钥加密 payload；SEID 用于标识签名和保存卡数据的 SE。因此修改 SEID 字符串或让本地能力检测返回 true，不构成完成密码学流程的实现。[Apple 官方 provisioning 指南](https://applepaydemo.apple.com/in-app-provisioning)

### App／网页付款仍由 SE 运算

官方流程是 Apple 服务器提供防重放值，SE 生成并加密支付凭证，服务器校验并按商户密钥重新加密后才交回商户。判断：只伪造 Wallet UI、复制数据库或复用旧 token 无法替代新的有效支付凭证。[Paying with cards using Apple Pay](https://support.apple.com/guide/security/paying-with-cards-using-apple-pay-secfbd5c0e54/web)

SEP 与 SE 出厂配置彼此长期公钥，硬件保存私钥，运行期用 ECDH 建立共享秘密；授权还绑定 AR、认证方式及 contactless／e-commerce 交易类型。判断：从 Mac 或 iPhone 仅转发一个 SE，仍须解决它信任哪个 SEP、如何接受交易授权的问题。[Payment authorization with Apple Pay](https://support.apple.com/guide/security/payment-authorization-with-apple-pay-secc1f57e189/web)

不需要 RF 天线不等于不需要内部 SE 驱动／传输。Apple 的组件说明还指出 NFC controller 负责 AP 与 SE 的通信路由；具体镜像是否依赖这一栈须取证，不能先假定直接 APDU 即可。

## 开源和其它虚拟化项目

| 项目／一手来源 | 可借鉴能力 | 与真实绑卡的距离 |
| --- | --- | --- |
| [jCardSim Simulator.java](https://github.com/licel/jcardsim/blob/master/src/main/java/com/licel/jcardsim/base/Simulator.java) | Java Card applet 安装、选择、APDU 调用 | 可做协议实验；未见 Apple Pay SE 身份、个性化及发行方密钥实现 |
| [vsmartcard 文档](https://frankmorgner.github.io/vsmartcard/virtualsmartcard/README.html)／[源码](https://github.com/frankmorgner/vsmartcard) | PC/SC 虚拟读卡器、网络 socket 和实体卡 relay | 证明普通智能卡可转发；没有 iPhone 内嵌 SE 接口和 SEP 配对实现。也依赖 Python，不能直接进入本项目产品运行时 |
| [GlobalPlatformPro](https://github.com/martinpaljak/GlobalPlatformPro) | 持有正确权限／管理密钥时管理 Java Card applet | 卡管理工具，不是 Apple Pay 模型；不提供 Apple 或银行的安全域密钥 |
| [jprx/qemu-sptm](https://github.com/jprx/qemu-sptm) | README 将部分硬件标为用于启动的 fake，SEP 列出 invalidate HMAC | 是 SEP 启动兼容线索；未见真实支付 SE 实现。本轮未逐行审计所有内部设备模型 |
| [QEMUAppleSilicon](https://github.com/cutecatsandvirtualmachines/QEMUAppleSilicon) | Apple ARM／iPhone guest 和 SEP 相关研究 | 未找到真实 Wallet 绑卡的证据；支持 SEP 不推出支持 SE |
| [QEMU VMApple](https://github.com/qemu/qemu/blob/master/docs/system/arm/vmapple.rst) | Apple Silicon macOS VM 设备模型 | 文档没有提供支付 SE passthrough 的实现依据 |
| [Corellium SEP](https://support.corellium.com/device-settings/sep)／[iOS limitations](https://support.corellium.com/devices/ios) | 商业产品的 SEP 协议模拟，部分部署可运行 SEPOS | 闭源且是 SEP；没有找到真实 Wallet 绑卡或 SE 透传能力证据 |

## 各路线判断

| 路线 | 结论 | 关键边界 |
| --- | --- | --- |
| 软件 SE + jCardSim | 可做实验模型；当前没有真实绑卡依据 | 运算／协议兼容不产生支付 applet 和受信任 provision 能力 |
| 外接普通 Java Card／USB 智能卡 | 不能作为现成 Apple Pay SE 替换件 | 即使 APDU 通，也没有相应信任和配对 |
| 宿主 Mac SE 裸透传 | 未找到本项目／公开方案，不可承诺可行 | 宿主安全元件服务边界、虚拟机接口及 SEP 配对均未解决 |
| 真 iPhone SE 裸透传 | 未找到端到端方案 | 不是公开 USB PC/SC 设备；仅转发 SE 不能取得原 SEP 的可信授权 |
| 真机完成完整授权后回传商户支付结果 | 有官方网页跨设备流程可参考 | 是应用层付款协作，卡仍绑定真机；不能直接承诺任意 iOS App 透明兼容 |
| Xcode Simulator／Apple Pay sandbox | 适合各自测试范围 | Simulator 给假支付数据；sandbox 测试卡不用于生产，不能默认 vphone 已具备 sandbox 设备能力 |

Apple 明确 Simulator 的支付 sheet 使用模拟卡并返回明文 dummy data；它是 UI 接入测试，不是真卡 Wallet 绑定。[Authorizing Payments](https://developer.apple.com/library/archive/ApplePay_Guide/Authorization.html)

Apple Pay sandbox 列出受支持设备、测试账号与测试卡；生产环境仍使用真实卡。因此“改沙盒开关”不是补齐虚拟 SE 的证据。[Sandbox Testing](https://developer.apple.com/apple-pay/sandbox-testing/)

Apple NFC & SE Platform 是独立于 Apple Pay／Wallet 的第三方凭证平台，并非供 VM 注册软件 SE provider 的入口。[官方平台说明](https://developer.apple.com/support/nfc-se-platform/)

## 推荐推进顺序与停止条件

1. **若必须 VM 自身真实绑卡**：下一步只做 guest 能力诊断。指定一个现有研究实例，检查 Wallet／passd、SE 驱动及服务是否存在、SEID 查询和首次失败位置；不输入真实卡、不先造模拟器。用日志和 I/O 服务区分界面隐藏、缺驱动、缺 SE、配对或服务资格失败。未得到新的受信任 SE 接口证据前，不承诺补几个补丁能成功。
2. **若目标是完成真实网页付款**：优先验证商户是否提供 Apple Pay 跨浏览器扫码或可在宿主继续的结账链接。官方支持电脑／平板第三方浏览器发起，再由受支持 iPhone／iPad 扫码确认；中国大陆不支持该第三方浏览器路径。vphone 是否被商户当作受支持发起端尚未验证，必要时由宿主浏览器继续，订单／会话转移取决于商户。[官方流程](https://support.apple.com/en-gb/guide/safari/ibrw9b779bd3/mac)／[地区与平台 FAQ](https://applepaypartners.apple.com/merchants/features/apple-pay-in-third-party-browsers)
3. **若目标是开发支付 UI／商户接入**：选官方 Simulator 或支持设备上的 sandbox，把验收目标写清楚，不把假数据测试标为真实绑卡能力。

后续如确需订单协作模块，应遵循现有架构边界，隔离在 `Integrations/`；不要将业务付款策略、卡数据放进 VM manifest、helper 或固件。本轮只新增研究文档，不新增补丁，不修改版本或部署产物。

## 第二轮：可参考 Demo 与具体验证路径

2026-10-23 继续调查。问题聚焦于“已有哪一段确实能运行、如何判断 vphone 的缺口”，不把普通商户 SDK 误归为 SE 实现。

### 新增的重要参考

| 参考 | 已展示／实现的部分 | 运行前提与证据边界 |
| --- | --- | --- |
| [苹果官方网页交互 Demo](https://applepaydemo.apple.com/) | 支付请求、商户验证、事件回调、Transcript 和可复制的 Show Source | 官方明确不扣款；适合作为现成网页对照。能完成 Demo 不等于银行扣款，也不等于 VM 自身绑卡 |
| [Offering Apple Pay in Your App](https://developer.apple.com/documentation/passkit/offering-apple-pay-in-your-app) | 官方可下载 App 示例，`PaymentHandler`、能力检测、支付 sheet 和 delegate | 需要开发者账号／merchant 配置；真机需要已绑定支付卡，Simulator 不需要卡。示例将服务端处理留空，UI success 不构成处理商授权成功 |
| [stripe-archive/ApplePayStubs](https://github.com/stripe-archive/ApplePayStubs) | 替代 `PKPaymentAuthorizationViewController` 的测试 UI，生成测试用 `PKPayment` | 2021 年归档，iOS 9 后已被官方 Simulator 替代；作者明确 token 是 stub／invalid。参考它可理解如何分离 UI，但不是可用于生产的 Wallet／SE |
| [beatty/applepay_crypto_demo](https://github.com/beatty/applepay_crypto_demo) | 对已有 PassKit payment token 做商户侧解密 | README 要求先从支持 Apple Pay 的 App 取得 JSON，再输入 merchant 证书与私钥；未实现 Apple 签名验证。不能生成 SE 绑卡身份或替代 SE 产生支付密文 |
| [QIWI In-App Provisioning Utils](https://github.com/qiwi/apple-pay-in-app-provisioning-utils) | [PassKitRequestGenerator.swift](https://github.com/qiwi/apple-pay-in-app-provisioning-utils/blob/master/InAppProvisioningUtils/Classes/PassKitRequestGenerator.swift) 创建系统绑卡 UI；[PassKitViewControllerDelegate.swift](https://github.com/qiwi/apple-pay-in-app-provisioning-utils/blob/master/InAppProvisioningUtils/Classes/PassKitViewControllerDelegate.swift) 将系统证书、nonce、nonceSignature 交给后端 | 是发行方客户端接线代码；仍需特殊 provisioning entitlement、卡组织配置和发行方后端，未实现 SE 或本地 nonce 签名 |
| [OCLP T1 issue #1103](https://github.com/dortania/OpenCore-Legacy-Patcher/issues/1103)／[修复 commit 1aee2e5](https://github.com/dortania/OpenCore-Legacy-Patcher/commit/1aee2e5dfa12d10e218a51e4151ac2e96705ae9e)／[当前 T1 patch set](https://github.com/dortania/OpenCore-Legacy-Patcher/blob/main/opencore_legacy_patcher/sys_patch/patchsets/hardware/misc/t1_security.py) | 维护者将旧 Mac T1 支持问题标为 v1.1.0 已解决；patch set 明确列出 Apple Pay 所需库和服务 | 依赖原机真实 T1，是恢复软件与硬件通信的参考；没有证明跨主板、跨 VM 透传或软件模拟。issue 关闭也不代替本轮真实绑卡验收 |
| [NFHardwareManager.h](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/NearField.framework/NFHardwareManager.h)／[NFECommercePaymentSession.h](https://github.com/nst/iOS-Runtime-Headers/blob/master/PrivateFrameworks/NearField.framework/NFECommercePaymentSession.h) | 历史运行时导出有 `getSecureElementInfo`、`secureElements`、`startECommercePaymentSession:`，以及 `allApplets`／`performECommercePayment:request:error:` | 是声明而非实现源码；只提供定位入口。必须对实际 guest 做 selector／签名核对，不能把旧头文件直接用于 iOS 27；不能从方法存在推出硬件可用 |

OCLP 的维护者描述调用链为 `SecureElementHelper → NearField/NFHardwareManager → libnfshared → nfcd → libPN548_API/AppleSSE`，而 T1 本体通过内部 USB 2.0 连接。**工程判断**：它证明“原配硬件还在，只是系统取消驱动”的问题可以研究恢复；没有证明取一个 T1 USB 通道就能给 Apple Silicon iOS guest 付款。本项目应借鉴其逐层取证方法，不能直接搬 macOS 二进制或套用其补丁。

[vphone discussion #175](https://github.com/Lakr233/vphone-cli/discussions/175) 和 [PR #333](https://github.com/Lakr233/vphone-cli/pull/333) 是 Apple services／experimental variant 的公开线索；讨论包含设备 attestation 的调查，不是 Wallet 绑卡完成报告。搜索没有找到可复现的“SE 模拟 → provision → payment token → 处理商验证”完整代码。是否 App Store 登录成功也不能单独证明 Apple Pay 能用。

### 验证 A：最小公开 API 探针，不涉及卡数据

优先在独立研究 App 的正常前台上下文采集三个布尔值；不需要展示支付或添加卡界面：

```objc
@import Foundation;
@import PassKit;
void collectWalletCapability(void) {
    NSDictionary *result = @{
        @"passLibraryAvailable": @([PKPassLibrary isPassLibraryAvailable]),
        @"canMakePayments": @([PKPaymentAuthorizationController canMakePayments]),
        @"canAddPaymentPass": @([PKAddPaymentPassViewController canAddPaymentPass])
    };
    NSLog(@"%@", result);
}
```

本机 iPhoneOS27.0 SDK 中已核对这些方法声明；使用 `xcrun clang -fsyntax-only -fobjc-arc -fmodules -target arm64-apple-ios15.0` 加对应 SDK 对上述完整片段检查，退出码 0。仅证明宿主交叉编译语法通过，不代表 guest 执行成功。应使用同一代码分别观察 vphone、Xcode Simulator 和可用的真实设备，并记录签名／entitlement／账号上下文。

- `passLibraryAvailable=true` 只说明可访问 pass library，不说明银行卡可用。
- `canMakePayments=false` 可能是能力或用户限制，不能单独归因为没有 SE。
- `canAddPaymentPass=true` 是进入下一步的资格信号，不证明 provision 一定成功；false 也需要结合配置、权限与日志解释。
- 后续可加 `canMakePaymentsUsingNetworks:` 检查已有支付网络，但无卡时 false 本来就可能正常。不要修改 API 返回值来“通过”检查。

SDK 依据：`PassKit.framework/Headers/PKPaymentAuthorizationController.h`、`PKAddPaymentPassViewController.h`、`PKPassLibrary.h`；[苹果能力检测示例](https://developer.apple.com/documentation/passkit/offering-apple-pay-in-your-app)。不要直接把 root daemon 调用结果当作正常 merchant App 的等价结果。

### 验证 B：SE 栈只读诊断，判断是否值得继续模拟

先固定实例目录、绑定 bundle、guest 版本，使用现有 guest 控制／文件访问能力，不升级或重刷。检查 NearField／PassKit 组件、`nfcd`／`passd` 服务与 I/O 注册情况。然后在确认当前版本签名和调用权限后，只尝试有超时的 controller／SE 元数据查询；记录“查询成功但为空”“权限拒绝”“服务不可达”“硬件初始化失败”四类结果。原始 SEID 不对外公开，仅记录是否存在和脱敏标识。不读取密钥、不调用 factory/test mode、不执行支付／applet 管理方法。

| 观察 | 下一步 | 不能据此声称 |
| --- | --- | --- |
| framework／daemon 缺失 | 先查镜像组件和原始固件来源 | 缺组件就意味着软件 SE 不可能 |
| 服务可连但无 controller／SE | 定位虚拟设备与驱动边界 | 改 MobileGestalt 就能绑卡 |
| SE 元数据可读但不能 provision | 定位配对、用户认证、服务资格与签名流程 | 有 SEID 就必然支持 Apple Pay |
| 权限错误／超时 | 修正探针上下文或保留未知结果 | 等同于硬件不存在 |

**继续条件**：拿到可解释的失败层，或者发现当前平台确有未使用的支付 SE 能力。只看到历史头文件而没有设备响应时，不立即开发通用 APDU 模拟平台。

### 验证 C：用现成 Demo 做对照

先用苹果官方网页 Demo，分别观察 vphone 浏览器与正常宿主／真机的能力检测、sheet、商户验证和 Transcript。可先读 `window.ApplePaySession` 是否存在及 `canMakePayments()`，只有有合法 merchant 上下文才调用需要 merchant ID 的检查。[Web 能力检测文档](https://developer.apple.com/documentation/applepayontheweb/checking-for-apple-pay-availability)

若 vphone 直接报告不支持，结合验证 A/B 定位，不将“换个 Demo”当修复；若只是原生 UI 研究，运行官方 App 示例的 Simulator 对照即可。源码展示的 UI success、token 字段非空、浏览器出现按钮，分别是不同层次的证据。

### 验证 D：真正需要的端到端证据

只有 A/B 提示具备进一步条件，再在独立测试设备／环境上使用 Apple 官方 sandbox；不为了测试更改现用 VM 的 Apple Account。验收分为：测试卡完成 provision、SE pass 状态激活、用户正常授权、获得新交易凭证、处理商测试环境接受并返回匹配订单的结果。处理商需明确兼容该 sandbox，不能默认所有 PSP 都接受苹果测试卡。

模拟器虚构 token 不计为通过；官方示例回调 `.success` 不计为银行授权；sandbox 接受也不计为真实卡生产能力。本轮没有执行 A–D 的 guest 或账号操作，以上是待执行验证设计。

若实际目标只是 VM 中订单能够付款，可单独验证官方网页跨设备路径：扫码和确认在原有真实设备完成，VM／宿主只保留订单和支付结果。它可能得到可用业务闭环，但不会给每个 VM 分配独立 SE 身份。
