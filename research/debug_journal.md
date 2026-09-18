# vphone 开发与排障记录

记录已验证结论、关键证据和未解决的边界；可复用操作见 [开发 skill](../skills/vphone-development/SKILL.md)。不创建 TODO.md。

## 当前结论

- 源码基线：官方 `1.0.14` / `9c23c8adcd4b362120988ab9d228b959bcc23ae3`；自有分支 `tb_dev`。host、guest 和固件补丁代码保持官方版本。
- 完整构建入口：`./scripts/build.sh`，编译自己的源码并打包签名资源。无需使用官方预编译程序，也无需用户手工修改第三方 IPA。
- 官方安装器内部会解包、重签并安装 IPA；用户直接选择原始 IPA 即可。应用的打包工具不是安装前提。
- 当前 `vm/` 为已有 EXP 环境，iPhone/cloudOS 均为 26.1 (23B85)。EXP 是固件变体，通过创建/补丁/安装参数选择，不是 Git 分支。
- 已验证 Orblino Weave 在官方生产源码完整构建后重装、冷启动和游戏交互正常；不代表所有 IPA 均兼容，也不代表干净 EXP 重刷已经验证。

## J-2026-09-18-03 — IPA 启动拒绝：轻量打包遗漏证书（已定位）

**症状与证据：** 10:51:02 点击 wooshort 后，TXM 报 `CodeSignature: selector: 24 | 0xA1 | 0x30 | 1`，随即 RunningBoard 报 `NSPOSIXErrorDomain Code=85`、`Bad executable (or shared library)`、`Launchd job spawn failed`，没有创建应用 PID。

**原因链路：** 干净 `make bundle` 仅携带 `Contents/Resources/signcert.p12`，官方资源解析却查找 `Contents/Resources/scripts/vphoned/signcert.p12`。文件缺失使 host 不上传 `cert_path`；guest 进入无证书签名分支，最后递归签名还会丢失 entitlements。官方 `scripts/build.sh` 会复制完整 scripts 资源树，因此不触发这一打包路径问题。

**控制实验：** 保持当时 host、guest、固件和 Developer Mode 不变，只将项目已有证书复制到宿主 .app 的预期位置，重新安装原始 IPA：

- 10:53:41，Downloads 中的 Orblino Weave (`com.Orblino-Weave`) 以 PID 892 进入前台主菜单。
- 10:58:24，Downloads 中的 SilentShadowsDeep (`com.SilentShadowsDeep.ssd`) 以 PID 925 进入前台主菜单。

这证明恢复证书输入解决了该安装路径；未独立区分 CMS 与 entitlements 各自的必要性。手工复制只是诊断实验，正式流程使用完整源码打包。

**排除的方向：** 缺少 launchdhook 不是这些 IPA 运行的必要障碍。不能根据没有 `.ips`、系统应用正常或单次 `app_launch=NO` 就修改 launchd/内核。临时 `vreq` 调试入口未保留；当前 host 只提供官方控制协议。

## J-2026-09-18-05 — 官方源码完整构建与冷启动（已验证）

**最终方案：** 不保留证书路径兼容、无证书时强制 `-M`、custom-trust 键拼写这三处生产修补。生产代码与官方 `1.0.14` 一致，使用 `scripts/build.sh` 完整构建，停止旧 host 后启动新产物。

**构建与部署证据：**

- `./scripts/build.sh` 成功，`codesign --verify .build/vphone-cli.app` 通过。脚本重新复制资源目录，不依赖诊断时留下的证书。
- 内置嵌套证书与项目证书 SHA-256 均为 `0d8e568d90518d6cb9580b410a45fea7464cd7ebe6c72c6dc44bdc9b2fa90ae0`。
- 构建与 VM 暂存的 guest SHA-256 均为 `79283a3e850edc27e731fa47ed7620cac4bd34b6243a6af3dbaa3532375d3f82`；Guest Version UI 确认 daemon 更新。运行中的构建标签不会随之后的 Git 历史整理自动改变，以验证时的源码差异和二进制哈希为准。
- 新 host 以普通用户启动：`.build/vphone-cli.app/Contents/MacOS/vphone-cli vm launch vm --library-root "$PWD" --variant exp`。

