# Threads 原图发帖故障与实测（2026-11-03）

目标：本机 1-20261023，账号 test409518，任务 39D16ED7-B2F8-4E8A-8530-50162FA53D8A，文案 image。保留其原请求、原图及发布检查点，不新建替代任务。未修改 Core、guest、helper 或实例绑定。

## 证据及修改

- 初次任务登录复用成功，import 阶段收到 ui.tree AX element query failed (-25216)，publishAttempted=false。同一任务重跑后 import 通过。分享面板过渡时 AX 暂不可用；只针对 -25216、重启时实测 -25215，最多十次只读重试，其他错误仍三次，不重发点击／保存／发布。
- Files 导入新增存储检查、传图、打开 Files、定位文件、分享、保存和授权检查日志。
- 系统相册第一列实际 x=-0.000003390842，原判断 x>=0 导致排除原图；仅容忍 0.01 点舍入误差并裁到屏内，真正越界仍拒绝。
- 授权原图后，Threads 保留旧的七张缩略图。关闭并重开选图器后新增原图出现，读取到八张。
- 原 Vision 特征距离受缩略图尺寸和勾选标记影响：系统选择前0.421、选择后0.558、Threads网格0.759。临时调大阈值不能稳定解决，最终移除该语义匹配，改为中心方形内容缩放到32×32 sRGB比较像素平均绝对差；最大0.08，第一第二差距须大于0.02，重复／相近图仍停止。只处理比对副本，上传文件不变。
- 实测像素差：系统权限页原图0.061，其它0.229以上；Threads原图0.013，其它0.236以上；草稿附件0.023、提交前0.020。选图、附件检查通过。

## 实际结果

原任务 publish started/passed 各一次，state包含login/import/publish且publishAttempted=true。第一次提交后的重启核验遇到-25215，随后脚本重试和Launchpad界面重试都只走verify，未再出现publish事件。重启后个人主页实际可见账号test409518、文案image、LITTLE GARDENS原图，无添加编号／水印。

证据保留在本机任务目录：events.jsonl、state.json、publication-review.jpg、published-image-review.png。原图SHA256与绑定完全相同：18ae11ae1025d6c6eb7ac30b51d37af70f512ad1ef8d9fe5f0acec51e42464fd。

自动任务状态仍为“发布结果待核验”：没有唯一帖子ID的自动完成判定仍未实现。本次人工查看重启后主页证实发布成功，不伪写verify完成。界面已通过原任务重试更新状态。

40项测试通过，覆盖两类AX短暂失败及重试上限、真实边缘舍入、原图缩略图／选择标记像素匹配、相近图拒绝，以及已有任务防重测试。Release App构建通过。本机更新主程序和自动化执行器、保留原Info/helper并重新签名；发布渠道尚未更新。

编译边界沿用VPHONE_CUSTOM_INSTAGRAM_AUTOMATION、VPHONE_CUSTOM_THREADS_AUTOMATION和VPHONE_CUSTOM_THREADS_DESKTOP；均在既有业务目录，未新增底层协议。
