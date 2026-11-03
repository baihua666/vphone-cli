# Threads 任务启动前准备（2026-11-03）

用户在另一台 Mac 的 r16 上运行任务时收到“实例未运行或 socket 不可连接”，随后明确确认目标实例 1-20261026 当时没有启动。失败发生在登录／发布前；不能据此判断 Threads 登录失败。

修复沿用 Launchpad 的 MachineLibrary.start，使用任务绑定目录、原 library 和 pinned Core。已运行实例复用，忙碌实例拒绝；启动后复用现有 guest ping 等待最多 120 秒。准备阶段占用任务运行槽，防止双击重复启动。错误显示在任务详情，不修改不可变请求或发布检查点。没有改动 Core、guest、helper 或版本绑定。

隔离：现有 VPHONE_CUSTOM_THREADS_DESKTOP 条件内的 UI 适配与 ThreadsDesktopModel；删除准备闭包重载及 UI 调用即可回退，原执行器和防重记录不变。

验证：32 项自动化测试通过，新增测试覆盖准备失败不启动执行器、保留已提交检查点／原请求、并发第二次运行被拒绝及失败后可重试。Release App 构建和关闭 ThreadsDesktop 的包构建均通过。未在另一台 Mac 执行真实冷启动与发帖，不将单元测试视为端到端验收。r16 未被覆盖，此改动尚未发布。
