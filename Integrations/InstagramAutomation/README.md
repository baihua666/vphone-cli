# Instagram 虚拟 iPhone 自动化

独立 Swift 宿主工具，复用现有实例的 `vphone.sock`，运行时不调用 Codex 或大模型。网页/原生控件使用 AX，Instagram 未提供控件的页面使用 macOS Vision 本地 OCR。没有修改 Core、guest、helper、镜像或实例绑定。

目标为 `1-20261023` 中的 `test409518`。当前按 Instagram 452.0.1、英文 UI、430×932 竖屏校准；其它账号/尺寸/语言需要独立校准，不是通用社交平台机器人。

## 一键运行

先在 Launchpad 启动 `1-20261023`。从仓库根目录运行：

```sh
# 同一个目录代表同一个任务；失败后沿用原命令续跑。
Integrations/InstagramAutomation/run.zsh "$HOME/InstagramTestRuns/trial-001"

# 强制通过 Instagram 的“登录已有账号”入口输入账号密码：
Integrations/InstagramAutomation/run.zsh "$HOME/InstagramTestRuns/login-001" --password-login
```

每个新任务生成新的 `VPHONE-xxxxxxxx` 标记，自动执行：核验/登录账号 → 备份简介 → 修改并核对 → 恢复简介 → 生成带编号的测试图 → 上传 Files → 保存相册 → 按编号授权照片访问 → 选图并核对图片编号 → 填写文案 → 发布一次 → 打开实际帖子核验作者、全文和图片编号。

默认复用有效登录态，遇到登录表单则填写凭据。`--password-login` 即使已经登录也走官方账号密码表单，保留已有会话，验证真实密码提交和返回目标账号。另有互斥的 `--fresh-login` 退出后重登模式；本次因设置页持续加载而未通过验收，不要将密码登录验收说成退出后的冷登录通过。

**新目录会创建新帖子。** 同一任务再次运行不会重复发布。工具不自动删除测试帖和已导入图片，方便人工核验。

## 凭据

首次构建：

```sh
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 swift build --package-path Integrations/InstagramAutomation
Integrations/InstagramAutomation/.build/debug/instagram-test set-password test409518
```

测试凭据现在优先读取独立文件 `~/.config/vphone-social-tests/test409518.password`（单行密码，已配置）。重新编译不再需要钥匙串授权，报告不记录密码。文件不存在时才读取原钥匙串；`set-password` 仍只更新钥匙串，不覆盖该文件。

也可以给运行命令加 `--password-stdin`，在终端隐藏输入或由自己的密码管理器通过匿名管道提供。不要把密码直接写在 shell 命令、脚本或环境文件里。正常复用有效登录态、以及验证码后的续跑不需要再次读取密码。

编译后可直接运行独立二进制，无需 Codex：

```text
instagram-test e2e SOCKET RUN_DIRECTORY [--password-login | --fresh-login] [--password-stdin]
```

## 验证码与 PC 已登录会话

验证码由 Instagram 风控决定，脚本不能保证每次登录都不需要验证。

| 页面要求 | 处理方式 |
| --- | --- |
| 同账号已登录设备批准 | 在可信设备批准本次登录，再用原命令续跑 |
| 邮箱/短信验证码 | 从账号实际绑定邮箱/手机号获取；在虚拟机填写，或终端隐藏输入 |
| 验证器代码 | 使用该账号已配置的验证器；本工具不自动改变双重验证设置 |
| CAPTCHA、身份核验 | 在官方页面人工完成，然后续跑；不尝试绕过 |

检测到验证要求时，报告写入 `needs_verification`。交互终端可隐藏输入数字验证码，工具仅在找到唯一验证码输入框时填写；找不到就保留现场，直接在虚拟机验证。非交互运行退出码为 **22**，外部调度器可据此通知操作者。验证码拒绝后不循环重发、不反复尝试。

