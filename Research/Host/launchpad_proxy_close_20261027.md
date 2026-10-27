# 代理出口面板明确关闭入口

用户报告代理出口窗口没有基本关闭入口。截图中原入口为底部“完成”，且源码在 controller 或 nativeController busy 时禁用；没有 Esc 取消快捷键，标题区没有关闭动作。

沿用既有 SwiftUI sheet 的 dismiss 与项目其它窗口的 cancelAction 模式，只修改 `VPhoneLaunchpadDecodoView`：将关闭动作移至滚动区域外的右上角标题行，使用“关闭”与 xmark，支持 Esc，并去掉与网络 busy 的绑定。删除底部“完成”，避免重复入口。不改代理、账号、任务执行、Core 或 VM。关闭只退出面板，不作为取消或回滚已发出的网络操作。

源码基于已发布修订 11，尚未发布或安装本改动。此为低影响呈现修正，验证完整 App 编译与代码布局，不为固定按钮位置创建镜像实现的测试；实际用户 UI 关闭操作仍待安装后验收。构建证据在 `.build/proxy-close-evidence/`。
