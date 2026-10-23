# IP 供应商比较：短租 ISP 与按量住宅

调研日期 / 下列链接访问日期：**2026-10-21**。范围：IPRoyal、Decodo、Webshare、DataImpulse 的官方公开网页和文档；通过 MCP 搜索、抓取。未注册、登录、下单、获取账户报价或实际连接。金额均为美元 USD；税、汇率、库存和账户限制仍以购买前报价为准。本文件是供应商事实附录，管理与网络集成方案由主调研报告综合。

## 选择建议

- **两台 VM、按天验证固定出口：优先候选 IPRoyal 的独享静态 ISP。** 官方允许 1 IP 起、最短 1 天；独享 ISP 页面公开起价 $1.80/IP/24h。这符合“已购地址池 → 选中一个出口”的产品模型。[最小订单](https://help.iproyal.com/en/articles/7222122-can-i-buy-one-isp-proxy)、[独享 ISP](https://iproyal.com/other-proxies/dedicated-residential-isp-proxies/)。尚无真实账户报价，因此不能把起价承诺成两台 VM 实付 $3.60。
- **月租备选 Decodo Dedicated ISP：** 最小公开套餐 3 IP / $9.99 + VAT / 月；10 IP / $29 + VAT / 月。它明确区分独享和共享，成本可计算，但 Instagram 视频和流媒体限制需要先核对。[ISP 定价](https://decodo.com/proxies/isp-proxies/pricing)、[限制目标](https://help.decodo.com/docs/dedicated-isp-proxy-restricted-targets)。
- **几十分钟至数小时的地区测试：DataImpulse 低价按量住宅可作辅助池。** $1/GB，首购 $5/5GB，之后同类型最低 $50；会话 1–120 分钟，不能当作固定资产池。[价格](https://dataimpulse.com/residential-proxies/)、[最低消费](https://help.dataimpulse.com/en/articles/15930995-minimum-payment-and-plan-sizes-explained)、[会话](https://docs.dataimpulse.com/proxies/types-of-connections)。
- **Webshare 适合需要较多固定 IP 的月租池候选。** 独享静态 ISP 最小公开档 20 IP / $42/月；2 台 VM 起步利用率偏低。$6/月买 20 个静态 ISP 是共享价，不能拿来比较独享。[独享价格](https://www.webshare.io/dedicated-static-residential-proxy)、[共享定义及价格](https://www.webshare.io/pricing)。

以上均为根据产品规格得出的候选排序，不是质量实测，也不承诺 Instagram 登录、视频、账号风控结果。

## 公开价格、最短周期与实际最低开销

| 产品 | 官方公开价格 | 短期 / 最小购买 | 已证实的条件与应确认项 | 官方源（访问 2026-10-21） |
| --- | --- | --- | --- | --- |
| IPRoyal 独享 ISP | 24h 起 $1.80/IP；30 天起 $2.70/IP；60 天起 $2.55/IP；90 天起 $2.40/IP | 1 IP 起；1 / 30 / 60 / 90 天，无公开 7 天套餐 | 都是 Starting from，60/90 天展示单位没有明确写全周期总额，不能按 $2.55 买 60 天推算。地区、数量折扣、税与当前库存需报价。已确认 1 IP 可买，未确认单 IP 在指定地区恰等于最低起价 | [定价](https://iproyal.com/pricing/static-residential-proxies/)、[1 IP FAQ](https://help.iproyal.com/en/articles/7222122-can-i-buy-one-isp-proxy)、[独享页](https://iproyal.com/other-proxies/dedicated-residential-isp-proxies/) |
| IPRoyal 动态住宅 | 1GB 订阅 $7；PAYG $7.35；PAYG 2GB 单价 $6.25、10GB 单价 $5.51 | 1GB 起；无须按天租 IP；流量不过期 | $1.75/GB 是 10TB 订阅档，不适用于两台 VM 小额试验；PAYG 对应 10TB 档是 $1.84/GB | [住宅价格](https://iproyal.com/pricing/residential-proxies/) |
| Decodo Dedicated ISP | 3IP $9.99/月；10IP $29/月；20IP $56/月，均 +VAT | 最小公开完整套餐 3IP/月；未发现独享按天或周套餐 | 独享报价不能与共享 Pay/IP 的 $0.27/IP 广告混用；未登录无法确认是否可订比 3IP 更小的定制档 | [ISP 价格及三类对照](https://decodo.com/proxies/isp-proxies/pricing) |
| Decodo 动态住宅 | PAYG $4/GB +VAT；月订阅最小公开档 3GB / $11.25 +VAT | PAYG 按 1GB 增量，需 Wallet；未使用流量有效 12 个月 | 消耗到 90% 会自动再买 1GB（Wallet 有钱时）；可关闭；不能与活动中的月套餐同时启用，转普通订阅可能改变 PAYG 可用期。钱包首次最低充值金额待账户确认 | [价格](https://decodo.com/proxies/residential-proxies/pricing)、[PAYG 细则](https://help.decodo.com/docs/proxy-pay-as-you-go) |
| Webshare 独享静态 ISP | 最小公开档 20IP / $42/月（$2.10/IP）；50IP / $94.50/月 | 月 / 年订阅；未发现天 / 周租 | 20IP 是公开最低档，不是经账户证实的绝对最小；250GB 起，升无限仍受 FUP；买 2IP 的真实定制报价未获得 | [独享静态 ISP](https://www.webshare.io/dedicated-static-residential-proxy) |
| Webshare 共享静态 ISP | 20IP / $6/月（$0.30/IP） | 月租 | 此项仅作价差说明。Private 仍可能与 1–2 个用户共享；只有 Dedicated 独享 | [总价、共享定义与流量](https://www.webshare.io/pricing) |
| Webshare 共享机房 | 100IP / $2.99/月；免费 10IP / 1GB月流量 | 免费 / 月租 | 很适合低成本验证代理导入链路；不代表住宅身份、独享或社交 App 可用 | [机房价格及免费档](https://www.webshare.io/pricing) |
| DataImpulse 动态住宅 | $1/GB；首购一次 $5/5GB；之后 $50/50GB；1TB $800 | 首购按类型仅一次 $5；后续同类型最低 $50；无月费，流量不过期 | 国家筛选免费；州 / 城市 / ZIP / ASN 精细筛选通常按基础价 2 倍扣量（Premium 例外）；不是租下 5 个固定 IP | [价格](https://dataimpulse.com/residential-proxies/)、[最低付款](https://help.dataimpulse.com/en/articles/15930995-minimum-payment-and-plan-sizes-explained)、[参数说明](https://docs.dataimpulse.com/llms.txt) |

### 两台和十台 VM 成本示例

| 场景 | 可用于比较的公开金额 | 解释 |
| --- | --- | --- |
| 2 个固定 IP，用 24 小时 | IPRoyal 起价下界 $3.60 | 计算为 2×$1.80；不是结算报价。7 天连续每天新购的下界 $25.20，也不保证续买同 IP，不能替代连续租约 |
| 2 个固定 IP，用 30 天 | IPRoyal 起价下界 $5.40；Decodo 完整 3IP 档 $9.99+VAT；Webshare 完整 20IP 档 $42 | 不能按 Decodo $3.33×2 或 Webshare $2.10×2 来声称存在对应可买套餐 |
| 10 个固定 IP，用 30 天 | IPRoyal 起价下界 $27；Decodo 10IP $29+VAT；Webshare 仍为 20IP $42 | 需要在相同地区、独享、流量和续费条件下取实际 quote 后比较 |
| 全部 VM 合计用 5GB，短时动态出口 | DataImpulse 首次 $5，后续需最低 $50；Decodo PAYG 理论流量成本 $20+VAT；IPRoyal 以真实 GB 档计费 | 5GB 是共享总用量，不是每 VM 各 5GB；还要考虑 Wallet 充值下限和自动增购。动态出口不满足长期固定 IP |

IPRoyal 金额依据上一表官方起价；Decodo 与 Webshare 依据公开完整套餐。没有做任何购买。

## API 是否支持购买，而非只有“API Access”

| 供应商 | 本轮确认可做 | 购买 / 续租边界 | 官方源（访问 2026-10-21） |
| --- | --- | --- | --- |
| IPRoyal ISP | `/products` 返回套餐、地区、库存字段与数量折扣；`/orders` 查询、创建；`/orders/calculate-pricing` 报价；`/orders/{id}/extend` 可选择 IP 续租；代理凭据管理 | 官方接口已有创建和续租闭环，可列为优先原生适配候选。URL 带 `/v1/reseller`，不能据此断言普通账号无需开通。权限、支付前提与真实 SKU 须账户验证；示例 `min_quantity:5` 不是实时最低量，不能覆盖 1 IP FAQ | [产品](https://docs.iproyal.com/proxies/isp/api/products)、[订单](https://docs.iproyal.com/proxies/isp/api/orders)、[代理](https://docs.iproyal.com/proxies/isp/api/proxies) |
| Decodo | 代理子用户、额度、流量报告、白名单、endpoint 列表、当前订阅；官方 API index 明确列出 GET subscription | 本轮公开 API 未找到下单或充值端点；先支持官网购买后导入 / 同步，不能写成已确认可自动采购；也不能把 residential 管理 API 泛化为 Dedicated ISP 全生命周期 | [Public API FAQ](https://decodo.com/faq/getting-started/public-api)、[官方 API 索引](https://help.decodo.com/llms.txt) |
| Webshare | 报价、取列表、替换、套餐查询；`POST /api/v2/subscription/checkout/purchase/` | **不是无限制自动付款 API。** 文档明确：需要实际支付时必须走 Dashboard 和 reCAPTCHA，不应程序调用；账户已有足额 credits 才无需付款。默认 replace 可能覆盖旧计划，适配需明确 add / replace，不得静默换套餐 | [报价](https://apidocs.webshare.io/subscription/pricing)、[购买限制](https://apidocs.webshare.io/subscription/purchase_plan) |
| DataImpulse | 普通 User API：代理列表、用量、池可用性；Reseller API：创建子用户、分配 / 扣除余额、用量和凭据 | 子用户 `balance/add` 是给子账户分配已有流量，不等同向供应商付款购买。Reseller API 需要已批准 reseller、KYC、签约。普通购买 / 充值 API 本轮未证实 | [User API](https://help.dataimpulse.com/en/articles/15931700-user-api-usage-stats-ip-info-and-pool-data)、[Reseller API](https://help.dataimpulse.com/en/articles/15931714-reseller-api-managing-sub-users-and-traffic) |

## 固定、粘性与协议能力

| 产品 | 固定性 | HTTP / SOCKS / UDP / IPv6 | 官方源（访问 2026-10-21） |
| --- | --- | --- | --- |
| IPRoyal 独享 ISP | 分配给本账号的静态 IP，续租可按 IP；是否到期宽限保留需报价确认 | HTTP(S)、SOCKS5；ISP 文档明确 TCP+UDP，HTTP 与 SOCKS 端口不同；FAQ 仅 IPv4，不售 IPv6 | [独享产品](https://iproyal.com/other-proxies/dedicated-residential-isp-proxies/)、[协议](https://docs.iproyal.com/proxies/isp/using-proxy-strings)、[IPv4](https://help.iproyal.com/en/articles/7222570-do-you-offer-ipv4-and-ipv6-proxies) |
| IPRoyal 动态住宅 | 旋转 / 粘性 1 秒至 7 天；不是独享永久固定。没有对单个家庭节点持续在线的保证 | HTTP(S)、SOCKS5；不要把 ISP UDP 能力直接推及住宅，住宅 UDP 本轮未确认 | [会话配置](https://help.iproyal.com/en/articles/7214673-how-to-use-residential-proxies)、[共享 / 独享对照](https://help.iproyal.com/en/articles/14653334-dedicated-vs-shared-proxies-which-is-right-for-you) |
| Decodo Dedicated ISP | 本账号独享静态 IP；IP 保留与替换独立管理，须在有效订阅内使用 | HTTP、HTTPS、SOCKS5；专门 ISP 文档明确 SOCKS5 支持 TCP+UDP；ISP IPv6 本轮未确认 | [价格](https://decodo.com/proxies/isp-proxies/pricing)、[ISP 协议](https://help.decodo.com/docs/dedicated-isp-proxy-protocols) |
| Decodo 动态住宅 | 默认 10 分钟，自定义 1–1440 分钟，官方明确家庭设备下线可能提前换 IP | HTTP(S)、SOCKS5；另有 HTTP/3 和 MASQUE UDP 网关，不能假设现有客户端通用 SOCKS 配置即可支持 MASQUE；IPv4/IPv6 池，强制版本参数需申请 | [粘性](https://help.decodo.com/docs/residential-proxy-custom-sticky-sessions)、[协议](https://help.decodo.com/docs/residential-proxy-protocols)、[IP 版本](https://help.decodo.com/docs/residential-proxy-ip-versions) |
| Webshare 静态 ISP | Shared / Private / Dedicated 三种访问等级；静态不等于独享。只给固定 VM 池导入 Dedicated | HTTP、SOCKS5；**不支持 UDP**；全部 IPv4 | [等级](https://www.webshare.io/pricing)、[UDP](https://help.webshare.io/en/articles/8375290-do-you-support-udp-proxy-connections)、[IPv4](https://help.webshare.io/en/articles/8370541-are-your-proxies-ipv6-or-ipv4) |
| DataImpulse 动态住宅 | 端口粘性 1–120 分钟，默认 30 分钟；不是固定 ISP | HTTP(S)、SOCKS5；UDP 默认关闭，提交用途、公司信息（适用时）并 KYC 后个案审核；住宅 IPv6 本轮未找到明确产品承诺，待确认 | [连接](https://docs.dataimpulse.com/proxies/types-of-connections)、[UDP](https://docs.dataimpulse.com/proxies/udp) |

供应商支持 UDP 不等于 VM→宿主→代理全链已支持；还需按实际隧道和客户端进行独立测试。对于不支持 UDP 的候选，不能让未代理 UDP 静默直连并声称整个 App 同一出口。

## Instagram App 与视频使用限制

1. **IPRoyal：** 官方社交 FAQ 明确可用住宅、移动或 ISP 代理，支持选择 ISP 做较长的相同 IP 会话。2026-10-15 更新的条款把未授权登录后采集、违反平台规则的采集列为禁止；这是“采集功能”的边界，不能错误扩展成任何正常授权账号登录均禁止。AUP 禁止虚假社交互动和未授权非公开采集。正常 Instagram App 登录 / Reels 播放的具体域名、带宽和合同适用范围仍需供应商确认并实际验收。[社交 FAQ](https://help.iproyal.com/en/articles/7222586-what-is-a-good-plan-for-social-media-sites-like-instagram-facebook-tiktok-discord-and-others)、[条款](https://iproyal.com/terms-of-service/)、[AUP](https://iproyal.com/acceptable-use-policy/)。
2. **Decodo：** Dedicated ISP 限制列表包含 Entertainment、Apple/Google stores、Streaming 等；星号类别说明仅 Residential 在 ID 验证后可申请开放。因此不能因为首页写 account management 就承诺 Dedicated ISP 能播放所有 Instagram 视频。需购买前核对 `instagram.com`、App API、Meta CDN、视频是否落入 streaming 限制，以及目标端口；普通住宅默认 80/443，其他端口须申请。采集 API / Video Downloader 是另一产品，不能替代整个 App 的通用代理。[Dedicated ISP 限制](https://help.decodo.com/docs/dedicated-isp-proxy-restricted-targets)、[住宅协议及端口](https://help.decodo.com/docs/residential-proxy-protocols)。
3. **Webshare：** 所有套餐均可能有供应商阻断域名，返回 `forbidden_host`；官网没有在本轮公开提供完整可审计 Instagram 白名单。可在买前向官方确认具体域名和用途。TCP 可用不保证 App 中所有 UDP 功能可用。[网站限制](https://help.webshare.io/en/articles/8375298-are-there-any-blocked-websites-from-your-end)、[UDP 限制](https://help.webshare.io/en/articles/8375290-do-you-support-udp-proxy-connections)。
4. **DataImpulse：** 公开阻断列表未明确列 Instagram，但未列出不等于保证许可和完整功能。默认开放端口有 80、443、5228、53、5060 等，绝大多数非标准端口受限；UDP 另需 KYC。按量计费的视频流量应单独预算。[域名限制](https://docs.dataimpulse.com/blocked-websites)、[端口限制](https://help.dataimpulse.com/en/articles/15931291-blocked-websites-and-restricted-resources)、[UDP](https://docs.dataimpulse.com/proxies/udp)。

## 发现的价格 / 规格陷阱及待确认项

- IPRoyal 营销定价写 unlimited bandwidth，而新版 FAQ/FUP 明确 ISP / DC 每 30 天池额度为 **100GB × IP 数**；独享超额降速，共享超额停用。不能把“无限”写成无条件满速无限；额外 100GB/IP 档 $2.50/IP，当前周期到期不结转。[额外流量及 FUP](https://help.iproyal.com/en/articles/13867938-how-to-purchase-additional-data-for-my-isp-or-datacenter-proxies)、[FUP](https://help.iproyal.com/en/articles/12094903-what-is-the-fair-usage-policy)。
- IPRoyal 起价、订阅价、PAYG 价、90 天页面单价混用会导致错误预算；报价 API 返回 `price_with_vat` 等字段，应把 quote 总额及有效期展示给用户，再购买。当前未取得 quote。
- Decodo 官网新文档住宅粘性上限为 24h，而官方 GitHub README 仍写 60 分钟；本报告采用产品帮助文档，并要求连接实测，不按旧 README 选型。[当前会话文档](https://help.decodo.com/docs/residential-proxy-custom-sticky-sessions)、[官方旧 README](https://github.com/Decodo/Decodo/blob/master/README.md)。
- Webshare 低至 $0.23/IP 的宣传是高数量共享 ISP 单价，不是 2 台 VM 的独享总成本；Private 不是 Dedicated。独享页较大数量折扣表存在单价乘数量与总价不一致的行，本报告只采用明确一致的 20IP / $42 与 50IP / $94.50 档，扩容须报价。
- DataImpulse 首页“无每月最低消费”不等于无最低充值；首购一次 $5，后续 $50 是明确规则；普通 API 和 reseller API 不能混用，更不能把子用户余额分配误当采购接口。
- 四家均未在本轮验证：购买后保留某个确切 IP 续租成功、同地区库存、支付方式最低充值、最终含税价、故障退款、Instagram App 完整域名/CDN/UDP/视频和长期 IP 信誉。最低成本验证应先取得具体 SKU quote 与用途确认，然后小额测试；本轮没有购买或联络供应商。
