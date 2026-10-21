# Guest 剪贴板变化通知（2026-10-17）

## 现场与定位

- 两台 2.x 实例控制连接正常，但 `clipboard.get` 始终返回空内容、`change_count=0`。
- custom 中长按网页文字并点 Copy，Safari 自己的地址栏可以 Paste 得到所选文字；同一时刻 vphoned 仍读为空。故复制已发生，故障在 guest 服务读取环节。
- 对照重启原版 vphoned 后，可以读取已有内容；再次复制后出现 `Clipboard text is unavailable to this process.`。仅重启服务不是修复。
- IcliKit 的剪贴板权限清单与 daemon 存在差异，曾测试补齐权限。但原权限的原版进程重启后也可读取既有内容，因此没有证据支持权限是本故障根因；本次撤回全部试加权限。
- daemon 主线程在 `server.closeFuture.wait()` 阻塞，没有运行主事件循环。UIPasteboard 初始读取缓存后无法正常处理新的变化通知。保持主 run loop 运行后，新复制计数和文本可以持续更新。

参考：固定官方基线 `Lakr233/vphone-cli@dfcfae9c608c432a9a63f846d5cda8272fde0b82`，以及 [IcliKit 权限说明](https://github.com/owngoal-dev/icli/blob/main/docs/entitlements.md)。权限说明不构成本问题各权限必要性的证明。

## 修改与部署

- `VPhoneDaemon/Daemon/main.swift`：用 Port 保持主 run loop，在 NIO channel 关闭时停止，然后沿用原关闭流程。
- 未修改 host 剪贴板逻辑、guest 权限、固件、实例身份或网络规则。
- 完整 `VPhone` Debug 构建通过；日志 `.build/clipboard-build.log`。
- 两台固定 runtime bundle 的 guest resource 和机器目录 `.vphoned.signed` 均已更新，外层 bundle 重新签名并通过 `codesign --verify --strict`。现有自动更新机制在线重启 guest 服务，VM 未重启。
- 新 daemon SHA-256：`4a575afc7864af1579cd49e93c97c5af35bacbbb0aa0340ad68f5bf136789b4d`。
- 原 daemon 的单文件回退副本：`.build/validation/clipboard-20261017/vphoned-before`，SHA-256 `afd8d210b243ffa52a2e003bb7e3720b594855ea150d1c295cee937a1e95cd1e`。没有创建额外 VM 镜像或完整 runtime 副本。

## 验收范围

- custom：修复后再次 ⌘C，计数 4 → 5，Mac 剪贴板与 guest 文本相同；随后触控 Copy 另一段文字，计数增至 6，guest 返回新文本。
- official：初始空剪贴板后，多次复制计数 1 → 2 → 3，guest 均能读取新内容；通过 host 菜单“编辑 → 拷贝”时，Mac 与 guest 内容相同。
- 后续自行完成 GUI 验收：custom 的 Safari 地址栏长按选中文本、点 iOS Copy，再让 VM 窗口真正失焦（最小化），在 Mac TextEdit 新建测试文稿按 ⌘V，实际显示 `https://api.ipify.org/?format=json&check=custom-1792142405`。不是用宿主写入剪贴板模拟结果。
- official 通过原生“窗口 → 当前 VM”激活后按 ⌘C，再通过 TextEdit“窗口 → 测试文稿”切换并按 ⌘V，文稿由 custom 网址变为 `https://api.ipify.org/?format=json&check=official-1792142405`。两份不同文字验证了不是读取旧内容。
- CUA 对后台窗口直接发点击/按键不一定真正改变 AppKit key window；此方式的触控复制切出仍可能读到旧 Mac 内容。上述端到端结果仅覆盖明确激活/失焦的路径，不将自动化后台输入的行为直接定性为产品故障，也不要求用户代验收。
- 图片、富文本及 VM 整机重启后的行为尚未验收。本次没有用一次读取成功冒充全部剪贴板路径成功。

## 收尾

- 为恢复最小化的 custom 测试窗口，经 Workstation 正常 Stop/Start，已回到 iOS 桌面，guest 控制连接及剪贴板接口正常。official 保持运行。重启后的端到端复制尚未另做一轮，不扩大验收结论。
- 本次新建 TextEdit 文稿已关闭，临时文稿移到废纸篓；原有 TextEdit 文稿未修改。最终未新增宿主产品代码或权限改动。
