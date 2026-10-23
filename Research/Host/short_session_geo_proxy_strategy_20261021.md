# 按位置选择、约五分钟使用一次的住宅代理策略

更新：2026-10-21。依据用户本轮澄清：5 台 VM；美国指定地址附近，越精确越好；每次约 5 分钟，随后用户主动换 IP；不主动复用，偶尔随机重复可接受。预算未设定。本报告替代上一版“日租/月租独享静态 ISP 优先”的推荐；调研后已完成 Decodo 最小接入的代码与界面；没有购买、账户注册、供应商连通测试或运行配置修改。

## 1. 推荐结论

**首期默认评估 Decodo 动态住宅 PAYG，以美国 ZIP 邮编选位置、每次独立 session，保留手动“换新 IP”。Oxylabs 是需要地址坐标＋半径控制时的重点对照；DataImpulse 是降低流量成本的对照。** 这个排序是依据功能适配、公开价格与接入复杂度的工程判断，不是 Instagram 实测质量排名。

购买的是住宅代理池的流量额度，不再逐个购买只使用五分钟的固定地址。5 台 VM 各持一个独立短会话，任务内尽量保持出口，下一次任务生成新 session；不使用每个 HTTP 请求都轮换的模式。随机分配可能回到旧 IP，符合用户最新容忍范围，因此不建立永久去重库，也不承诺 IP 从未被其他客户使用。

## 2. 位置精度的真实边界

| 选位方式 | 可以表达什么 | 无法据此保证什么 |
| --- | --- | --- |
| 国家/州/城市 | 城市级区域测试 | 靠近某条街道 |
| 美国 5 位 ZIP | 供应商数据库认定的邮编区域 | 邮编中心周边固定半径；ZIP 大小不恒定 |
| 经纬度＋半径 | 按数据库位置筛选某个圆形范围 | 出口设备的 GPS 位置或目标平台使用同一数据库 |
| GeoHash 网格 | 固定精度级别的矩形区域 | 门牌地址；也不等价于圆形半径 |