**PC 登录会话不是邮箱、短信或验证器的验证码接口。** Meta 官方支持已登录设备批准登录请求，但必须是同一账号且当前流程提供此选项。此前 Chrome 的 `tubao1985` 与测试账号 `test409518` 不同。没有实现从浏览器 cookie 推导验证码、复制会话到原生 App 或抓取邮箱验证码。

若将来需要验证码也无人值守，需要另外接入用户控制的验证渠道（如已配置 TOTP 的密钥或授权邮箱接口），并独立验收。即使如此，平台要求 CAPTCHA/身份核验时仍可能需要人处理。

官方依据：[Meta — Keeping Instagram Safe and Secure](https://about.fb.com/news/2021/07/keeping-instagram-safe-and-secure/)。本次帮助中心部分页面返回限流或登录页，未据此虚构当前 PC 页面能力。

## 中断与恢复

- `state.json` 绑定实例、账号及登录模式；不能把一个目录移给另一个实例或更改模式续跑。
- `events.jsonl` 记录阶段、状态、时间，不记录密码、验证码或底层原始错误。
- `fixture.png` 是实际上传的测试图；`published.jpg` 是最终核验截图。
- 简介原值存于权限为 0600 的状态文件，修改前持久化。失败后续跑先恢复本任务修改，再重测。
- 密码提交先记录状态；网络超时后仅等待结果，不自动重复提交密码。
- 发布前持久化 `publishAttempted`。此后续跑只核验结果，不再次点击 Share；如果状态不明，人工核对帖子后创建新任务，不能删改状态强制重发。
- 若发布已成功但核验超时，沿用原目录续跑。若报告 `verify` 已通过，再运行直接返回已完成。
- 同一实例有进程锁。未知弹窗、控件变化、账号不符、图片编号不符均停止，不让 AI 临场接管。

照片访问保持系统现有范围，仅增加本次编号图片，不改成全相册授权。选图后再次核验大图编号；看不到编号即停止。预览页和文案完成按钮有少量经现场校准的坐标，使用前检查页面及竖屏尺寸。

## 开关与验证

宏 `VPHONE_CUSTOM_INSTAGRAM_AUTOMATION` 在 `Package.swift` 集中维护，默认关闭。开启仅影响此模块；关闭时入口直接退出，不连接实例、不注册任务。删除本目录即可移除，但不会撤销 Instagram 已保存的数据或帖子。

```sh
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 swift test --package-path Integrations/InstagramAutomation
# 关闭态使用独立构建目录，避免覆盖用于验收的执行器：
swift build --package-path Integrations/InstagramAutomation --scratch-path /tmp/instagram-disabled-build
```

单元测试验证失败停止、凭据日志隔离、实例串行锁、跨实例/账号拒绝、断点持久化及发布前记录阻断。测试替身仅用于单元测试，不作为真实账号验收依据。

实际验收记录见 [VALIDATION.md](VALIDATION.md)。运行中生成的材料位于 `Artifacts/`，已被 Git 忽略。

## 既有 JSON 分段流程

保留 `validate FLOW.json` / `run FLOW.json SOCKET RUN_DIRECTORY`，供独立步骤排查使用。`Flows/` 的固定标记配置是 2026-10-30 早期现场校准材料，不应直接反复发帖；日常使用上方 e2e 命令动态生成编号和文案。`profile-smoke-test409518.json` 仅用于原简介为空的该账号；e2e 则会备份原值。

### Threads 一键入口

Threads 使用独立入口 `threads.zsh RUN_DIRECTORY [--fresh-login]`，操作实例 `1-20261023` 的 `test409518`。
完整使用方法、独立编译开关和恢复说明见 [THREADS.md](THREADS.md)，实际验收见 [SOCIAL-VALIDATION.md](SOCIAL-VALIDATION.md)。
原 `threads-*.json` 保留为 2026-11-01 分段校准记录，不作为日常重复测试入口。
Instagram 原 `e2e` / `run.zsh` 仍只用于 Instagram。X 按用户要求暂停，尚未通过注册及发帖验收。
