# Workstation 每实例 Clash 出口：2026-10-17

## 范围与实现

`tb_dev`，复用两台既有 2.x 实例及独立 runtime，未复制镜像或变更 guest/宿主 CLI。GUI 呈现节点选择；`VPhoneWSCore/Proxy` 读取当前订阅、精确替换前置规则标量、调用 Mihomo、验证完整规则序列并只关闭目标进程的旧连接；guest IP 检测仍调用实例绑定的 CLI。当前入口要求已有独立进程路径规则，不自动创建另一套代理管理机制。

新增 Yams 6.1.0（锁定 revision），用于读取 YAML 语义与定位标量。写入保留其它字符，不全量重写 YAML。随 GUI 分发 Yams/libyaml MIT 声明。系统 curl 经 stdin 接收控制密钥和重载 payload，不引入解释器、Homebrew 运行依赖、外部控制端口或 VM 内 VPN。

## 官方实现核对

通过 GitHub MCP 核对已安装版本的官方源码：

- [Clash Verge Rev 2.5.8 seq.rs](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.8/src-tauri/src/enhance/seq.rs)：订阅 rules 的 prepend/append/delete 合成语义。
- [Clash Verge Rev 2.5.8 profiles.rs](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.8/src-tauri/src/config/profiles.rs)：current、option.rules、规则文件绑定。
- [Clash Verge Rev 2.5.8 service.rs](https://github.com/clash-verge-rev/clash-verge-rev/blob/v2.5.8/src-tauri/src/core/service.rs)：服务 staging 与 runtime 生命周期。
- [Mihomo 1.19.32 configs.go](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/hub/route/configs.go)：`PUT /configs` 支持 payload，`force=false`，先解析再应用。

本机使用服务模式，实际 socket 为 `/var/run/clash-verge-service/users/<uid>/verge-mihomo.sock`，生成配置中的用户临时 socket 不存在。优先识别服务 socket，普通模式使用配置 socket。使用 payload 避免服务用户隔离目录对外部配置路径的准入问题。

## 实测中发现并修复

第一次 GUI 写入返回错误并恢复：Swift JSONEncoder 默认把路径斜线编码为 `\/`，Yams 接受但 Mihomo Go YAML 返回 HTTP 400 `found unknown escape character`。改为 `.withoutEscapingSlashes`，并增加回归断言。失败后核对 15 个受保护配置文件 SHA256 均与基线一致。

官方实例开始时尚未完成启动，返回 `guest not connected`。在其启动画面期间不把宿主网卡查询当作 guest 连接成功。正常停止定制实例释放测试资源后，官方实例完成启动并实测 `178.249.213.185`；未修改 guest 数据或网络设置。仅记录观察，不断言资源压力是唯一根因。

## 已取得的验收证据

- 定制实例在 GUI 选择美国 BGP 2 并应用，界面自动检测成功：`79.127.245.216`（UTC 04:01:03）。此前 BGP 1 为 `79.127.245.214`。
- 在 Clash Verge 界面点击“重新激活订阅”，实际重新合成配置；定制仍为美国 BGP 2，官方仍为日本 BGP。
- 重载后规则总数 570；除定制实例目标外，其它规则的内容和顺序完全一致，共享 Selector 选择无变化。
- 重载后定制 guest 再次检测仍为 `79.127.245.216`（UTC 04:02:44）。

本地证据位于忽略目录 `.build/validation/proxy-20261017/`，只保留配置哈希、规则/策略组对比与 guest 测量，不保存控制密钥或订阅凭据。最终双机与交付状态见后续验收补充。

### 双机隔离补充

官方实例完全启动后再由 GUI 启动定制实例，两台同时运行：

- GUI 将官方切至新加坡 BGP，自动 guest 检测 `138.199.25.98`（UTC 04:06:44）；CLI 复查同值（04:08:10）。
- 定制仍保持美国 BGP 2，guest 检测 `79.127.245.216`（04:08:46）。刚启动期间一次 ipify 请求超时，稍后重试成功，失败 JSON 保留，未作为成功计入。
- `/connections` 的真实流量分别命中各自 `ProcessPath` 和对应节点；原两条 DIRECT 例外及其它规则不改。
- GUI 重新启动后仍读取保存的美国 BGP 2。此项连同 Clash 订阅重新激活验证，覆盖 GUI 重启和配置重新生成持久化。

### 最终恢复与交付检查

由 GUI 恢复官方日本 BGP、定制美国 BGP 1；自动检测分别为 `178.249.213.185`（04:09:09）和 `79.127.245.213`（04:09:48）。再次在 Clash Verge 重新激活订阅，双机在 **UTC 04:10:17 同时完成 guest 探测**：

| 实例 | 最终选择 | Guest 公网 IPv4 |
| --- | --- | --- |
| official-2x-20261016 | 日本 BGP | 178.249.213.185 |
| custom-2x-20261016 | 美国 BGP 1 | 79.127.245.214 |

美国节点为动态出口池，恢复前后尾号变化不作为串流证据；验证依据还包括独立进程路径命中和节点链。

最终 `final-preservation.json`：570 条规则与初始基线内容、顺序完全相等，Selector 选择无变化。15 个配置文件中只有当前订阅的 rules YAML 字节变化（两条目标标量由转义折行改为普通双引号字符串，语义恢复原值）；生成配置、其它 9 个 Clash YAML、两台 manifest 与 sidecar 哈希均保持基线值。

最终 GUI release build 成功，75 项 Swift 测试通过；既有 StreamingRunner/TaskModel 编译警告未在本轮扩大处理。验收没有创建镜像副本、修改 guest 固件或替换绑定 CLI。IP 结果是一次 HTTPS 探测，不证明所有 DNS、UDP 或应用出口。未测试宿主重启和订阅远端内容更新；已实测 GUI 重启和 Clash 当前订阅重新生成。

收尾：通过 GUI 正常停止两台测试实例，确认两台 `Disk.img` 均无打开的文件句柄；GUI 保持可用。没有清理用户原有备份或改变其它应用运行状态。
