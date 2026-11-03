# X 原生登录来源排查（2026-11-02）

## 11:40–11:46 邮箱入口与网络对照

本轮继续使用原生 X 12.39、实例 1 与原 pinned Core，未改底层。

- 冷启 X 后从欢迎页信封入口进入邮箱验证码流程，读回确认邮箱完整。
  提交后同样出现 `Please use official X apps to proceed or try again later.`；
  未进入验证码输入页，不把页面预告发送验证码当作已发送成功。
- 自动时间开启。通过 guest HTTPS 出口检测，Decodo 原生代理出口为
  `144.225.198.143`；临时关闭该代理，使用已有宿主路由，出口变为
  `178.249.213.185`。重启 X 清除旧连接，再走相同邮箱流程，仍返回相同拒绝。
  宿主路由未证明是无 VPN 的住宅直连，因此不能声称已排除所有 IP 风控。
- 已恢复原 `isp.decodo.com:44611` 配置，并再次通过 guest 检测确认出口恢复
  `144.225.198.143`。禁用原生代理会删除 reference 文件，恢复使用原端口唯一
  对应的既有配置文件；未重建凭据、换供应商或改实例网络模式。
- 原生系统日志采集受大量音频/XPC 消息影响，3000 条全系统与 800 条 Twitter
  采集均截断在开头约一秒；没有覆盖完整请求，不能据此断言无认证错误。
- 对现有 IPA 做只读字符串检查：`XAppLibraries` 含 `AttestationFlowError`，
  `T1Twitter` 含 `XAppAttestation` 协议符号。只证明包中存在认证相关实现，
  不证明此次拒绝调用了 Apple App Attest，更不证明仅修改签名即可解决。

外部一手资料：

- X 官方排障建议检查网络/VPN：
  https://help.x.com/en/using-x/x-ios-app-not-working
- NeoFreeBird #78 是 iOS 侧载用户报告 `Loginerror.AttestationDenied`，
  支持客户端认证这一排查方向，但不同设备/版本不能直接套用：
  https://github.com/NeoFreeBird/app/issues/78
- #177（2026-10-27/28）有 stock X 也失败的用户报告及贡献者的网络归因。
  贡献者经历不是 X 官方诊断；本轮网络对照正是用于检验该线索：
  https://github.com/NeoFreeBird/app/issues/177
- 搜索摘要曾显示 NeoFreeBird README 有 attestation 警告，但本轮打开当前 v7
  README 未见该段，不将旧摘要当作现行维护者结论。

判断：用户名和邮箱入口均在密码/验证码验证前被拒，单纯切换登录入口、冷启、
切换现有两条网络路线尚不能修复。剩余重点是当前包/设备认证与账户环境风控。
进一步有效对照应采用相同账号、相同网络下真实 iPhone 的官方 X；这不替换
虚拟机交付目标，仅用于隔离变量。当前没有可证明有效的底层补丁方案，未实施
注入、校验绕过、会话搬运或 App Store 重试。原生完整链路仍未验收。

证据：本模块 `Artifacts/x-email-recheck-20261102/`；`rejected.jpg` 为邮箱入口拒绝。

## 11:28 原生复测与上游方案检索

用户明确停止 App Store 路线、保留现有 X 原生路线，不改网页。
通过 GitHub API 检索上游 Issues/PR 的 Twitter、Tweetie2、official X、login、
security checks，以及 Discussions 的 Twitter；未找到 X 当前登录提示的已验证修复。
搜索无结果不是证明绝不存在解决办法。

- PR #465 为第三方登录研究，closed、merged=false，不能作为已合入官方方案。
  https://github.com/Lakr233/vphone-cli/pull/465
- Issue #547 的 owner 回复确认解密 IPA 原签名失效时需 ad-hoc 重签；
  这解决安装，不保证应用业务认证。本次安装后签名不同并不能单独证明 X 拒绝的根因。
  https://github.com/Lakr233/vphone-cli/issues/547
- Issue #212 的 owner 明确项目不提供针对消费应用安全检查的绕过方案。
  https://github.com/Lakr233/vphone-cli/issues/212
