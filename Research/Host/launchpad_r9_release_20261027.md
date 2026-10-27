# Launchpad 2.13.4 修订 9 发布

用户于 2026-10-27 明确要求发布新版本。源码继承 `codex/legacy-guest-repair-isolation`，包含独立 App 更新窗口、开始使用窗口，以及旧实例黑屏修复的静态 Hook 隔离。官方基线保持 2.13.4 / `7f55bebdcbed913541928b9c4b1c1ca79abc0822`，仅 App 发行修订增加到 9。同步用户要求的 Hook 优先开发规范。

使用精确源码提交的干净快照构建 App；团队配置和签名身份仅通过本机构建参数传递，不进入源码。沿用 Apple Development 内部分发，未公证。Core 采用完整构建、验签并完成开关两态验证的 `2.13.4-local.9e7ad669`（Debug 构建）；其修复流程此前在 2 / 3 号以 `1da558c7` 验收，新包是同一修复的静态 Hook 整理，未对新内容身份重复部署实机。详见旧实例黑屏研究与静态 Hook 维护说明。

发行目录仅含签名 App DMG、Core ZIP、launchpad-catalog.json；`images=[]`、`previousTags=[]`。镜像由用户线下管理，本次不上传镜像或分片，不删除历史附件，不安装本机 App 或 Core，不修改实例绑定或 guest。既有实例继续使用各自 pinned Core。

更新安装器的真实签名包测试允许传入修订号，保留旧默认值，供 r9 包执行原有修订、签名、篡改和失败保留验证。最终构建、测试、附件摘要、草稿及公开结果留在工作树 `.build/r9-evidence/`，实际下载验收使用全新 `.build/r9-online-acceptance/`，不会下载镜像或安装 Core。
