# Decodo ISP 官网地区选择器

## 2026-10-25 空搜索列表修复

现场读取 `https://dashboard.decodo.cn/static-isp-proxies/proxy-setup`：展开地点时无需搜索即可浏览城市列表。Launchpad 同步显示 52 个地区，但空搜索仅显示随机，选择城市分类为空，输入 YORK 才出现 New York City。根因为 Foundation 的 `String.contains("")` 返回 false；原过滤器只对随机选项单独处理空搜索。

复用现有订阅库存、分类、列表与选中逻辑，在共享地区过滤器中显式处理空查询，按所选类型返回全部地区。涉及 Workstation subtree 的 `DecodoLocations.swift`、`Package.swift` 和原测试文件，因为 Launchpad 已通过该 package 复用地区规则；不修改 CLI、Core Bundle、VM、guest、helper、版本、账号文件及出口配置。

编译条件 `VPHONE_CUSTOM_DECODO_LOCATION_BROWSING` 集中定义在 `VPhoneWorkstation/Package.swift` 的 `decodoLocationSettings`，默认开启，同时传给 VPhoneWSCore 和测试 target。Launchpad 静态链接此 package，无跨进程协议变化。清空设置数组并重新构建即可退回原搜索路径（空查询仅随机）；不写持久数据，无需迁移。完整删除本次定制时一起删除该配置、过滤器条件分支和对应测试。此开关仅覆盖本次空查询浏览行为，已有 Decodo/代理业务未完成整体宏隔离。

回归测试先在旧实现复现全部及三个分类共四处失败，修复后覆盖空查询、分类、搜索后清空、无结果及空库存；保留原库存解析与地区凭据生成测试。验证日志位于忽略目录 `.build/decodo-location-*.log`，不包含凭据。关闭宏的独立测试使用忽略目录内的临时 manifest，链接实际源码，未改动正式 manifest。选择地点仅改变表单选中项；本次验收不申请新代理、不换 IP。

交付验证：开启和关闭宏各 121 项共享服务测试通过；`scripts/dev.sh build launchpad` 成功。按已安装 App 的开发签名团队通过命令行构建（团队未写入源码），为 Debug dylib、preview dylib 和完整 App 签名，deep strict 校验通过。已更新 `/Applications/vphone-launchpad.app` 为本地测试产物，产品版本保持 2.8.0，原 App 备份在 `.build/validation/decodo-location-before.app`。安装后 debug dylib SHA-256 与构建产物一致。运行中 VM 的 PID 35663 及 pinned `2.8.0-local.199abaf3` 未变。

在停止的 `2-20261023` 实例表单现场验收：真实账号同步仍为 21 个国家、4 个州、27 个城市；空查询全部列表包含随机及全部地区；国家、州、城市三个分类可直接浏览。搜索 YORK 返回 New York City，清空后恢复城市列表；直接点击城市后表单回填，重新展开保留勾选。未点击获取出口、换 IP 或启动实例。既有检测中的 ipify 证书错误不属于本次列表修复，未绕过证书校验。

2026-10-22：读取官网 index.625a8d9c.js 确认 eNF 组件使用 subscriptions 的 static_isp 地区字段；eNz 为忽略大小写的 substring 搜索，国家 count>0，城市 count>0 且名称非空，美国州从城市去重。州使用 -state-，城市使用 -city-，国家使用 -country-。

使用当前 Chrome Default 的 Decodo JWT-AUTH 对固定 HTTPS subscriptions 接口实测 HTTP 200。只检查产品键与地区字段，没有打印身份/订阅/密码/Cookie；美国城市为 Ashburn、Boston、New York City、Palo Alto、San Jose。未登录为 HTTP 401。

实现位于 VPhoneWSCore 的 DecodoLocations、DecodoBrowserSession；Launchpad 只呈现列表，DecodoProxyController 编排同步及选中地区应用，DecodoISP 复用原有每实例新端口流程。Cookie 不进入持久化文件，URLSession 禁用 Cookie 存储及重定向。未新增服务器、浏览器插件或 guest 依赖。

验证：109 个共享服务测试通过，Launchpad Xcode build 成功，以现有 Apple Development 证书签名并原地更新。保留两台运行中的虚拟机与既有代理配置，未执行实际换 IP；本轮用户要求留给其手动测试。