- PR #779 未合并；系统应用下载/installd 修复明确不声称解决 account attestation、
  FairPlay 或 Configurator App Store 列表安装，不适用于本次 X 登录结论。
  https://github.com/Lakr233/vphone-cli/pull/779

现场发现实例已停止，按原绑定 2.13.4-local.666ac4da 启动实例 1，未操作实例 4。
冷启动第一次输入因焦点切换漏了首字符，返回找不到账号；读回发现后立即校正，
第二次提交前确认完整 `tubao1985`。11:28:48 北京时间再次返回
`Please use official X apps to proceed or try again later.`，仍未进入密码页。
同时间段网络日志有 HTTP 200/204，证明存在成功网络响应；未解析认证响应正文，
不把所有 HTTP 200 都等同登录成功，也不推定唯一的签名/设备/风控原因。
本次没有输入密码、申请验证码、改简介、发帖或改变 guest/网络。

证据：`Artifacts/x-native-recheck-20261102/rejected.jpg`、`correct-username.json`。
当前实际阻塞仍为客户端/环境认证拒绝；没有查到可直接部署的官方修复，
因此完整链路及重复运行防重仍未通过真实验收。不会用 App Store、网页或未经校准的
空脚本冒充完成，也没有执行之前提出的 libsigninfix 停用方案。

状态：原生登录未通过，不能宣称完整一键链路已可运行。用户明确要求保留原生路线。
2026-11-02 官方资料复核：当前不能将虚拟机内 App Store 登录下载作为可交付路径。
上游 main 的 Documents/Guides/create-and-run.md（In Launchpad）明确写道：
“Apple Account is not offered: the guest refuses its sign-in either way”。
https://github.com/Lakr233/vphone-cli/blob/main/Documents/Guides/create-and-run.md#in-launchpad
上游协作者 zqxwce 在 #249（2026-04-07）确认 Apple ID 相关功能当时不可用；
该条为历史佐证，当前结论以现行文档及本机实测为主。
https://github.com/Lakr233/vphone-cli/issues/249
讨论 #418 明确提及 App Store 不工作以及 Anisette / Apple 服务端障碍，但属于社区讨论，
不把所有发言都当作维护者承诺：https://github.com/Lakr233/vphone-cli/discussions/418
据此撤回“优先停用登录隐藏组件推进官方安装”的建议；尚未执行任何改名或停用。
恢复登录窗口不能证明能完成 Apple 服务认证，当前也不能承诺通过官方 App Store 修复 X。

目标实例 `1-20261023`，原 pinned Core `2.13.4-local.666ac4da`。
测试账号 `tubao1985` 已获用户确认；网页邮箱验证码登录成功，原生尚未进入密码验证。

## 已核对事实

- Launchpad 应用管理在线搜索返回 X 12.39；本地包与已安装应用均为 12.39 / 20，
  bundle ID `com.atebits.Tweetie2`。没有观察到可升级版本。
- 应用管理源码 `ApplicationLibrary.swift` 的 search 使用 Apple iTunes Search；
  download 使用 ARM Store 客户端。因此在线版本来自 Apple 不等于安装包由 App Store 直接安装。
- 本地输入包位于 `~/Library/Application Support/vphone-launchpad/Applications/333903271-12.39.ipa`。
  SHA-256：`4a454401dca98499ee5b52da250988ffc1e3da6eef1e57b16874a946111297aa`。
- 包内 Info.plist：最低 iOS 15.0，SDK 27.1，主程序 Twitter。
- 包内主程序 `LC_ENCRYPTION_INFO_64.cryptid` 为 0；保留 Apple 签名链字段，
  TeamIdentifier 为 N66CZ3Y3BX，但 `codesign --verify` 报 code or signature modified。
  不能将存在签名字段当作签名有效。
- 从当前安装目录只读拉取的主程序，Identifier 为 Twitter，无签名链，TeamIdentifier 未设置；
  与包内主程序哈希不同。既有 `GuestSigner.swift` 确实通过 VPhoneSigner 重签可执行文件。
- 原生用户名提交返回 `Please use official X apps to proceed or try again later.`。
  密码正确性尚未验证；不能归因为错误密码。
