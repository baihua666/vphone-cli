# 动态住宅供应商：美国精细位置、五分钟会话、五台 VM

调研 / 全部下列官方来源访问日期：**2026-10-21**。用户最新要求：美国指定地址附近，位置越精确越好；每个 IP 约用五分钟后主动换新；五台 VM；不主动复用旧会话，允许偶尔随机重复，不要求永久去重；重视性价比和成熟稳定。本附录只研究 Decodo、IPRoyal、SOAX，不购买、不注册、不改运行配置；规格是官方声明，**没有真实出口或 Instagram App 实测**。价格 USD，税另按结算。

## 当前选择

**三家之中优先小量测试 Decodo 动态住宅的美国 ZIP 筛选。** 它明确支持美国五位邮编，位置筛选包含在住宅价内；PAYG $4/GB，普通月订阅可从 3GB / $11.25 起。每台 VM 使用独立 session ID，`sessionduration-5`；任务结束更换全新 session ID，而不是复用旧 ID 等待过期。[当前价格](https://decodo.com/proxies/residential-proxies/pricing)、[参数与美国 ZIP 示例](https://help.decodo.com/docs/residential-proxy-advanced-parameters)。

**IPRoyal 可作为城市级备选，SOAX 城市级能力完整，但在小量 ZIP 场景不优先。** IPRoyal 位置文档只证实 region / country / state / city / ISP，未确认 ZIP 或经纬度半径；SOAX 通用文档虽列 ZIP 参数，当前定价表将 ZIP / ASN 放在 Scale（$1,500/月）及以上，不能拿 Sandbox 的 $5/GB 声称已包含 ZIP。[IPRoyal 位置](https://docs.iproyal.com/proxies/residential/proxy/location)、[SOAX 定价权限](https://soax.com/pricing)、[SOAX 参数](https://developers.soax.com/proxies/residential)。

此排序基于公开功能与小量门槛，不代表已验证哪家 Instagram 成功率最高。所有供应商宣传的全网成功率、延时和总池规模都不能推导指定美国邮编内五路并发的稳定性。

## 位置精度：供应商真正允许指定什么

| 供应商 | 官方证实的筛选 | 从街道地址如何使用（方案推断） | 精度、库存与加价边界 | 官方依据（2026-10-21） |
| --- | --- | --- | --- | --- |
| Decodo 动态住宅 | country、US state、city；**USA-only 五位 ZIP**；新增 geohash level 1–4 | 先取目标地址的 ZIP；以 `country-us-zip-10001` 一类参数请求；ZIP 缺货时展示不可用，用户选择扩大到城市 | 官方价格写 advanced targeting 免费。Geohash 最细 level 4 约 **39.1×19.5km 的网格**，不是自选坐标半径，也不能与 country / city / ZIP 等位置条件组合；文档未给邮编覆盖率和按地址距离 SLA | [高级参数](https://help.decodo.com/docs/residential-proxy-advanced-parameters)、[价格](https://decodo.com/proxies/residential-proxies/pricing) |
| IPRoyal 动态住宅 | region、country、state、city、ISP | 将地址映射到城市 / 州，再选择 city；若用户要求具体邮编以内，当前公开证据不足 | 不能将官网对竞品的 ZIP 描述误当自己支持 ZIP；未找到经纬度、半径参数。地理筛选公开价格没有列单独 surcharge；具体城市 / high-end 条件需账户确认 | [位置参数](https://docs.iproyal.com/proxies/residential/proxy/location)、[快启](https://iproyal.com/quick-start-guides/residential-proxies/) |
| SOAX 动态住宅 | country、region、city、ISP；文档另列 asn、zip | 城市任务可选 `country-us-city-...`；ZIP 必须先确认所选套餐具备权限 | 定价表 Sandbox / Builder / Team 为 Country, Region, City, ISP；Scale 加 ASN、ZIP。当前公开 Scale $1,500/月，故“有 ZIP 参数”不等于低价套餐可用。未找到经纬度 / 半径筛选 | [产品参数](https://developers.soax.com/proxies/residential)、[套餐权限和费用](https://soax.com/pricing) |

IP 地理位置是数据库归属，不是设备 GPS 或街道地址保证。Decodo 明确住宅按 MaxMind 判断位置，其他服务或社交平台可能显示不同结果。选中 ZIP 仍需用实际出口做位置检查，不能承诺“该 IP 的家庭设备就在目标建筑附近”。[位置差异说明](https://help.decodo.com/docs/ip-location-does-not-match)。

## 五分钟固定、任务结束换新

| 供应商 | 官方会话控制 | 对五台 VM 的最简单用法（方案） | 已知边界 | 官方依据（2026-10-21） |
| --- | --- | --- | --- | --- |
| Decodo | `session` + `sessionduration`，1–1440 分钟；`session_iplock` 在节点离线时返回 **502**、不自动换 IP | 每 VM 每任务新随机 ID；设 5 分钟，任务结束换 ID 并重建代理连接；需要严格单会话稳定时用 `session_iplock-<新ID>-sessionduration-5`，用户名密码认证 | SOCKS5 普通粘性必须有 `session`，只有 `sessionduration` 仍会旋转；住宅节点下线可能早于 5 分钟，iplock 可选择失败而非悄换；未找到跨会话永不重复承诺 | [高级参数](https://help.decodo.com/docs/residential-proxy-advanced-parameters)、[粘性、IP Lock 与502](https://help.decodo.com/docs/residential-proxy-custom-sticky-sessions)、[SOCKS5 细节](https://help.decodo.com/docs/residential-proxy-protocols) |
| IPRoyal | `_session-` 要求 8 位随机字母数字；`_lifetime-5m` 在 1 秒–7 天合法范围内；省略 session 为随机轮换 | 为每任务生成新的 8 位 session，将地区和 5m TTL 放在代理认证字符串；下一任务换 ID | TTL 是会话配置，不代表永久拥有一个 IP。重复抽中某 IP 没有被公开排除，符合用户容忍偶发重复的要求 | [rotation](https://docs.iproyal.com/proxies/residential/proxy/rotation) |
| SOAX | `session` 绑定节点；`rotate-timed_300` 或 `rotate-timed_5m`；定时范围 10 秒–1 周；`onerror-fail` / `bind-node` 可控制失败 | 每任务新 session；同一任务按需保持 session，结束主动换 ID；若用 timed rotation，300 秒后的新请求换节点 | **60 秒无请求会话即过期**；定时不会中断已在运行的请求；`bind-node` 会忽略定时轮换。故不能同时要求绑定锁定又依赖 timed 自动轮换 | [完整会话与轮换规则](https://developers.soax.com/proxies/residential) |

上述均通过供应商网关的会话参数触发，不需要每五分钟购买一个静态 IP。更换 session ID 表示发起新分配，**不能保证下一次随机抽到的公网 IP 与历史绝不相同**；用户已接受这一边界。没有必要实现无限历史排除池。

### “5 分钟”应由任务完成控制

工程建议：在切换前停止新业务请求，关闭旧代理连接和 App 相关旧长连接，再更新 VM 对应的宿主出站 session，探测新出口后开始下个任务；不能只改凭据但让旧 TCP / QUIC 连接一直活着。供应商的时钟轮换只决定新连接 / 请求如何选节点，SOAX 对不打断运行中的请求有明确说明。[SOAX 轮换说明](https://developers.soax.com/proxies/residential)。这里是接入设计建议，本轮未实现。

如果以后真的要求严格不重复，IPRoyal 有 `_skipipslist-<ULID>` 和 IP/CIDR 清单 API，但需支持开通，清单容量、传播时延和精确地理池耗尽行为未核实；当前需求不启用此复杂度。[Skipping 参数](https://docs.iproyal.com/proxies/residential/proxy/ip-skipping)、[Skipping API](https://docs.iproyal.com/proxies/residential/api/ip-skipping)。

## 小量价格、最低付费与流量寿命

| 供应商 | 当前可核公开小量价格 | 首付、有效期、地理费用 | 需注意的差异 | 官方依据（2026-10-21） |
| --- | --- | --- | --- | --- |
| Decodo | PAYG **$4/GB +VAT**；月订阅 3GB **$11.25**、10GB **$35** +VAT | PAYG 每次增量 1GB，仅 Wallet；**钱包最低充值金额本轮未找到公开数值**，故不承诺首次现金付款恰为 $4。PAYG 流量有效 12 个月；住宅高级地理筛选包含在价格内 | PAYG 用到 90% 且 Wallet 有钱，会再买 1GB；可关闭自动增购。PAYG 与活动月订阅不能同时启用；转普通订阅会影响可用期限 | [定价](https://decodo.com/proxies/residential-proxies/pricing)、[PAYG](https://help.decodo.com/docs/proxy-pay-as-you-go)、[Wallet](https://help.decodo.com/docs/wallet) |
| IPRoyal | PAYG 1GB **$7.35**；2GB **$12.50**；10GB **$55.10**。订阅对应 1GB $7、2GB $11.90、10GB $52.50 | 1GB 档可小量购，住宅流量不过期。当前地理文档支持城市但未证 ZIP；高端池仅活动订阅可启用，不能将普通 PAYG 等同最优节点池 | $1.75/GB 为 10TB 订阅级，不能用于五台小流量预算。只要城市够用，它的接口与会话功能可用，但这一轮比 Decodo PAYG 贵 | [定价与不过期](https://iproyal.com/pricing/residential-proxies/)、[高端池条件](https://iproyal.com/quick-start-guides/residential-proxies/) |
| SOAX | 美国属 Tier 1：Sandbox **$5/GB**；Builder $200/月、美国 $3/GB；Team $500/月、$2.20/GB；Scale $1,500/月、$1.50/GB | Sandbox 无套餐费、不赠流量，须买 credits；**最低 top-up 未公开确认**；Sandbox / 月套餐 credits 60 天过期；ZIP 需 Scale 权限，不是简单按 GB 加一点价 | 新价为按国家分 Tier、统一 credits，不能沿用旧 $90/25GB 或 $1.99 试用宣传。Sandbox 两个 package 是两组凭据 / 规则容器，不等于只能两台 VM；会话与 VM 数应另核并发 | [当前价与 ZIP 权限](https://soax.com/pricing)、[credits 和有效期](https://developers.soax.com/dashboard/account-billing)、[package 定义](https://developers.soax.com/getting-started/core-concepts) |

SOAX 官网价页和 billing 文档对部分 Enterprise 最低单价存在不同数字；本附录不使用该大客户单价。采用公开价页的美国 Sandbox / Builder / Team / Scale 档。购买前以 checkout 实际权限和总额复核。

### 五台 VM 的预算算法

五台同时连续工作，每五分钟一个任务，合计 **60 个会话/小时**（5×60÷5）；按 IP 次数本身不会增加每 IP 月租，成本取决于总上传 + 下载量、失败重试、出口地理筛选和套餐。

以下只是示例假设，未测 Instagram 实际用量：每任务总计 10 / 50 / 100MB，则每小时总流量约 **0.6 / 3 / 6GB**（按十进制 GB）。Decodo PAYG 基础费用相应 **$2.40 / $12 / $24 每小时**，尚未考虑充值粒度、税和重复探测流量。SOAX 美国 Sandbox 的城市级基础成本相应 $3 / $15 / $30；其 ZIP 不能沿用这组单价权限。视频 / App 更新可能显著改变每五分钟的流量，必须实际测量后定预算。[Decodo 单价](https://decodo.com/proxies/residential-proxies/pricing)、[SOAX 计量为双向、含重试](https://soax.com/pricing)。

## Instagram 原生 App、UDP 与网站许可

| 供应商 | 已证实的通用代理能力 | 原生 Instagram 应在试用前确认 | 官方依据（2026-10-21） |
| --- | --- | --- | --- |
| Decodo 住宅 | HTTP、HTTPS、SOCKS5；HTTP/3 使用 **socks5-gate.decodo.com:10000**，另有 MASQUE **masque-gate.decodo.com:42000** 携带 UDP，普通 HTTP 不等于可转 UDP | 默认目标端口 80/443；其他端口申请。Streaming / business 等类别可能需 ID 验证解锁；不能因“住宅代理支持社交”就承诺 Instagram CDN / 视频一定可用。单 session 跨 TCP 和专用 UDP 网关是否同一出口需实测确认 | [协议 / UDP / 端口](https://help.decodo.com/docs/residential-proxy-protocols)、[限制目标](https://help.decodo.com/docs/residential-proxy-restricted-targets) |
| IPRoyal 住宅 | HTTP(S)、SOCKS5；住宅专页明确 **TCP**，不能复制其 ISP 支持 UDP 的结论 | 官方 FAQ 推荐住宅 / 移动 / ISP 可用于社交；但视频通话 / UDP 需求须另核，不能让 UDP 从宿主本地直连补漏；最新条款禁止未授权非公开采集和虚假互动，不能把通用代理当成采集 API 授权 | [住宅协议](https://docs.iproyal.com/proxies/residential/proxy/protocols)、[社交 FAQ](https://help.iproyal.com/en/articles/7222586-what-is-a-good-plan-for-social-media-sites-like-instagram-facebook-tiktok-discord-and-others)、[AUP](https://iproyal.com/acceptable-use-policy/) |
| SOAX 住宅 | 官方限制页明确 SOCKS5 可 UDP；HTTP 接口不支持 UDP；默认开放 TCP 80/443/5222–5223/5228 等，UDP 443、3478–3479 等 | 默认域名封锁列表非完整清单；没有出现在例子里不代表可访问。具体 Instagram API、Meta CDN、登录、Reels、通话功能及套餐权限定价需要确认；不将网页采集 API 等同 App 全流量出口 | [目标与端口](https://developers.soax.com/trust/access-restrictions) |

SOAX 新条款 11.3(b) 对收集节点 IP、ASN、地理属性等有宽泛限制，除非书面授权；其自带 IP checker 与诊断文档又公开提供查询能力。接入若保存出口检测 / 质量记录，应先明确其允许的常规诊断范围，不据此自行推定可以采集完整节点库。本需求不做永久去重，减少了这一依赖，但仍需验收出口。[条款](https://soax.com/legal/terms-of-use)。

## 最小验收与尚未确定

以下为采购前后建议流程，不是本轮完成的测试：

1. 用用户真实美国地址取得 ZIP；向候选确认该 ZIP 当前住宅供给与五路并发、是否允许原生 Instagram 登录与视频。
2. 小量购买前核对 Wallet / top-up 最低额、最终税额、streaming 解锁和退款条件；优先测试 Decodo ZIP；对更具体坐标半径需求由主报告比较其他供应商。
3. 每 VM 新建五分钟 session，核对真实公网 IP、国家 / 邮编数据库归属和三分钟 / 五分钟内是否稳定；30–60 个连续短会话统计失败、提前换 IP、重复率与总 GB。
4. 只在任务边界换新 session，明确关闭旧连接；若位置无可用节点，显示缺货或让用户明确扩大位置，不能静默全美国兜底。
5. 浏览器查 IP 只能证明探测链路；还需原生 App 实际域名流量归属、UDP / DNS / IPv6 是否绕出、节点断开是否停止流量。五台 VM 不应共用同一个粘性 session ID。

未确认：真实目标 ZIP 库存、指定地址距离、五路可重复运行稳定性、真实 Instagram 流量/视频、付费账号域名许可、Decodo Wallet 最低充值、SOAX 最低 top-up 和 ZIP 的最终账户授权。没有任何官方证据可以把这三家的营销总池规模当作一个邮编的可用池规模。