已安装 app 现场验收：自动同步显示 52 个地区；城市分类搜索 YORK 返回 New York City (New York)，Washington 显示「未找到地点」，Ashburn 返回 Ashburn (Virginia)。选中 Ashburn 后获取出口与一键换 IP 按钮启用，未点击执行。界面留在 custom-2x-20261016 的地区配置，Helper ready (15)，两机 running。

## 独立账号版本

后续按用户要求移除 DecodoBrowserSession 的 Chrome 数据库/钥匙串读取，新增 DecodoAccount、DecodoAccountSession。用户设置文件优先、仓库 .local 文件兜底；API Key 仅保存，官方文档明确不支持 ISP，当前 ISP 路径使用授权接口。HTTP 401 自动刷新并重试，刷新凭据过期时单次登录；403/210 提示网页验证。覆盖刷新轮换、拒绝访问不重试、缺失凭据不请求、文件0600及登录兜底测试。最新共享测试116项通过，Xcode构建及签名校验通过。

已更新 /Applications/vphone-launchpad.app，打开系统 Settings 场景确认邮箱、密码、API Key、可选授权会话字段与配置来源显示。当前未提供网站登录邮箱密码，未进行真实登录/刷新请求；不能将测试传输通过等同于真实账户续期通过。两台VM出口未修改。

部署兼容性：同一工作区另有 2.9 原生代理开发把 minimumBundleComponents 提高到2.9，首次账号版启动因此隐藏本机2.8核心，VM进程仍运行。没有修改该并行源码；在 .build/DecodoAccount28Source 中制作本机2.8兼容快照（仅快照版本门槛回到2.8，并固定本机fallback路径），输出 .build/LaunchpadAccount28，避免升级或重启现有VM。后续统一2.9部署需按核心版本配套完成。

兼容快照部署后已重新启动管理器，界面恢复显示两台运行实例，再打开独立 Decodo 设置。没有停止 VM 或更换出口。最终凭据仍为空，等待用户在设置中完成真实账号验证。

## 2026-10-22 API Key 与真实账号续期验收

- 从独立项目授权文件读取 Public API Key，通过官方 `https://api.decodo.com` 的 `Authorization` 请求头调用；未把凭据写入研究记录或测试输出。
- 实测 HTTP 200：GET `/v2/subscriptions`、`/v2/sub-users`、`/v2/allocated-traffic-limit`、`/v2/whitelisted-ips`、`/v2/endpoints`、`/v2/endpoints/sticky`；POST `/api/v2/statistics/targets`、`/api/v2/statistics/traffic`（住宅产品、UTC 2026-10-21 至 2026-10-22，traffic 必须传 groupBy，使用 day）。无效 Key 对照请求 `/v2/subscriptions` 返回 401。由此确认真实 Key 有效，非匿名公共响应。
- 未测试创建/删除子用户、修改白名单等写接口；200 只证明这些查询的认证和响应成功，不证明住宅代理有可用余额。
- 官方文档仍明确 Public API 不支持 ISP / datacenter 产品。ISP 地区继续使用 dashboard 授权订阅接口，而不是把住宅 endpoints 列表用于 ISP。来源：https://help.decodo.com/api-reference/public-api-key-authentication ，OpenAPI https://help.decodo.com/api-reference/jero_public_api.yaml 、https://help.decodo.com/api-reference/jero_dash_stats.yaml 。
- 经用户授权把网站登录资料保存到 `~/.vphone/decodo-account.json`，保留 API Key；用户文件优先于项目文件。Launchpad “保存并验证 / 续期”真实登录成功，令牌持久化，返回 52 个 ISP 地区。
- 使用实际 `DecodoAccountSession.swift`、`DecodoAccount.swift`、`DecodoLocations.swift` 编译临时验收入口（`.build/validation/decodo-account/`）。仅在内存副本替换 access token 为无效测试值，并清空邮箱/密码以禁用密码回退；真实 refresh token 成功续期并取得地区列表。以配置快照比对防止覆盖并发修改后，把新令牌写回原用户文件。未伪造服务响应，未记录令牌。
- 续期后统计：21 个国家、4 个州、27 个城市（另有随机选项）。真实 Launchpad 出口页自动同步成功；搜索 New York 显示 New York 州与 New York City (New York) 城市。
- 本轮没有启停 VM、切换出口、下载 IPA 或通过代理加载 App 内容；只请求管理 API。