**应用验证：** 使用 `/Users/tubao/code/private/flywheel/Orblino Weave` 现有 `scripts/build_ipa.sh` 生成 unsigned Release IPA（iPhoneOS SDK 27.0），没有修改应用源码。产物 `ipa_build/Orblino-Weave.ipa` 的 SHA-256 为 `1de3d99587fa5144fdc7879753949c86949b74f3e912901f3f8685809f1ce479`。该脚本的选项应放在 `unsigned` 前，否则 `-o` 不生效。

通过官方 Apps → Install 安装后，PID 406 进入主菜单和 Garden 1。随后完整重启 guest，应用以新 PID 388 运行；12:14 RunningBoard 记录 `running-active-Visible`，拖动成功连接一对图案，界面显示 `Connected 1/4`、`Moves 1`、`Garden 8%`。截图保存在本地 `.build/validation/orblino-rollback-cold-game.jpg`。

**保留的验证：**

- `swift test --no-parallel --filter ResourcesTests`：9 项通过，覆盖完整 bundle 和开发目录的证书查找。
- `python3 tests/test_ipa_signing.py`：带证书签名通过，覆盖主程序、扩展权限及 framework 递归签名。官方无证书权限丢失保留为 expected failure，不能计作通过。
- `quick_validate.py skills/vphone-development`、`zsh -n scripts/exp.sh` 和 `git diff --check` 通过。

## EXP 创建与归档

[scripts/exp.sh](../scripts/exp.sh) 薄封装官方构建、创建及导出命令，具体用法见开发 skill 或 `--help`。不另写固件补丁流水线。

- `create NAME OUTPUT.tzst`：完整编译当前源码，官方 `vm create --variant exp`，再导出。
- `export NAME OUTPUT.tzst`：导出现有、已停止的 VM，附带 SHA-256 文件。
- 检查已覆盖：拒绝覆盖已有 VM/归档、修改固定变体、导出占用中的磁盘；最终脚本用隔离的 1 GiB 空 VM 完成导出、校验、官方导入往返。空 VM 测试不等于固件启动验证。
- 实际归档：`.build/exports/exp-orblino-validated.tzst`，13,006,611,657 字节，SHA-256 `183e7807a998635ef4a97772b1f76190b1239f68e81c589e561475d746460edf`。`zstd -t` 和完整 `tar -tf` 通过，包含磁盘、配置、NVRAM、SEP 和 boot ROM，排除恢复中间目录。
- 该归档包含现用 guest 和已安装应用，不是干净分发镜像或通用 IPSW。尚未执行真实归档导入后启动，也未执行干净 EXP 从零创建。

## 独立遗留问题与操作边界

- **O-2 / launchdhook：** 之前会话记录 EXP 注入 hook 后出现 `launchd cannot be run directly` 启动 panic，并通过只保留 jetsam 修改的 launchd 恢复启动。本轮沿用这个 guest，没有重新验证其根因。重装前需单独调查；历史 `DISABLE_LAUNCHD_HOOK=1` 例外不能悄悄推广为所有 EXP 的默认设置。
- **O-3 / EXP DSC：** 之前记录 hv_vmm/camera 预补丁可能因跳过已安装 cryptex 的复制而未落盘，完整性仍待独立验证。IPA 正常不能证明全部 EXP 能力生效。
- **SSH：** 该 guest 的 root SSH 曾拒绝 `alpine`，不要把默认提示当已验证凭据；已有 USB 配对通道可用于日志与进程检查。
- 取证先关联点击时间、TXM/AMFI 和 RunningBoard，再看应用 PID/前台状态。不要全局忽略 TXM 错误。
- 停机后检查实际 host 和磁盘占用进程；某些停止路径只结束 Virtualization 子进程，host 仍可能存活。只处理本次 VM 的相关进程。
- 宿主控制 socket 的 tap/swipe 使用 guest 像素坐标（当前 1290×2796）；截图后再定位，不复用旧图标位置。先唤醒屏幕再操作。
- 源码、磁盘上的构建产物和运行中进程可能是三个版本。不要仅凭 Git HEAD 或构建成功就声称新代码已部署。

## 官方依据

- [官方源码构建与变体说明](https://github.com/Lakr233/vphone-cli/blob/1.0.14/README.md)
- [完整打包脚本](https://github.com/Lakr233/vphone-cli/blob/1.0.14/scripts/build.sh)
- [资源解析](https://github.com/Lakr233/vphone-cli/blob/1.0.14/sources/VPhoneCore/VPhoneResources.swift)
- [guest 安装器](https://github.com/Lakr233/vphone-cli/blob/1.0.14/scripts/vphoned/vphoned_install.m)