IP 地理位置不是 GPS。MaxMind 明确说明它用于区域定位，不能据此识别具体家庭或街道地址；应连同 accuracy radius 理解经纬度结果。[MaxMind 定位精度说明](https://www.maxmind.com/en/geoip/ip-geolocation-accuracy)

Oxylabs 当前住宅文档支持 `X-Oxylabs-Geolocation` 代理请求头，值为经纬度和英里半径，**最小 10 英里，约 16.1 公里**；该范围没有出口时返回 502。也支持美国 ZIP。其位置映射使用 MaxMind，并提示其它数据库可能不同。因此不能说“坐标功能必然比 ZIP 更精确”：城市中的 ZIP 可能更小，郊区 ZIP 也可能很大。[Oxylabs 位置参数](https://developers.oxylabs.io/products/proxies/residential-proxies/location-settings#coordinates)

第一版建议先让用户输入 ZIP；展示供应商定位与检测结果。如果地址坐标筛选成为必要功能，再加入地址转坐标和半径选项。地址本身不直接交给社交 App，也不因为换 IP 就改变 iPhone 的系统定位权限或 GPS。

## 3. 供应商与价格

美元公开价，税费、账户权限、支付门槛和实际可售地区以结算为准。这里比较动态住宅产品，不能套用上一报告的独享 ISP 单 IP 价格。

| 平台 | 本需求适配 | 小量价格及门槛 | 判断 |
| --- | --- | --- | --- |
| **Decodo Residential** | 美国 ZIP；位置筛选不加价；可设 5 分钟 sticky session；支持 IP Lock 掉线时报错而非悄换 | PAYG **$4/GB＋VAT**，按 1GB 增购；月包 3GB/$11.25、10GB/$35＋VAT | **综合首选候选**：低试点门槛、地区和会话参数齐全 |
| **Oxylabs Residential** | 美国 ZIP；坐标＋最小 10 英里半径；支持严格单出口会话，出口掉线时报错而非换 IP | 当前 Starter **$30/月**，住宅 $6/GB，对应最多 5GB；有 $5 welcome credits，资格以账户为准 | **位置控制及会话控制优先的对照**；需要 HTTP 代理自定义头支持 |
| **DataImpulse Residential** | ZIP/州/城市；sticky 1–120 分钟，可配置 5 分钟 | 标价 $1/GB，但 ZIP 等精细筛选 **双倍扣量，等效 $2/实际GB**；首购 $5/5GB 标称额度，ZIP 下约 2.5GB 实际流量；之后同类型最低 $50 | **低价对照**；要实测精细区域库存与任务完成率，不能直接按 $1/GB 预算 |
| **Bright Data Residential** | 美国 ZIP、会话控制 | 当前 PAYG 促销 $4/GB（页面原价 $8/GB，优惠码 RESIGB50） | 有完整产品与接入体系，但本次未发现比上述方案更合适的价格/位置组合；价格不可当长期承诺 |

来源：[Decodo 定价](https://decodo.com/proxies/residential-proxies/pricing)、[Decodo PAYG](https://help.decodo.com/docs/proxy-pay-as-you-go)、[Oxylabs 定价](https://oxylabs.io/pricing/residential-proxy-pool)、[Oxylabs 会话控制](https://developers.oxylabs.io/products/proxies/residential-proxies/session-control)、[DataImpulse 精细筛选计费](https://docs.dataimpulse.com/proxies/targeting/target-filters)、[DataImpulse 最低购买](https://help.dataimpulse.com/en/articles/15930995-minimum-payment-and-plan-sizes-explained)、[DataImpulse 会话间隔](https://docs.dataimpulse.com/proxies/parameters/session-interval)、[Bright Data 定价](https://brightdata.com/pricing/proxy-network/residential-proxies)、[Bright Data 位置能力](https://docs.brightdata.com/products/residential/introduction)。

IPRoyal、SOAX 进一步核验见[供应商附录](../residential_short_session_suppliers_20261021.md)。IPRoyal 本次官方文档只证实城市等筛选，未证实 ZIP/坐标入口；其 IP Skipping 排除已用地址的能力已非必要需求。SOAX 当前 ZIP 定位有高套餐门槛，不适合以五台 VM、小额试点作为初始默认方案。

Decodo PAYG 通过钱包购买，流量消耗到 90% 时可从钱包自动购买下一 GB。试点应明确关闭不需要的自动增购；关闭后已购流量按文档可保留 12 个月，或直到购买常规住宅订阅。钱包最低充值额本轮未证实，不能承诺首次现金付款恰为 $4；也不要将 1GB 单位价误解为无限按分结算。[官方说明](https://help.decodo.com/docs/proxy-pay-as-you-go)

## 4. 如何判断成熟与稳定

官方文档、错误码、状态页、会话控制和支持渠道能反映可集成程度，不能证明某个美国邮编在指定时间一定有五个稳定出口。网站的“99.9% 成功率”不等于当前 Mac 到 Instagram 原生 App 的五分钟完成率；全球池大小也不等于单 ZIP 的实时库存。

截至本次访问，Decodo 状态页显示住宅代理正常，另有美国 **ISP** 部分故障；这两类产品不能混为一谈。Oxylabs 状态页显示系统正常，并按住宅入口区域列出组件。这里是状态快照，不用它推断谁长期最稳定。[Decodo 状态](https://status.decodo.com/)、[Oxylabs 状态](https://uptime.oxylabs.io/)

建议用相同目标 ZIP、相同任务先对照 Decodo 与 DataImpulse；需要坐标半径时再加 Oxylabs。每个候选先跑 20 个五分钟任务，分布在至少两个时段，记录：位置命中率、拿到出口的时间、五分钟内出口改变次数、图片/视频成功情况、失败原因和账单实际流量。最终以 **实际花费 / 成功完成且位置合格的任务数** 排序。这是待执行试点，不是已经完成的测量。

供应商有域名、端口或身份验证限制。Oxylabs 定价页列出 Apple、流媒体等受限类别；Decodo 的住宅权限需按住宅文档核对，不能套用独享 ISP 的解封规则。Instagram 页面能打开不代表其媒体 CDN、登录、消息或所有 VM 系统服务全部可用。[Oxylabs 限制说明](https://oxylabs.io/pricing/residential-proxy-pool)

## 5. 五台虚拟机的成本模型

费用主要由五分钟内的实际流量决定，换 IP 的次数不是这些方案的主要计费单位。计算式：`总GB = VM数 × 每台任务次数 × 单任务实际MB / 1000`。下面均为示例，未含重试、探测和协议开销；不是已测 Instagram 用量。

| 每台每次五分钟流量 | 五台完成一轮合计 | DataImpulse ZIP $2/GB | Decodo PAYG $4/GB | Oxylabs Starter $6/GB 折算 |
| --- | --- | --- | --- | --- |
| 10MB | 0.05GB | $0.10 | $0.20 | $0.30 |
| 50MB | 0.25GB | $0.50 | $1.00 | $1.50 |
| 200MB | 1GB | $2.00 | $4.00 | $6.00 |

上表是消耗价值，不是最低付款；特别是 Oxylabs 有 $30/月订阅门槛，DataImpulse 首次之后有 $50 充值门槛。若五台连续跑一小时，每五分钟一轮，共 60 个任务；按 50MB/任务示例是 3GB，分别约 $6/$12/$18 消耗价值。大量视频会显著放大费用；月成本需要实际每天任务数和测量流量后再算。大流量时重新比较对应套餐，不把入门费率当最优大额报价。

## 6. 最小产品闭环如何调整

已在手动 HTTP/SOCKS5 录入与实例分流基础上实现 Decodo：美国 ZIP 输入、每 VM 独立五分钟 IP Lock 会话、手动换新 IP、同一专属节点更新及 guest 出口检测。代码和 GUI 构建可用；用户暂无账号，因此尚未实网验收或改变当前运行配置。操作和边界见[Workstation 网络指南](../../Documents/Guides/workstation-network.md#decodo-美国-zip-与五分钟会话)。

当前实现：认证保存在现有私有 Clash 代理扩展中，每台 VM 维护一个当前会话。界面显示 ZIP、会话 ID 和 guest 实测公网 IP，不显示虚构的供应商会话开始时间；不同 VM 使用不同 session。无需购买或积累成千上万个静态节点，无需永久历史排除库，也无需在虚拟机安装 VPN。

实网试点待验证流程（当前未接入地理位置数据库）：

1. 用户选择目标 ZIP；无库存就明确失败，不能无提示放宽到整个美国。
2. 点击“获取新 IP”，为目标 VM 生成新 session；请求代理后检测实际出口与位置。
3. 应用到该 VM 的现有分流路径，关闭该 VM 旧连接，再由 guest 验证出口；新地址与前一地址相同可提示再换一次，但不承诺永久不重复。
4. 用户完成约五分钟任务后再次点击换新 IP。优先按任务边界换；如果设定严格五分钟截止，需要管理器主动关闭旧连接，因为供应商 TTL 不保证已建立的长连接在第 300 秒立即断开。
5. 普通 sticky 会话的家庭出口离线时可能提前更换。若业务要求五分钟内绝不换，需采用供应商严格绑定能力并在掉线时报错；“设为五分钟”本身不保证完整持有五分钟。

Decodo 的 `session_iplock` 配合 `sessionduration-5` 可在出口离线时返回 502，避免任务中途静默换 IP；每轮改为新的会话名称。此能力需用户名/密码认证。普通 `session` 则可能在家庭出口下线时自动换 IP；两种模式都不承诺任务间永久不重复。[Decodo IP Lock 与时长](https://help.decodo.com/docs/residential-proxy-custom-sticky-sessions)、[ZIP 与高级参数](https://help.decodo.com/docs/residential-proxy-advanced-parameters)

Oxylabs `sessid_oneip` 提供严格单出口绑定，出口掉线报 502；普通 `sessid` 可自动换出口。精确坐标头需要走 HTTP CONNECT 路径，不能直接给 SOCKS5 加 HTTP 请求头。当前 Mihomo 1.19.32 的 HTTP 节点支持 `headers` 并在 CONNECT 时发送，技术上可在 Mac 适配，无需改 App；现有手动录入表单尚未暴露该字段。[Oxylabs 会话契约](https://developers.oxylabs.io/products/proxies/residential-proxies/session-control#single-ip-session-binding-sessid_oneip)、[Mihomo 固定版本 HTTP 实现](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/http.go)

UDP/QUIC 需要按各家的具体产品和网关验证；HTTP CONNECT 不覆盖它们，SOCKS5 支持也不能直接推出所有供应商入口都开放 UDP。既有五机 runtime 路径隔离条件仍成立，位置参数不能代替实例隔离。当前仍没有采购、真实代理测试或 Instagram App 验收。
