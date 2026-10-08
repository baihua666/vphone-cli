# 官方基线与业务分支

## 2026-10-08 源码同步

- `main`：官方 `Lakr233/vphone-cli` 的 `dfcfae9c608c432a9a63f846d5cda8272fde0b82`，跟踪 `upstream/main`；由 GitHub MCP 核实，与本次 fetch 一致。
- `codex/business-vm`：合并上述官方基线，保留独立取证工具、启动入口和研究历史。
- `codex/pre-upstream-sync-20261008`：同步前完整业务代码 `d23154b`，保留原 Python MobileGestalt 实验、EXP 流程和测试，供查证/后续移植。
- `tb_dev`：原历史指针 `0f76ba1`，不改写。
- `origin` 仍是个人 fork；本次未推送。官方基线较旧 `9c23c8a` 增加 636 个提交（包含合并提交）。

## 架构迁移与冲突处理

采用上游 Xcode workspace、原生 Swift/C 实现及 patch sets/presets，不恢复已删除的 Python 固件流水线。上游现在只公开 JB 模式，不能把旧 `--variant exp` 自动映射为某个 preset。

旧的 `cfw_patch_hv_vmm_dsc.py`、`custom_features.py`、特性头和对应测试不进入新版流水线。本地默认关闭的 MobileGestalt 实验尚未移植；完整可恢复版本在备份分支，不声称它在新版继续生效。历史验证补充保留在 `0_binary_patch_comparison.md`。

旧 `ResourcesTests` 的 signcert 路径和 ObjC 安装器签名测试依赖已经移除的实现，随上游旧代码删除；新版使用上游对应 Xcode 测试。`scripts/exp.sh` 对旧操作明确报错且不修改 VM，避免运行残留旧程序。Python 取证工具及其测试作为独立宿主研究工具保留，不作为产品运行依赖。

研究文档保留在 `Research/` 根目录，不采用 Git 将所有新文件推断到 `Research/Kernel/` 的位置。当前指南在 `AGENTS.md`；本地开发 skill 顶部列出新版边界，旧步骤仅供历史排障。

## 开发与验证

```sh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/XcodeBundle -jobs 4 build

xcodebuild -project VPhoneKit/VPhoneKit.xcodeproj -scheme VPhoneCoreKitTests \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/upstream-sync-tests -jobs 4 test
```

完整构建输出为 `VPhone.bundle`，不是旧 `.build/vphone-cli.app`。运行部署按 `Documents/Guides/host-setup.md` 与 `Documents/Guides/launchpad-cli.md` 验收，不能以源码合并或测试成功代替 guest 版本确认。

## 现有 VM 与运行产物

本次同步不重刷、不迁移、不启动虚拟机，不替换已构建产物。`start.sh official` 仍使用库外官方 1.0.14，`start.sh custom` 仍使用同步前保留的旧版 app；启动脚本明确提示这不代表当前源码。旧运行产物缺失时需恢复对应版本，不能把新 bundle 伪装成旧 app。

当前实例是 `~/.vphone/VMs/stock-regular-guard-20261008` 和仓库内 `vm-fresh`。后续升级运行环境时单独核实宿主、guest daemon、固件兼容性，再决定部署。VM、IPSW、构建产物和 CodeGraph 索引不进入 Git。
