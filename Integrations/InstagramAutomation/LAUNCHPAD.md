# Launchpad Threads 自动化

## 使用

在 Launchpad 工具栏打开「Threads 自动化」。填写 Instagram/Threads 用户名、
密码并选择现有虚拟机，保存账号。已有独立密码文件时留空可保留凭据。
先启动目标虚拟机；选择账号，填写文案和/或选择图片，创建任务，核对内容后点击
「一键登录并发帖」。无需 AI、Xcode、Swift 或仓库源码参与运行。

普通任务复用正确账号的登录状态；「重新登录」执行退出后密码登录；
「完整测试」额外修改简介并恢复。当前原生控件只在英语、430×932 竖屏验收。
账号必须已经注册；遇到验证码，在虚拟机完成后点击同一任务重试，不尝试绕过验证。
不同登录账号或不可识别的页面会停止，不会在未核实账号时发布。

支持纯文字、图片加文案、图片不填文案；两者均空时不允许创建。纯文字跳过图片生成、导入及选图。
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

## 修订 15 账号入口反馈与本地修复（2026-11-02）

用户在另一台 Mac 的修订 15 反馈找不到添加账号入口。旧布局把表单置于可伸展列表下方，
仅显示「保存账号」，窗口最低高度 800。此前本机 UI 验收使用修订 0 测试构建，
发布 DMG 只做构建/签名/下载校验，没有从干净账号状态完成 UI 全流程，不能据此声称发布包可用性验收通过。

修复将添加入口与表单置于左上方，区分添加/编辑，右侧可滚动，最低高度降为 560。
本机实际点击添加入口、输入 test409518、选择 1-20261023、保存，确认列表及任务区选中账号；
退出重开后账号与原任务保留。此次保留已有密码，未验证另一台 Mac 首次输入密码的全过程。
本地安装测试只更新主可执行文件并重新签名，保留 helper/Core；不是新的已发布 DMG。
此修复不改变限流记录，仍未完成自选图片真实发布及发布后重试验收。

### 可选图片本地验收

2026-11-02：UI 与执行器均支持无图任务，旧请求缺少 hasImage 字段时按原图文模式解码。
本机从页面选择 test409518，填写用户原文案 121212，不选图片，实际创建
VPHONE-4852F074，状态「待运行」。未点击发布，未绕过账号限流。
26 项自动测试通过，包含纯文字持久化、空内容拒绝、旧请求解码、无图片/无 guest 的
完成任务重试及请求变更拒绝。Release 构建通过，主程序与执行器已更新至本机测试 App。
这仅证明任务创建与自动测试通过，不证明纯文字原生发布已在真实平台验收。

### 用户首次运行纯文字任务的结果

VPHONE-4852F074 在北京时间 2026-11-02 19:48:43 开始登录，19:49:14 因
`guest 拒绝请求: ui.tree` 停止。state.json 为 loginSubmitted=true、publishAttempted=false、
completed=[]，未提交发布。该任务创建时 freshLogin/testProfile 均为 true。
默认的新任务为复用登录态；原生登录步骤会先核对目标账号，只有显式强制测试才退出。
UI 将该选项明确为「强制退出并重新登录（仅测试）」，详情展示任务已保存的设置；
复用时写 session/reused 事件。运行失败时区分「未提交发布」与「发布结果待核验」。
ui.tree 拒绝的底层原因尚未确定，不能将此次失败描述为密码错误或发布失败。

### ui.tree 读取容错修复与真实重试

原客户端丢弃 guest 的具体错误，仅输出方法名，且单次快照失败就中止。
现在保留错误 code/message，仅对只读 ui.tree 最多读三次；不重发任何点击、登录或发布请求，
平台提示检查位于重试外，限流不会被当成读取故障重试。持续读取失败保留原错误退出。
29 项自动测试和 Release 构建通过，执行器已替换本机测试 App 并严格验签。

原目录真实重试记录 session: reused、login: passed，越过此前停止位置；随后简介保存
得到 Try again in 24 hours，保存 retry-after.json。取消未保存编辑后重新打开 Edit profile，
确认 Username: test409518、Bio: + Write bio，证据为任务目录 bio-after-cancel.json。
保留 bioChanged 恢复标志，后续可再次核对；未篡改发布检查点或跳过原任务的简介测试。
UI 点击同任务重试显示平台限流，暂停到北京时间 2026-11-03 20:43，无新增 guest 操作。
publishAttempted 仍为 false。原单次读取错误无法事后恢复，底层具体成因仍未确定；
本次完成的是错误可观测性与有限只读重试，不代表真实发帖已成功。
