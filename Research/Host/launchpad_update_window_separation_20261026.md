# App 更新与开始使用分离

用户明确要求两个独立功能。当前改动仅位于 Launchpad，基于已发布 r8 的源码；未获新发行确认，产物为测试构建，不替换 /Applications 的已安装 App。

- 菜单「检查 App 更新…」打开 app-update 单例窗口；只处理 App 版本、下载、安装和错误。VPhoneLaunchpadAppUpdateModel 独立保存检查任务/结果，不读本地镜像目录或刷新开始使用状态。
- 开始使用沿用 distribution 窗口与四步准备流程，去除 App 更新区块、版本修订展示及更新按钮；其目录动作明确命名「刷新 Core 目录」。
- 保留已有签名校验、原子替换、回退与重新打开实现。安装交接前额外核对开始使用没有在忙，避免 App 重启打断权限/Core/导入操作。
- 两个窗口均提供关闭和 Esc；更新窗口关闭不改变 setupSeen。
- VPHONE_CUSTOM_DISTRIBUTION 控制两个定制窗口；VPHONE_CUSTOM_APP_UPDATE 开启自动安装，关闭则保留独立手动下载安装。未加新宏，不触及 Core、Helper、guest 或 VM 绑定。
- 验证：完整 Release 构建开启/关闭 AppUpdate 通过；真实分发类型下的独立更新模型测试在开启/关闭时通过，覆盖重复点击、检查结果、无发行版、网络失败清理旧结果、状态隔离和历史安装错误读取。未执行本机替换或线上发布，未替用户测试实际安装重启。