- X 用户名页的 AX 树包含不可见的 password 元素。后续脚本必须检查真实页面标题，
  不可仅凭元素存在判断已进入密码页。误填现场已清除并恢复正确用户名后才提交。

## 判断与限制

已排除“没有安装 X”和“版本号明显落后于当前查询结果”。安装来源、解密与重签是
客户端校验失败的重要嫌疑，但没有 X 服务端诊断或同环境官方安装的对照，不能确定唯一根因。
未补丁、注入或绕过 X 校验，也没有修改 Core、guest、helper、代理及实例绑定。
没有重复安装同一个 IPA：那不会提供签名来源不同的对照。

X 官方 iOS 排障页建议更新、重启、检查连接及从 App Store 重装；没有解释本次准确错误：
https://help.x.com/en/using-x/x-ios-app-not-working
其正文系统版本描述与当前 IPA 最低版本存在差异，以实际包要求为准。

虚拟机已注册 `com.apple.AppStore`。后续排查中仅终止并重启 App Store，未改网络或服务，
便完成 JetPack 加载并显示首次使用介绍页；完成介绍并关闭个性化广告后出现 Today 等标签。
因此此前“持续 Loading”并非应用永远无法初始化。但首页随后显示 Cannot Connect，
X 官方商品 URL 也未到可下载安装状态，不能视为官方安装渠道已跑通。

## App Store 进一步诊断

实例 iOS 26.6.2；appstored、itunesstored、amsaccountsd、jetpackassetd 均启用并运行。
appstorecomponentsd 已启用但按需未运行，不据此强行修改服务状态。
2026-11-02 01:18:14 北京时间的真实日志记录：

- 前置请求 HTTP 200，TLS 建立成功，不能笼统判断为完全断网。
- `https://fpinit.itunes.apple.com/v1/signSapSetup` 返回 HTTP 500；
  `AMSErrorDomain 301 / Invalid Status Code`，payload 显示 sign-sap-setup-buffer = Error。
- 后续 `Mescal Session Failure / Context establishment failed during data exchange`，
  media token 不可用，Anisette type 2 生成失败 `-45061`。
- 尚未区分暂时服务问题与该研究 guest 的认证兼容性，不绕过或伪造认证。

账号页能显示 Apple Account Sign In，但点击后未出现输入表单。启动日志确认
`VPSignInFix installed`，源码与历史研究确认该组件用途是压制 Apple ID／商店登录窗口。
当前 `/usr/lib/libsigninfix.dylib` 为普通文件，88064 字节，755。
点击采集没有取得直接的 suppress 日志，因此它是有代码及加载证据支持的独立阻塞嫌疑，
不是已完成停用对照的结论。

已向用户请求单独授权：临时改名备份该组件，仅重启 App Store 验证登录窗口，随后可恢复。
这是 guest 修改，受 AGENTS.md 的底层修改确认规则约束；尚未执行。
其作用仅是恢复正常登录界面，不承诺修复 Mescal。Core、固件、代理和实例绑定均保持原值。
停用期间其他新启动的应用也不会再加载这个登录窗口隐藏组件。

参考 Apple 官方连接排查： https://support.apple.com/en-gb/108093
本机日志：`Artifacts/appstore-20261102/startup.json`、`product-load.json`、`signin-click.json`。

## 后续验收前提

先取得原生客户端可成功登录的正常路径；虚拟机 App Store 路线已停止，
不得沿用本报告早期的商店安装建议。
在此前提成立前，不编造简介、相册及发布的成功结果或未经观察的 UI 选择器。
无需再次注册该邮箱，网页已证明账号可登录；不要重复申请验证码或反复提交原生用户名。
后续需依次完成原生登录、简介修改恢复、相册导入、精确选图、发布核验，以及同目录重复运行。

独立凭据文件：`~/.config/vphone-social-tests/tubao1985.password`，600，仓库外。
不在本报告记录密码或验证码。当前文件尚未通过原生密码登录验证。

## 本机证据

- `Artifacts/x-login-20261102/client-rejected.jpg`、`client-rejected.json`（移除输入值）。
- `Artifacts/x-source-20261102/Info.plist`、`signatures.txt`。
- 两份只读分析的主程序保留在同一证据目录，不用于部署。
