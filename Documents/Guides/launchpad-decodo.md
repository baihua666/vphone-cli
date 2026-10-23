# Launchpad 的 Decodo 管理

本仓库扩展的 Launchpad 在机器检查器中提供「代理出口 → Decodo 配置与换 IP」，使用原生 Form。可读取本机凭据、选择美国 ZIP、保存独立五分钟 IP Lock 会话、一键申请新会话并从 guest 检测 HTTPS 公网 IPv4。官方上游公证版不包含该业务界面。

共享服务来自现有 `VPhoneWSCore` Swift package；Launchpad 不启动 Workstation，也没有第二套代理写入逻辑。Launchpad 的代理与检测命令解析 `launchpad.json`，不会被旧 `.vphone-ws.json` 覆盖；同一运行路径在所有已登记资料库中的重复绑定会被拒绝。Workstation 保留原绑定解析作为备用。

凭据默认读取 `~/.vphone/decodo.json`，权限为 0600；也可在表单指定绝对路径或通过 `VPHONE_DECODO_CONFIG` 覆盖。已有会话换新直接复用 Clash 节点凭据，不需要再次填写密码。表单不会保存独立凭据文件，保存动作写入原有 Clash 私有节点。

前提是已有 Clash Rule/TUN/strict 配置、对应实例的唯一 PROCESS-PATH 规则及代理扩展，且运行中网络为 tunnel。当前版本不自动安装 Clash、购买流量、建立新路径规则或复制 runtime。切换 Bundle 后应在维护窗口重启并核对实际路径再使用代理功能。

「配置已生效」与「guest 检测成功」分别报告。认证/流量问题可能导致规则正确但无法联网。仅验证 guest HTTPS/TCP 出口；不承诺 UDP、全部 App 或 ZIP 的街道精度。五分钟由供应商处理，不是 UI 自动轮换计时器。

## 验证和部署

- `./scripts/dev.sh test launchpad`：共享核心测试，覆盖 Launchpad 绑定优先级、跨库共用路径拒绝、绑定变化、配置读取无写入、配置与轮换、非 tunnel 拒绝及检测失败状态。
- `./scripts/dev.sh build launchpad`：实际 Xcode UI 集成构建；产物位于 `.build/LaunchpadDecodo/Build/Products/Debug/`。
- 2026-10-22 本次只修改源码并构建测试，**没有替换 /Applications app、启停 VM、修改实际代理或凭据文件**。另一会话正在操作现有两台机器，真实新 UI 验收留待维护窗口；不能复用旧 Workstation 的实测结果当新界面验收。
- 自定义 app 需要有效 Apple 签名和 Helper 互信配置；本机可用 Apple Development，对外分发用 Developer ID，源码构建不继承官方签名。不要直接覆盖正在使用的官方 app。

其他 Mac 的安装、签名、接入、验收及 Workstation 备用步骤统一见 [vphone-management Skill](../../Skills/vphone-management/SKILL.md)。真实凭据和机器数据不经 Git 同步。

## ISP 已购端点（2026-10-22）

机器检查器 →「代理出口」→「ISP / Decodo 出口与换 IP…」，默认显示 ISP。
从当前 Clash 配置识别实际网关 `isp.decodo.com`、静态端口 10001–63000 的 HTTP/SOCKS5 节点；无需重复输入现有节点的密码。
「应用出口并检测」使用选中的端点；「一键换 IP」在同一共享服务事务中选择未被任何 PROCESS-PATH 规则使用且不同于当前出口的端点，沿用原持久化、重载验证、回滚和目标连接断开逻辑。端点不足时报错，不购买或新增套餐。
这是一组已配置端口的轮换，不保证公网 IP 不重复、不保证 ZIP；UDP 能力由节点和 Clash 规则决定，本机双机的 UDP 443 REJECT 规则仍独立保留。

构建与测试不等于安装。2026-10-22 本机没有可用 Developer ID Application 身份，无法按既有 Helper 签名要求替换官方 app；正式安装保持原样。独立 bundle ID 的只读预览读取真实机器和代理配置，禁用写操作，不启动 Helper 或管理服务。

2026-10-22 后续更正：已核对代码与 Apple SMJobBless 官方要求，本机开发证书可满足现有互信条件。使用有效 Apple Development 证书同时重建并签署 app、Helper、CLI 和 launcher，完整签名验证通过，已部署到 /Applications/vphone-launchpad.app。系统 Helper 与内置 Helper SHA256 一致。正式 UI 一键将 custom 从 ISP 10003 切到 10002，guest 实测 9.249.113.1，official 复测仍为 9.249.113.0。旧官方 app 保存在 /Applications/vphone-launchpad.previous-20261022.app；未重启 VM。系统仍可能要求对新签名重新授予开发者工具权限；代理操作已实测成功，未据此宣称核心 Bundle 安装/冷启动权限全部验收。

## 只读出口检测与归属地（2026-10-22）

