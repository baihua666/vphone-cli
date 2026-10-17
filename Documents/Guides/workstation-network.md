# Workstation 网络状态与出口检测

在实例详情中查看“网络状态”。“刷新状态”读取当前 VM 的网卡及 guest 地址，不向公网发起检测；“检测 guest 出口 IP”让虚拟 iPhone 内的 vphoned 向 `https://api.ipify.org?format=json` 发起 HTTPS 请求。

两者都不修改 VM 网络配置或 Clash。停止的实例禁用检测。结果按实例隔离，切换实例、停止或刷新后清除旧结果；公网 IP 显示检测时间，不能视作持续监测。

## 字段含义

- 已保存模式：manifest 中的下次启动设置。
- 运行中模式、链路：当前 VM 网卡状态。
- Guest 地址分配设置：例如 DHCP，不是测量到的地址。
- Guest 实际 IPv4：guest `device.network` 返回的 en0 IPv4。
- 公网 IPv4：guest 发起 HTTPS 后服务观察到的出口；不表示静态、独享 IP，也不证明所有 App、DNS 或 UDP 的出口。

实例设置页按绑定 CLI 的帮助检测 tunnel 支持；已有 tunnel 设置即使旧界面不认识也不应悄悄改为 NAT。修改网络模式仍要求停机并在下次启动生效。

## 命令与兼容性

```sh
vphone-cli vm network NAME --library-root /path/to/library --json
vphone-cli vm network NAME --library-root /path/to/library --json --probe
```

`--probe` 不能与 `--link` 一起使用。JSON 继续保留原有网卡字段，新增可选的 `guest_addresses`、`egress` 和 `egress_error`。网卡查询成功而出口失败时仍返回网卡 JSON（退出 0），调用方必须检查 `egress_error`，不能只看退出码；实例未运行/控制连接失败时退出非零。

成功的 `egress` 包含 `ip`、`origin: guest`、`source` 和 UTC `checked_at`。guest API 增加 `network.egress` 方法及 `network_egress` capability。检测固定使用 HTTPS 和系统证书校验，15 秒资源超时；不接受任意 URL，不通过宿主请求兜底。

旧 CLI 没有 `--probe` 时，Workstation 保留网卡查询并提示更新完整运行包；新 CLI 配旧 guest 时显示 guest 的未知方法/未连接错误。此扩展不改变 Launchpad 已依赖的既有参数和字段。

## 实例上下文

`VMCommandContext` 统一解析真实机器目录、真实名称、library root、sidecar 绑定的 CLI 和旧版 variant。启动、info、config、network、clone、rename、delete、export 使用该上下文；列表由默认 CLI 发现，再由绑定 CLI 读取对应实例详情。

新版分离式运行包（存在可执行 `vphone-vm`）通过绑定 CLI 停止，并等待磁盘释放；旧版保留按真实 config 找 AppKit 宿主的兼容停止路径。窗口激活属于 macOS UI，继续按真实 config 定位窗口。

损坏的 sidecar 报错，不静默回退。链接实例的查询、启动、停止、配置和导出解析到真实目录；clone/rename/delete 拒绝对库别名操作并提示真实库，避免创建对象不可见或留下悬空链接。新建/导入属于库级操作，仍用默认 CLI；旧创建向导的 2.x 迁移不在本次范围。

## 开发验证

```sh
scripts/dev.sh test gui
VPhoneDaemon/Tests/run-network-egress-tests.sh
scripts/dev.sh build cli
scripts/dev.sh build gui
```

GUI 测试覆盖绑定宿主与链接目录、损坏绑定、旧 CLI、guest 错误及拒绝 host 来源结果。guest 测试编译实际探测代码并验证返回地址解析。真实验收还需两台 VM 同时运行、分别检测、单独停止和切换实例，确认结果隔离及既有分流配置不变。
