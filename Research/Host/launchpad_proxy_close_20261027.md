# 代理出口面板明确关闭入口

用户报告代理出口窗口没有基本关闭入口。截图中原入口为底部“完成”，且源码在 controller 或 nativeController busy 时禁用；没有 Esc 取消快捷键，标题区没有关闭动作。

最初增加页内关闭按钮的方案被用户明确否决，未发布。用户要求系统标准标题栏、关闭按钮和可拖动窗口，同时修复小屏显示不全。

最终方案复用现有 SwiftUI Scene：以实例完整 URL 作为 WindowGroup 值，取代 inspector 的 sheet。保留系统 titleBar、红色关闭、拖动、调整大小和菜单默认 ⌘W，不再添加业务关闭／完成按钮。同一路径重复打开聚焦已有窗口，同名不同库按 URL 区分；内容从现有共享 model 获取当前实例及运行状态，实例移除时显示不可用，不改 VM 身份模型。

移除代理 View 固定的 600×650 frame；最小内容区 420×280，可继续放大。使用 macOS 15 起的 defaultWindowPlacement，根据当前 display.visibleRect（已排除菜单栏与 Dock）及标题栏边距设置初始尺寸。状态、进度和说明从 Form 外移入其可滚动状态 Section，避免长提示挤占内容区；原生 HTTPS 分支沿用原 Form 滚动。系统窗口装饰独立于表单 busy 状态。关闭不等于取消或回滚已发出的网络操作。不改代理、账号、任务执行、Core 或 VM。

官方 API 依据：[WindowPlacement](https://developer.apple.com/documentation/swiftui/windowplacement)、[defaultWindowPlacement](https://developer.apple.com/documentation/swiftui/scene/defaultwindowplacement(_:))，同时核对本机 SDK 声明。

源码基于已发布修订 11，尚未发布或安装本改动。验证完整 App 编译与布局接入，不为静态按钮位置创建镜像实现的测试；实际系统按钮、拖动与目标小屏操作仍待安装后验收。构建证据在 `.build/proxy-close-evidence/`。
