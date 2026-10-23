# Instagram App 两机纽约 ISP 分流与换新实测

时间：2026-10-22 15:00–15:09（Asia/Shanghai）。
复用已安装的 Instagram 452.0.1（com.burbn.instagram），没有下载/安装IPA、注册或登录账号，
没有浏览动态/视频内容。使用真实 Launchpad 一键换 IP，未修改业务源码或固件。

## 结果与范围

两机 Instagram 均实际进入登录页面，最终 apps.foreground 验证为 Instagram：
official PID941，custom PID920。结束后 apps.terminate 成功关闭两台 App，保留两台虚拟机运行，
减少后台流量。Launchpad helper=ready(15)，hostReady=true。

Mihomo 捕获到两机的 i.instagram.com、graph.instagram.com、graph.facebook.com、
www.facebook.com、static.xx.fbcdn.net 请求和返回字节。
每个实例的这些连接只命中自己的 IP · ISP 专属节点，没有命中另一台节点或 DIRECT。
这是实际 App 连接证据，不是只用 Mac curl 或 guest IP echo 推断 App 已联网。

| 实例 | 起始 guest IP | 第一次 official 换新后 | 最终 guest IP | 最终端口 |
|---|---|---|---|---:|
| official | 72.245.70.229 | 48.45.93.92 | 48.45.88.221 | 54682 |
| custom | 72.245.66.178 | 72.245.66.178 | 72.245.66.178 | 32361 |

最终 guest probe 时间为 07:08:07Z / 07:08:09Z，均 origin=guest。
official两次换新后均捕获其Instagram新连接通过同一专属节点，并有返回数据。
custom节点、IP和Instagram连接始终独立。切换会断开目标实例旧连接；App重新发起请求后走新出口。

## 城市定位限制

两机保留 country-us-city-new_york_city。
Launchpad 对当前 official 入口查询 Decodo/IPInfo，核对返回IP与guest相同：
48.45.88.221，New York City，ZIP10004。
第三方ipwhois.app对同一IP标为Houston；中间48.45.93.92也标为Houston。
custom 72.245.66.178此前两种查询均为New York City。

因此，本轮通过的是“Instagram实际分流、独立出口、换新后恢复请求”。
不能据此声称Instagram服务端将两个IP都认定为纽约，更不能保证ZIP10001/街道附近。
没有登录账号，也未验证登录后风控/地区显示。前述数据库分歧保留展示，没有隐藏或以主要结果覆盖。

## 启动异常

custom首次被process-launch watchdog在20秒限额后终止，
第二次被scene-create watchdog终止（报告剩余限额2.27秒）。
第三次启动保持前台超过观察窗口并进入登录页，有Instagram网络请求。
未修改watchdog、清理数据或重装App；启动不稳定的根因未修复，不能宣称永久解决。

## 流量与证据

Mihomo轮询样本按processPath/start/host/destinationIP/chain去重并取最大累计字节：
official Instagram/Meta连接538726字节，custom251110字节，合计约0.79MB。
这是捕获到的连接字节，不是供应商账单总量；短连接、代理握手、IP查询及系统流量可能未全计入。
本机证据在gitignored .local/instagram-nyc-20261022：
各阶段connections.json、guest probe JSON、最终前台状态与登录页截图、两份custom崩溃报告、summary.json。
没有记录代理密码或Instagram账号凭据。
