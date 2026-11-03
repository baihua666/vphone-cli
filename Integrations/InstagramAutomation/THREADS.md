# Threads 一键测试

2026-11-02 已在 test409518 完成全新目录一次性完整验收（含退出后密码登录），
同目录重复运行未重复发帖。19 项测试通过，证据见 [SOCIAL-VALIDATION.md](SOCIAL-VALIDATION.md)。

入口为 `threads.zsh`，复用同目录已有 Swift 执行器、凭据读取、socket、OCR、导图与任务日志。
不调用 Codex、大模型或外部 AI。只针对实例 `1-20261023`、账号 `test409518`、Threads 453.0.0、
英文 UI 与 430×932 竖屏校准。先在 Launchpad 启动实例。

```sh
Integrations/InstagramAutomation/threads.zsh "$HOME/ThreadsTestRuns/trial-001"
```

新目录创建新的随机编号图和一条测试帖；同目录代表同一任务，失败后用原命令续跑。
完成目录再次执行直接退出，不发布第二次。不要删改 state.json 强制重发。

流程：核对编辑资料页的 Username → 备份简介 → 保存测试简介并读回 → 恢复原值并读回 →
生成带二维码测试图 → Files/Preview 保存相册 → 只授权本次照片 → 解码定位实际格子 →
核对附件二维码中的编号 → 输入并断言全文 → 持久化发布尝试 → 发布 → 等待上传 →
重启 Threads → 重新核验账号、全文及图片二维码，保存截图。

`state.json` 绑定平台、实例、账号与登录模式，Instagram 目录不可混用。状态与报告权限 0600。
同实例使用已有锁，Instagram 与 Threads 不能同时驱动同一虚拟机。
发布状态不明时仅继续核验，不重新点击 Post。简介遇到第三方修改时停止覆盖。
明确登录失败会保存 login-error.jpg 并退出，后续可原命令重试；结果未知不自动重提密码。未知界面会停止；验证码、身份核验仍可能需要人在官方界面完成，再沿用命令续跑。

退出后重新登录模式为 `--fresh-login`。测试密码优先从独立本机文件
`~/.config/vphone-social-tests/test409518.password` 读取（仅一行密码，已配置，位于仓库外）。
修改该文件即可更换测试密码；重新编译无需钥匙串授权。缺少文件时才回退到原钥匙串，
也可加 `--password-stdin` 在终端隐藏输入。注册只进行一次，不纳入日常回归任务。
实际验收范围以 SOCIAL-VALIDATION.md 为准，不以存在参数表示已验收。

## 编译与开关

```sh
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 VPHONE_CUSTOM_THREADS_AUTOMATION=1 \
  swift test --package-path Integrations/InstagramAutomation
```

两个宏均在 Package.swift 集中声明，默认关闭。现有执行器基础宏控制共用能力；
`VPHONE_CUSTOM_THREADS_AUTOMATION` 额外控制 Threads 入口和 Threads/ 目录中的实现。
仅开启 Instagram 宏时，Threads 命令明确不可用，不创建任务或连接实例。
编译后可直接运行 `.build/debug/instagram-test threads-e2e SOCKET RUN_DIRECTORY`，无需每次构建。

删除 Threads/、threads.zsh、ThreadsTests.swift、专用宏和 main.swift 的条件入口即可移除此扩展；
RunState 的可选 platform 字段继续兼容旧 Instagram 状态。停用不会撤销已创建的帖子或照片。
未触及上游产品文件、Core、guest、helper、VM 绑定或代理。
