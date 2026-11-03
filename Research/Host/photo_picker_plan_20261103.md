# 通用照片选择修复计划

目标：在当前实例选择原图并确认单附件，不发布。复用已有 ui.tree、device.screen、
screen.screenshot、input.tap；不修改 Core、guest、Helper 或实例绑定。

设计：同一 Swift package 内新增独立 PhotoPicker library，既供社交适配器调用，
也供只选图的 CLI 验证入口调用。模块不含账号、Threads、文案、发布或任务状态。
识别系统 PXG 和旧 grid-view-cell，按实时屏幕比例裁剪；小量浮点越界夹紧，
真实越界拒绝。相似度匹配唯一目标；多个可信候选仅在缩略图视觉等价时视为重复，
优先已选中的一张，否则稳定选择首个。多个已选或近似但不等价时拒绝。
视觉等价不声称相册资产字节相同；错误区分空候选、无匹配和歧义。

- [x] 接入既有原文/原图兼容提交 25e1f5c8、f92e1ea1 的相关改动；不接入凭据展示改动。
- [x] 先写旧/新格子、浮点边界、重复/近似/未命中测试并观察失败。
- [x] 实现通用模块、窄适配和不可能发帖的 photo-select 入口；验证开关两态。
- [x] 当前实例原图选择、Done 后单附件确认；不输入文案、不点 Post，保留现有草稿。
- [x] 构建 Launchpad，记录测试及运行边界；证书处理仍暂停，不替换 App。
- [ ] 提交并 push 本次修复及说明。

编译开关：VPHONE_CUSTOM_PHOTO_SELECTION 在本 package 集中定义，默认启用；
VPHONE_PHOTO_SELECTION_DISABLED=1 关闭，入口明确报不可用。业务本身仍受原宏控制。

实测发现：只修正 identifier 后找到了 3 个候选，但原 Vision 阈值仍拒绝缩略图。
裁剪对齐后，特征距离约 0.39，像素平均误差约 0.011；附件中央区域特征距离约
0.64、像素误差 0.0122。以严格像素对照补充、而非单独放宽语义特征阈值后均通过。
记录失败轮和 red→green 测试；代码复核指出屏外已选项/多附件被 compactMap 漏算，
已先检查原始元素并补拒绝测试。未触碰已安装签名 App、Core 或 guest。
接口、边界、宏和删除步骤见 [能力说明](../../Integrations/InstagramAutomation/PHOTO-PICKER.md)。
