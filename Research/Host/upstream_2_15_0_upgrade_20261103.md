# 官方 2.15.0 同步、配套部署与 Threads 点击验收

2026-11-03。用户明确授权：同步官方 2.15.0、保留本地业务功能、配套升级
Launchpad/Core、将当前实例切换到新 Core、重启并验证 Threads 选图关闭按钮
及脚本点击。本文同时记录计划、进度和验收限制。

## 基线与约束

- 同步起点：`674b0adb841dbd0492e9649873b307ffb9c1cedb`，分支 `tb_dev`。
- 官方 tag：`2.15.0`，SHA `fd1610d7928aacd6cbc060722bb27fd7d2c76315`，
  已通过官方 GitHub API 与实际 fetch 双重核对。
- 当前运行实例 `1-20261026`，library `~/.vphone/machines`，
  原 Core `2.13.4-local.666ac4da`；另一实例保持原绑定和状态。
- 保留应用管理/ARM Store、临时安装内存恢复、FLYWHEEL、Decodo/原生代理、
  设备初始化、分发与首次向导、Workstation 备用，以及既有定制编译开关。
- 官方版本来自真实合入基线；本地包身份沿用签名 seal 内容哈希，附加 test 标签。
- 本次是本机测试升级，不发布 GitHub Release，不升级 guest 内核/固件；正常启动的
  guest 资源同步按上游流程核验并记录，不把宿主更新等同于完整 guest 环境升级。
- 遵循仓库统一在 `tb_dev` 开发的约束，保留已有未提交修改的独立恢复副本。
- 本机预检未找到有效代码签名身份；已向用户请求可用签名环境，同时继续完成
  源码、构建与测试。必须使用正常签名及 Helper 验证，不以 ad-hoc 替代业务 App 签名。

## 执行计划

1. 保存既有工作和运行基线；合并官方 tag，逐项核对冲突与本地业务入口。
2. 运行 CoreKit、共享 GUI/业务包及 Launchpad 适配测试；构建完整 Core/Launchpad，
   检查相关定制关闭构建、版本、签名 seal 和 bundle admission。
3. 完成代码复核后记录合并提交；保留旧 App/Core 与当前绑定，按正常安装流程
   部署配套版本、切换指定实例、重启并核验实际运行二进制和 guest 状态。
4. 在同一 Threads 页面验证鼠标中心点击、宿主像素 tap 和 guest 点坐标点击；
   回归边缘手势与本地业务入口，恢复空白发帖前页面并记录结论。

## 进度和证据

- 原始工作区 diff、HEAD、文件状态和实例列表已保存到
  `.build/validation/upstream-2.15.0-20261103/`。
- 已有未提交内容为 `Research/debug_journal.md`、
  `VPhoneKit/VPhoneCoreKitTests/Bundle/BundleActivityTests.swift` 与本聊天的
  Threads 诊断文档。保留其独立修改，不默认为本次实现。
- 前置根因与失败/成功对照见 [Threads 诊断](threads_photo_picker_touch_20261103.md)。
- 合并保留官方鼠标输入实现；冲突中保留本地旧 Core 管理兼容范围、测试构建身份
  展示和补丁研究历史。创建初始化测试替身适配官方新增 preset 参数接口。
- Core 完整构建及 `codesign --verify --strict --deep` 已通过。Launchpad 独立测试
  （除依赖完整 App 构建的 FlywheelWebAction 外）均通过；ApplicationManagement
  11 项、FLYWHEEL 45 项（含生命周期矩阵）、Distribution 25 项通过。
- 启动解锁测试和 source-sync 边界测试通过。后者需要 `zsh` 调用，文件本身没有
  executable 位；首次直接调用未执行测试，改用解释器后通过。
- 独立合并复核未发现确定的新增回归。复核指出既有兼容限制：允许管理旧 Core
  不代表新建流程的 `fw kernelcache` 在所有旧 Core 上可用；该问题在同步前已经存在，
  本次不扩大修改范围，也不提高全局版本下限以阻断既有实例。
- `git diff --cached --check` 报告官方导入文件的既有尾随空白/末尾空行；保留官方
  文件内容，不为此次同步批量格式化研究材料或补丁源文件。
- 用户确认询问无证书本地验证。Core 沿用官方 ad-hoc 签名，可经现有已签名
  Launchpad/Helper 正常安装；新业务 Launchpad 构建测试与替换部署分别报告，
  未具备有效 Apple 签名时不替换现有 App、不绕过 Helper 互信。
- 尚未部署，验收待完成。

## 合并构建验证

- Launchpad Debug 完整构建通过；FlywheelWebAction 使用实际 package 产物的
  RPC/实例隔离/目录替换/重试等适配回归通过，共享 Workstation 层 120 项通过。
- CoreKit 执行 672 项，670 项通过、2 项失败（3 个 expectation）。失败均在
  `FirmwareCatalogReportTests`：`lists every curated guest` 和
  `other i phones have pairings of their own`。官方 2.15.0 的 known 增加了
  `iPhone15,4`，但 catalog 没有该型号配对，report 会过滤空配对。
  相关两个产品文件及测试文件与官方 tag 无差异，属于导入基线问题；不为此次
  已有实例宿主升级虚构固件 URL、不跳过测试，也不声称全套通过。
- 该缺口影响 iPhone 15 固件目录/创建覆盖；当前实例重启与触摸路径须另行实测。
- 合并提交只包含官方导入、冲突保留、测试替身适配和本文；原有未提交工作仍在
  独立 stash 中，完成构建来源标记后恢复。
