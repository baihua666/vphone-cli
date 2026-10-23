# FLYWHEEL 本地设备业务库

macOS 15+、Swift 6；仅依赖 Foundation、Observation 和 Apple SwiftData。业务验证与持久化可以脱离 Launchpad 独立构建、测试。

```sh
swift test --package-path Integrations/Flywheel
```

从 vphone 仓库根运行。主要测试使用临时磁盘数据库，覆盖重开后的 CRUD、编号唯一性、同名实例隔离、关联变化、无效输入及损坏数据库，不使用正式业务存储。

- `VPhoneFlywheelDeviceStore` 是唯一写入入口；表单只编辑值，校验通过后显式保存，保存失败回滚。
- `VPhoneFlywheelDeviceRecord` 是内部 SwiftData 模型，不向界面暴露可变持久化对象。
- `VPhoneFlywheelMachineReference` 仅保存平台定位信息、UDID 与本机目录身份核对值；不能执行虚拟机操作。
- 数据默认位于 `~/Library/Application Support/vphone-launchpad/Flywheel/devices.store`，关闭 CloudKit 同步。测试通过显式 URL 使用独立数据库。
- 不导入 SwiftUI、Launchpad、VPhoneWSCore 或 VM/guest 模块，不启动进程、不访问远端业务服务，也不读写虚拟机配置。
- `VPhoneFlywheelWebPage` 保存业务网页规则：校验 URL 与 DECODO 路径、读取新鲜 guest 出口、按勾选状态附加或移除 `ip` 参数、指定 Safari。所有操作由宿主闭包提供；URL 与参数选择使用独立的 `flywheel.businessWebURL` / `flywheel.businessWebIncludeIP` 偏好键，不更改业务数据库模型。
- `VPhoneFlywheelURLParameter` / `VPhoneFlywheelURLParameterStore` 管理自定义参数行与自动保存，独立使用 `flywheel.businessWebParameters` 偏好。勾选、名称、值、行顺序与 UUID 均持久化，支持重复名称和空值；`ip` 保留自动填充，不能被自定义参数覆盖。
- `VPhoneFlywheelNetworkPreparation` 编排业务网络准备：必要时正常停机、配置 tunnel、启动、接入 DECODO，再验证 guest 出口。失败停止后续步骤，既有实例与业务记录保留；通过宿主注入已有操作，不复制 VM 或供应商实现。

界面与宿主适配位于 `VPhoneLaunchpad/VPhoneLaunchpad/Flywheel/`。具体合同、上游改动面和数据备份说明见 [接入指南](../../Documents/Guides/flywheel-integration.md)。
