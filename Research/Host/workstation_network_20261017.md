# 2026-10-17 Workstation 实例上下文与 guest 出口检测验收

## 范围与实现

主仓库 `tb_dev`，在原有 Workstation / native CLI / vphoned 上迭代，未新增 VPN 内核、外部服务适配或二进制固件补丁。接口和使用说明见 [Workstation 网络](../../Documents/Guides/workstation-network.md)。

- `VMCommandContext` 统一绑定宿主、真实目录/名称、library root 与旧 variant。
- 单实例查询/修改、启动、导出均经此上下文；现代分离式运行包通过绑定 CLI 停止，旧版继续使用集中兼容路径。
- 新增只读 `vm network --probe --json` 和 guest `network.egress`，固定 HTTPS 请求从 guest 发起，不在 Mac 代测。
- 网络页区分保存模式、运行模式、地址分配设置、guest 实际 en0 IPv4、公网 IPv4 和检测时间。切换实例或停机清除旧结果，失败不回显上次成功。

## 自动验证

- `scripts/dev.sh test gui`：69 个测试通过。新增覆盖真实目录链接、绑定损坏不回退、旧 CLI 不支持检测、拒绝 host 来源、guest 超时、新版停止走绑定 CLI 并等待磁盘释放。
- `VPhoneDaemon/Tests/run-network-egress-tests.sh`：编译实际生产探测代码，16 个响应解析用例通过（仅替换 daemon 错误类型）。
- `scripts/dev.sh build cli`：完整 Xcode `VPhone.bundle` 构建成功，含原生 CLI 和 iOS vphoned；bundle deep/strict 签名检查通过。
- `scripts/dev.sh build gui`：release app 构建成功。
- 实际 CLI 拒绝 `--probe --link down`，退出 64，未执行网卡变更。
- CodeGraph 已增量同步：856 文件、20,923 节点、53,335 边（本次快照）。

## 运行态验收

两机仍位于 `~/.vphone/machines/{official,custom}-2x-20261016`。两者 runtime 仍使用 `~/.vphone/runtimes/source-4a76ffb-20261016/{official,custom}/VPhone.bundle`，因此不改变现有进程路径分流规则。按原路径部署完整最终 bundle，两份各 61 个文件与构建产物逐一 SHA-256 一致；host preflight 均通过。

| 对象 | guest en0 IPv4 | 最终实际公网 IPv4 | GUI 检测时间（上海） |
| --- | --- | --- | --- |
| official | 192.168.127.3 | 178.249.213.185 | 2026-10-17 11:43:27 |
| custom | 192.168.127.3 | 79.127.245.214 | 2026-10-17 11:44:51 |

custom 本轮还曾返回 `.215`、`.213`，说明节点池会变化，不能以历史 IP 作为固定预期。

实际 GUI 验证：两台启动与同时运行；详情切换不携带另一台结果；Show screen；两台分别点击出口检测；正常单独停止 official 后 custom 仍检测成功；运行中 Export/Save 禁用；停止后 Export 恢复且检测禁用、旧 IP 清除；设置页能显示 Tunnel，取消退出未保存配置。未为验证导出生成整机归档，导出本轮仅验证上下文参数及按钮状态。

对比开始前保存的 15 个文件 SHA-256（两台 config/sidecar 与 Clash YAML），结束时全部未变。未修改实例网络模式、订阅规则或代理节点。没有删除/复制虚拟磁盘，guest 通过现有机制更新 vphoned。

## 失败观察与边界

验收期间 Mac 使用约 32 GiB swap，冷启动和构建明显变慢。观察到 guest 尚未连接以及 HTTPS 请求超时，均显示为失败而非旧 IP。一次 official 冷启动已进入锁屏但控制连接未恢复；正常停机重启后恢复，最终双机检测成功。未确定该次控制连接问题根因，也未将其描述为已修复的网络缺陷。

本轮测试的是 guest vphoned 的 HTTPS 出口，不代表 Instagram 登录、所有 App/DNS/UDP 或断线阻断已通过；没有实现节点切换。旧 CLI/guest 会明确显示不支持或未知方法。本机完整构建也包含任务开始前已有、未在本次代码提交中纳入的启动解锁修改。

原运行包保存在各实例 runtime 目录的 `VPhone-before-network-20261017.bundle`，仅用于回退，未备份整机。任务证据保存在已忽略的 `.build/validation/network-20261017/`；包括配置哈希、两机 JSON、构建/测试与启动日志。完成后正常停止本轮启动的两机和日志采集器，保留 Workstation GUI。
