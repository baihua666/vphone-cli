# Threads 选图页关闭按钮坐标偏移：真实环境复现

2026-11-03，北京时间。用户要求优先查官方问题，并授权在当前 Threads
发帖选图页验证关闭按钮失效。本次完成诊断，未实施或部署产品修复。

## 运行上下文

- 实例：`~/.vphone/machines/1-20261026`，保持原 library 与 pinned Core。
- 运行 Core：`2.13.4-local.666ac4da`，Info.plist 的 `VPhoneBuildHash=130e9076`。
- guest：iOS 26.6.2；`device.screen` 返回 430×932 点、scale 3、竖屏、亮屏且未锁定。
- 配置屏幕：1290×2796 像素，与上述点尺寸一致。
- 当前普通窗口外框：266×629 宿主点；CUA 窗口截图为 532×1258 像素。
- 本地 `VPhoneVirtualMachineView.swift` 与官方 2.13.4 tag
  `755d49191a6f0b78fbcdde4f43d56ce45c9bee90` 对应文件逐字相同。

## 复现和单变量对照

进入 Threads 的空白 New thread 页面，打开图片选择器，不选择照片。
guest AX 报告关闭按钮 `label=Cancel, identifier=Cancel`，区域为
`x=24, y=127, width=36, height=36`，中心为 `(42,145)` 点。

| 输入 | 实际结果 |
| --- | --- |
| CUA 鼠标点击窗口截图中关闭按钮中心 `(52,284)` | 图片选择器保持打开 |
| 宿主 socket `tap(126,435)`，即中心坐标乘以 3 | 图片选择器保持打开；稍后截图再次确认 |
| guest RPC `input.tap(42,145)` | 图片选择器关闭，`ui.wait` 确认回到 New thread |
| 重开后，guest `input.touch` 保留 `edge=8`，down 使用归一化 x=0.001，up 使用 x=42/430，y 均为 145/932 | 图片选择器保持打开 |
| 在同一选图页，保持 `edge=8`、相同 y，down/up 均使用 x=42/430 | 图片选择器关闭，`ui.wait` 确认回到 New thread |
| 再重开，CUA 鼠标点击关闭按钮靠右位置 `(71,284)` | 图片选择器关闭，`ui.wait` 确认回到 New thread |

两组 `input.touch` 对照均使用现有 RPC，按 down → 等待 80 ms → up 顺序发送。
实际间隔另包含 CLI 调用开销，不声称为精确 80 ms。唯一有意改变的输入字段是
down 的 x 坐标。所有成功结论基于页面/控件变化，而非输入请求的 `ok`。

## 已确认原因

`beginTouch` 对普通鼠标和 `injectTap` 均调用 `hitTestEdge`。
`VPhoneDisplayGeometry.edgeThreshold` 是 **32 个宿主视图点**。
当前缩小窗口中，按钮中心距离画面左边约 26 个宿主点，落入该范围。
当 guest 支持 `touch_edge` 时，`sendTouchEvent` 把 down 的归一化 x 强制改为
0.001，也就是 guest 的 **0.43 点**；up 却回到原来的 **42 点**。
按下落点已在按钮区域之外，实际不再是对按钮中心的正常点击。

保留 `edge=8` 而取消坐标吸附即可关闭，排除了“只要有 edge 标志就不能点”的解释。
鼠标稍向右、离开 32 宿主点范围后也能关闭，进一步支持同一原因。
本结论适用于已复现的 Threads 关闭按钮，不宣称解释所有应用的中央点击异常。

调用点：

- `VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachineView.swift`：
  `beginTouch`、`injectTap`、`sendTouchEvent`。
- `VPhoneKit/VPhoneCoreKit/VirtualMachine/VPhoneDisplayGeometry.swift`：`edgeThreshold`。

## 官方来源与规范修复范围

- [#525](https://github.com/Lakr233/vphone-cli/issues/525)：全屏黑边被计入触摸区域。
  本地已有 `VPhoneDisplayGeometry` 修复，当前复现发生在普通窗口。
- [#719](https://github.com/Lakr233/vphone-cli/pull/719)：新增 edge digitizer 标志和
  首次按下吸附，相关提交 `f22628872c7f1315824af0aed19553e1335f8d88`。
- [#785](https://github.com/Lakr233/vphone-cli/pull/785)：Duo viewport 缩放修复，
  不是当前 2.13.4 普通 iPhone 路径的修复依据。
- [#683](https://github.com/Lakr233/vphone-cli/issues/683)：自动化文档固定尺寸问题；
  本次所有坐标均使用实时尺寸换算。
- [官方 2.14.0 的 VM View](https://github.com/Lakr233/vphone-cli/blob/2.14.0/VPhoneExecutable/VPhoneVirtualization/UI/VirtualMachine/VPhoneVirtualMachineView.swift)：
  已取消该普通点击吸附，保留 `normalized[0]` 原坐标；注释要求 edge flags 不移动
  ordinary tap，明确的触控板 Home 手势由 `snappedScrollStart` 选择边缘起点。
  现场读取 2.14.2、2.15.0 tag 文件也确认包含这一行为。

建议在用户批准底层修改后，单独回移上述普通点击修正到当前官方 2.13.4 基线，
保持 edge 标志和既有手势路由，避免为此合入整个 Duo/外接显示/相机功能集合。
最小产品改动归属 `VPhoneVirtualMachineView.swift`；无需新增 guest RPC、修改
helper、刷固件或改变屏幕分辨率。若按本地定制交付，遵循仓库编译条件隔离要求，
并验证启用/停用行为；不预先创建未使用的宏。

修复验证应包含：普通点击 down/up 坐标保持一致、该关闭按钮的鼠标与宿主 tap、
中央/四边按钮、不同窗口比例、全屏，以及 Home/返回/控制中心手势。
本轮未构建或部署，因此不声称正式修复已生效。回移也不改变官方基线版本号；
新测试包身份仍应由签名 seal 的内容哈希产生，安装和实例切换单独验收。

## 证据与结束状态

原始请求结果、各阶段 AX 和 `ui.wait` 结果保存在已忽略目录
`.build/validation/threads-touch-20261103/`，编号 01–19。
CUA 的真实鼠标操作与截图记录在本次聊天工具调用中。

验证结束后关闭本轮空白发帖页，`19-return-profile.json` 确认 Create post 控件恢复，
回到原 Threads 页面。未选择/上传图片、输入或发布帖子，未更改 Core、guest 或实例
配置。已有 `Research/debug_journal.md` 和 `BundleActivityTests.swift` 的未提交改动保留。

## 后续：用户授权升级官方 2.15.0 后验证通过

上述“未部署”描述为诊断阶段结束状态。用户随后明确选择同步官方 2.15.0。
已合并官方 tag `fd1610d7` 到业务分支（合并提交 `94dbabe2`），安装测试 Core
`2.15.0-local.f7570c4b` 并切换当前实例后，真实鼠标中心点击、宿主 socket
`tap(126,435)`、guest `input.tap(42,145)` 均正常关闭同一个选图窗口。
没有额外回移或重新实现鼠标修复；使用官方基线的普通点击保留原坐标行为。
完整构建、已知测试缺口、快照与 Launchpad 尚未替换的限制见
[升级验收记录](upstream_2_15_0_upgrade_20261103.md)。