- ISP 标签改为「ISP · 按流量」。代理配置名、真实配置的网关 host:port、guest 实测公网 IPv4 分开展示；入口端口不是邮编或公网 IP。
- 「检测当前 IP」只调用所选实例绑定 CLI 的 `vm network --probe --json`，不依赖表单待选入口，不写 Clash、不重载、不关闭连接、不重启 VM。仅用户点击时检测，不自动轮询。失败清空旧实测结果。
- 成功后用 guest 返回的 IPv4 查询 `https://ipwho.is/{IP}`，展示可用的国家/地区/城市、邮编和运营商。只提交实测 IP，不提交代理账号或密码；界面显示来源和第三方查询说明。服务限流、超时或缺失字段不影响公网 IP 展示。
- IP 归属地是数据库估算，不代表街道地址、GPS 或目标 App 使用的地理库，也不能证明所有 App/UDP/DNS 流量已分流。手动检测结果只代表标注时刻。
- 官方接口契约：https://ipwhois.io/documentation 。无需密钥，使用 HTTPS、10 秒超时；返回 IP 必须与 guest 实测 IP 一致。
- 本轮只构建与离线测试，未替换运行中的 Launchpad、启停 VM 或调用真实 guest 检测；需在允许部署后验收现场结果。

2026-10-22 本机后续验收：移除开发者工具旧签名授权条目，重新添加当前安装 app 后 6/6 主机检查通过。两台已通过 Launchpad 正常停止并重新启动，guest 独立 ISP 出口保留；两台各自的一键换 IP 成功且另一台不变，详见 `Research/Host/launchpad_restart_isp_20261022.md`。

后续部署更正：用户要求取消独立只读预览，已移除该入口与 `readOnly` 参数，以现有 Apple Development 身份构建、签名并更新 `/Applications/vphone-launchpad.app`。真实界面的「检测当前 IP」「应用出口并检测」「一键换 IP」均可用；本次没有点击代理动作。更新前后 VM PID 373 / 98848 及启动时间相同，control status 显示 running=2、hostReady=true、helper ready (15)。旧 app 保留于 `/Applications/vphone-launchpad.before-ip-detection-20261022.app`。后续统一操作真实 UI。

### 归属地 TLS 故障修复

本机实际复现 ipwho.is HTTPS 握手失败（URLSession TLS error，curl 35）。增加 HTTPS 备用接口 `ipwhois.app/json/{guestIP}`，不关闭 TLS 校验、不改变 Clash 规则；仍严格核对返回 IP。备用接口的顶层 isp/asn 规范化到现有模型，来源按实际成功接口显示。仅缺失邮编时显示未知。备用请求使用同一 guest 实测 IP，不将 Mac 的出口当成虚拟机出口。

修复已部署到真实 Launchpad。现场界面确认归属地可返回：official 页面在 2026-10-22T06:50:56Z 的检测结果为 216.132.139.129，United States / New Jersey / Princeton，运营商 RCN，来源 ipwhois.app，邮编未知。验证期间另一操作者切换了实例与代理入口，本轮不据此宣称目标城市或换 IP 验收通过；这里只确认 HTTPS 备用归属地链路在真实 UI 返回。105 项测试与独立目录 LaunchpadGeoFix 构建通过。两台 VM 的原 PID/启动时间保持。

## 2026-10-22：ISP 城市出口（替代四端口轮换）

Launchpad → 选择运行中的实例 →「ISP / Decodo 出口与换 IP」→ ISP 按流量。
国家当前为美国，城市填 `New York`（也接受 `New York City`），点击「获取地区出口并检测」。
「一键换 IP」沿用输入的城市，为该机节点从 10001–63000 中选取不同于已配置入口的端口，
向 Decodo 请求出口，不再在旧四个节点间轮换。账号和已有中转从本机 Clash ISP 配置复用；
不会购买套餐，也不会使用动态住宅余额。节点按实例资料夹区分，修改时保留另一台的节点和规则。

当前 ISP 网关实测拒绝文档示例 `city-new_york`（HTTP 400），接受 `city-new_york_city`；
服务自动转换纽约别名。无可用城市不会静默降级成全国随机 IP。端口改变不保证供应商一定分配不同 IP，
可再次手动换新。城市级定位不代表 ZIP 10001 或某个街道附近，ISP 不发送 ZIP 参数。

验证以 guest 的 HTTPS 公网 IP 为准，归属地使用第三方数据库。实际出现过供应商 IPinfo
显示 New York City、ipwhois.app 显示其它城市的分歧；界面在归属地不符时明确提示，不能视为定位通过。
最终两机实测与换新记录见 `Research/Host/decodo_isp_city_20261022.md`。

## Decodo/IPInfo 优先与第三方对照

