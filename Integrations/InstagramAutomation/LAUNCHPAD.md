# Launchpad Threads 自动化

## 使用

在 Launchpad 工具栏打开「Threads 自动化」。填写 Instagram/Threads 用户名、
密码并选择现有虚拟机，保存账号。已有独立密码文件时留空可保留凭据。
先启动目标虚拟机；选择账号、图片并填写文案，创建任务，核对图片预览后点击
「一键登录并发帖」。无需 AI、Xcode、Swift 或仓库源码参与运行。

普通任务复用正确账号的登录状态；「重新登录」执行退出后密码登录；
「完整测试」额外修改简介并恢复。当前原生控件只在英语、430×932 竖屏验收。
账号必须已经注册；遇到验证码，在虚拟机完成后点击同一任务重试，不尝试绕过验证。
不同登录账号或不可识别的页面会停止，不会在未核实账号时发布。

当前为自动化测试页面：图片副本会添加可见的二维码/任务编号识别条，文案前加编号，
用于从相册唯一选图及重启客户端后的帖子核验。原始图片不修改，创建后显示实际预览。
识别条不是无损发布模式。含编号的文案最多 500 字。

## 本地状态与防重

- 账号与任务：`~/Library/Application Support/vphone-launchpad/Threads/`。
- 凭据：`~/.config/vphone-social-tests/<username>.password`，独立文件，权限 0600。
- 每个任务拥有固定 UUID 目录、request.json、fixture.png、state.json、events.jsonl、run.log。
- 首次运行绑定请求与图片 SHA-256；重试不接受更换实例、账号、文案或图片。
- 复用原脚本的实例 flock；同一实例不能同时执行两个自动化任务。
- 点发布前持久化 publishAttempted；未知发布结果的重试只核验，绝不再次点发布。
- 已完成任务重试直接返回“未重复发帖”。新建任务才表示另一次发布意图。
- GUI 崩溃重开后“运行中”标为“已中断”，重试沿用同一目录与执行器检查点。
- 本地 JSON 损坏时报错，不覆盖原文件。手工删除任务状态会破坏防重证据。

## 实现与边界

`Sources/ThreadsDesktop/` 保存账号/任务、准备发布图片、启动 Process 并显示进度。
Launchpad `Threads/` 只组装界面与现有实例列表；工具栏、Window 和模型只增加窄入口。
现有 `ThreadsWorkflow/Session/Post` 是唯一原生操作实现，不另建 UI 操作脚本。
`threads-task RUN_DIRECTORY` 读取固定任务；旧 `threads.zsh` 测试入口继续可用。
GUI 与执行器共享 ThreadsTaskRequest。账号未写入 VM manifest、guest 或 helper。
不改 Core、guest、固件、helper、网络及运行时绑定，不升级实例。

`Build/embed.zsh` 在 App 构建时编译既有执行器到 `Contents/MacOS/threads-automation`，
运行时无编译步骤。`SignLaunchpad.sh` 对该子程序单独签名。

## 开关与回退

- `VPHONE_CUSTOM_THREADS_DESKTOP`：Launchpad xcconfig 通过 `VPHONE_THREADS_DESKTOP` 默认启用；
  清空该变量关闭 UI、模型实例与执行器嵌入。关闭态不会删除账号或任务数据。
- SwiftPM 的 ThreadsDesktop target 同名宏集中在 Package.swift；
  `VPHONE_THREADS_DESKTOP_DISABLED=1` 可单独验证整个业务 library 关闭态。
- 既有执行器仍由 `VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1` 与
  `VPHONE_CUSTOM_THREADS_AUTOMATION=1` 显式启用。
- 完全移除时删 ThreadsDesktop 源码/测试、Launchpad Threads 目录、三处条件组装、
  package product 引用、Embed Threads build phase、签名条件与 xcconfig 变量。
  账号和任务由用户保留；不涉及底层回退。

## 验证命令

```sh
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 VPHONE_CUSTOM_THREADS_AUTOMATION=1 swift test --package-path Integrations/InstagramAutomation
VPHONE_THREADS_DESKTOP_DISABLED=1 swift test --package-path Integrations/InstagramAutomation --scratch-path .build/threads-disabled
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj -scheme VPhoneLaunchpad -configuration Debug -derivedDataPath .build/threads-launchpad build
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj -scheme VPhoneLaunchpad -configuration Debug -derivedDataPath .build/threads-launchpad VPHONE_THREADS_DESKTOP= build
```

验收结果另记于本文件后续段落。测试通过不等于正式发布批准；本地产物默认测试版。

## 2026-11-02 真实 UI 验收

- 在本地 Launchpad 测试窗口中添加并保存 `test409518` → 实例 `1-20261023`，
  使用已有独立凭据，选取本地测试图片、填写文案并创建任务。
- 任务 `57DA3B13-8A80-4B19-A937-4FA2F8AD579F`，编号 `VPHONE-57DA3B13`，
  勾选重新登录及完整测试，从页面点击执行，真实重新登录通过。
- 简介保存遇到 Threads 的 `Try again in 24 hours`，明确活动限额。
  停止后取消未保存编辑，重新打开 Edit profile，读回 `Username: test409518` 和
  `Bio: + Write bio`，确认原空简介未改变。恢复证据在任务目录的 bio-unchanged.json。
- 没有执行发布：state.json 中 publishAttempted=false，completed 仅包含 login。
  不将此前 CLI 的成功发布冒充这次新 UI 与自选图片流程的完整验收。
- 为真实观测到的限流保存 retry-after.json，新的执行器也会自动识别同样的提示并保存暂停时间。
  暂停期同任务重试会在任何 guest 操作前返回，不自动重置暂停时间、不尝试其它账号绕过。
- 本次首个运行的旧执行器尚未自动识别限流，返回普通 Profile 等待超时；
  上述限流识别是本轮根据真实失败增加的修复。恢复记录明确记载这次人工只读核对及取消编辑。
- 尚待限额解除后完成：该任务的简介测试、所选图片导入/发布核验、发布后真实再次点击重试。
  自动测试覆盖已完成检查点直接返回、发布检查点禁止重发、任务/图片变更拒绝及限流重试。

### 本机交付与重试核验

已将测试版安装到 `/Applications/vphone-launchpad.app`，保留原 App 的 helper、
CLI、launcher、资源与 Info.plist，更新 UI 可执行文件/debug dylib 和新执行器；
使用原 Apple Development 身份重新签名，`codesign --verify --deep --strict` 通过。
原包备份：`.build/threads-ui-test/backup/vphone-launchpad.app`。
本次未正式发布，未上传镜像或其它附件，未改 VM pinned Core。

重开已安装 App 后，账号及 UUID 任务都保留。通过页面再次点击「重试同一任务」，
显示「平台限流」，暂停至 2026-11-03 18:40（北京时间），事件日志没有增加登录、
简介或发布步骤，publishAttempted 仍为 false。不是新建任务，也没有重新提交到 Threads。

24 项自动测试通过（ThreadsDesktop 2 项、现有执行器及新增用例 22 项）。
已完成检查点的测试使用不存在的 guest socket 验证直接返回，不可能产生 guest 操作；
真实发布后的第二次 UI 重试仍需在平台限制解除且本任务首次发布成功后补验。
