# 通用照片选择与附件核验

`PhotoPicker` 是独立 Swift library target，通过注入 RPC 闭包复用现有 guest API。
它与 ThreadsDesktop/InstagramAutomation target 没有反向依赖，不读取账号、文案、
任务、凭据，也不导图或发布。保留在现有 package 中，避免新增 Core/guest 协议或平台。
ThreadsOriginalPhoto 只是薄适配器；其它调用方可单独依赖 PhotoPicker product。

## 行为

- 识别系统 `PXGGridLayout-Info` 及旧 `grid-view-cell-*`，从 `device.screen` 读取
  实时尺寸，不写死 430×932。对舍入误差容忍 0.01 point；真实越界拒绝。
- 按格子比例对齐原图与截图裁剪，Vision 特征强匹配阈值 0.25。缩略图重采样可能
  使特征漂移，仅当对齐的 32×32 RGB 平均误差小于 0.018 且特征距离小于 0.75 时，
  才允许像素证据补充匹配。不是把 feature-only 的阈值放宽到 0.75。
- 近邻候选必须相互像素误差小于 0.018，才认为视觉等价的重复缩略图；稳定选择
  首个匹配格子，已选中的可信匹配优先。相似但不等价、已有其它/多张选中项则拒绝。
- 点击前重读布局，点击后最多等待 5 秒确认目标是唯一选中项。部分屏外的已选项、
  截断 AX 树、无候选、无匹配均明确失败；不点击 Done/Post。
- `verify` 先检查原始附件数量必须为 1，再校验 frame；使用附件中央 60% 做视觉
  比较，避开边缘编辑/移除叠层。模糊或未完整显示的附件可能被拒绝，不自动跳过校验。

这证明可见内容匹配，不是 Photos asset 字节身份。无法识别同图不同元数据；
刷新 frame 也不能完全排除同一格子内容瞬时替换。滚动至不可见目标和自动删重复照片
不在本能力范围。当前实机只验收本次照片、窗口及实例；其它裁剪/系统布局需实测。

## 构建和验证入口

`VPHONE_CUSTOM_PHOTO_SELECTION` 由 Package.swift 集中维护，默认开启。
`VPHONE_PHOTO_SELECTION_DISABLED=1` 关闭实际实现；入口在 RPC 前返回不可用，
不会编译 Vision 匹配实现。独立于 Instagram/Threads 的业务宏。

```sh
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 VPHONE_CUSTOM_THREADS_AUTOMATION=1 \
  swift test --package-path Integrations/InstagramAutomation -j 2
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 VPHONE_CUSTOM_THREADS_AUTOMATION=1 \
  VPHONE_PHOTO_SELECTION_DISABLED=1 swift test \
  --package-path Integrations/InstagramAutomation --scratch-path .build/photo-picker-disabled -j 2
```

先构建开启业务执行器的产物。下面命令不执行发布流程：

```sh
Integrations/InstagramAutomation/.build/debug/instagram-test \
  photo-select /absolute/machine/vphone.sock /absolute/original.jpg
Integrations/InstagramAutomation/.build/debug/instagram-test \
  photo-verify /absolute/machine/vphone.sock /absolute/original.jpg image-view
```

第一个只选择已打开选择器中的照片；第二个只读检查调用方指定的单个图片视图。
它们不运行 `threads-task`，也不改变业务任务完成状态。确认 Done 是调用方的流程职责。
不把这些命令当作完整账号登录/发帖验收。

## 2026-11-03 本机结果

已在 `1-20261026`、Core `2.15.0-local.f7570c4b` 上从三个相同缩略图中选择一张，
AX selected 数为 1；确认 Done 后只有一个 image-view，原图核验通过。
留在无文字、单图的未发布草稿；没有点击 Post、登录或更改任务状态。
证据在 `.build/validation/photo-picker-20261103/`，不把用户图片提交仓库。
开启态 36 项测试（9 项通用、23 项业务执行器、4 项桌面）通过；关闭态 28 项
（1 项禁用保证、23 项执行器、4 项桌面）通过，Launchpad 完整构建通过。
独立代码复核指出的原始附件计数及屏外选中项遗漏均已修正，复核确认无新增阻塞项。

兼容接入已有 `25e1f5c8`、`f92e1ea1` 的可选图片和原文/原图行为，避免退回测试
水印路径；没有接入另一个分支的密码明文展示等无关改动。新 Launchpad 构建不等于
部署；证书处理仍按用户要求暂停，已安装旧 App/执行器不会因源码 push 自动更新。

回退/删除：关闭上述宏会明确拒绝原图选择任务，但不会删除草稿、照片或任务。
彻底移除时删除 PhotoPicker target/product、Tests/PhotoPickerTests、main 中两个
入口及 ThreadsOriginalPhoto 的适配，移除 Package.swift 中对应依赖和宏；不要让
业务代码以假成功绕过附件检查。