界面分开展示「主要归属地 · Decodo / IPInfo」和「第三方对照」，每份结果独立展示城市、地区、邮编、运营商及来源。主结果通过当前已生效 Decodo HTTPS 入口请求 `https://ip.decodo.com/json?provider=IPinfo`，凭据仅通过 curl stdin 传递；复用本机已有 SOCKS/mixed 入口访问上游，不创建或切换代理规则。返回 IP 必须等于先前从 guest 测得的 IP，查询前后入口必须一致；不一致时主结果显示错误，不能使用另一个出口的定位。

第三方按同一 guest IP 查询；主查询失败不会把第三方冒充主来源，也不跨来源补邮编。两份已有字段不一致时逐项提示国家/地区/城市/邮编差异；缺失字段显示未知。ISP 目标城市验证采用主来源，不能据此保证目标 App 的数据库也一致。原始官方契约与数据库说明：https://help.decodo.com/docs/isp-pay-per-gb-proxy-user-pass-requests 和 https://help.decodo.com/docs/ip-location-does-not-match 。

## 官网 ISP 地区选择（2026-10-22）

Launchpad「ISP / Decodo 出口与换 IP」打开时同步官网地区，也可点击「同步官网地区」。复用指定 Chrome 配置目录（默认 Default）中 dashboard.decodo.cn 的 JWT-AUTH Cookie，仅发送到同站点 `/subscription-api/v1/subscriptions`，不读取其它站点 Cookie、不持久化明文、不跟随重定向。macOS 钥匙串可能要求授权读取 Chrome Safe Storage；登录过期请在 Chrome 正常登录后重新同步。

使用 `static_isp.ip_locations` 与 `ip_locations_by_city`，按官网排除 count 为零的地区；支持随机、国家、美国州、城市分类和忽略大小写的名称搜索。列表来自账户产品库存，不是全球地名库。选择后才启用「获取地区出口并检测」和「一键换 IP」；单纯搜索、同步或选择不会修改代理。两按钮复用每实例 ISP 新端口配置流程，供应商可能分配重复 IP。国家/州筛选不保证城市或街道定位。

接口是官网内部接口，响应变化会提示同步失败并禁用地区应用，不静默使用猜测城市或其它产品列表。当前不自动刷新网页登录凭据；可在「浏览器登录会话」指定其它 Chrome 配置目录。

## 独立账号设置与授权续期（取代上述 Chrome Cookie 读取）

2026-10-22：Launchpad 菜单「设置」或代理页「Decodo 账号设置…」管理网站邮箱、密码、Public API Key 和可选 JWT-AUTH / refresh_token。此版本不再读取 Chrome 数据库或调用钥匙串。明文用户配置 `~/.vphone/decodo-account.json` 优先于源码仓库 `.local/decodo-account.json`，可用 `VPHONE_DECODO_ACCOUNT` 指定兜底文件。配置模板为 `decodo-account.example.json`；真实文件 0600、Git 忽略，跨设备单独复制。

官方 https://help.decodo.com/api-reference/public-api-key-authentication 明确 Public API 不支持 ISP 和数据中心产品。当前功能只有 ISP 地区查询，因此此路径走授权接口；API Key 可保存，但不发送给不支持它的 ISP 接口，不以 Web Data API Key 替代账号授权。

按需自动续期：现有会话访问订阅 → HTTP 401 时 POST `/api/v1/token/refresh` → 重试 → 刷新过期时尝试一次 `/api/v1/users/login/`。HTTP 403/二次验证/验证码停止并提示，不循环尝试、不绕过验证。成功后的新会话保存回当前来源文件；期间账号设置变化则拒绝覆盖。设置页「保存并验证 / 续期」读取 ISP 地区验证授权，不修改虚拟机出口。未提供网站账号时不能完成真实账号登录验收，代理账号不能替代网站邮箱密码。

## 原生网络备用方案（按能力检测的实验功能）

代理出口页新增网络方案选择，Clash 原逻辑保留。原生 HTTPS 在每个 VM 的用户态网络中独立应用，不读取 Clash；提供直连检测、应用/换 IP 与明确切回 Clash。使用方法、版本及验收边界见 [原生代理说明](native-decodo-proxy.md)。当前运行的 2.8 实例不会被自动升级或改变出口。

### 2026-10-23：统一实测公网 IP 显示（源码验证，尚未部署）

Launchpad 的检查网络、准备出口、打开业务网页与代理面板共用按实例路径保存的实测 IP / 检测时间。操作开始时清除旧结果，成功后更新；失败不把旧 IP 当作当前结果。URL 参数行与操作完成提示不再保存或显示另一份 IP。Clash / 原生代理应用和换 IP 完成后，以 guest 只读检测刷新共享结果；独立入口直连检测不覆盖 guest 结果。

验证：VPhoneLaunchpad Debug 构建通过，`zsh VPhoneLaunchpad/Tests/FlywheelWebActionTests.sh` 通过，包含时间更新、实例隔离、打开网页后同步、失败清除以及现有 RPC/实例校验回归。本轮没有操作运行中 VM、切换代理或替换已安装 app；运行中的管理界面仍为旧版，需在允许更新管理 app 的窗口部署后验证视觉效果。
