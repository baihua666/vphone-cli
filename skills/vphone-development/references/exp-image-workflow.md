# EXP 镜像制作、官方补丁与归档

适用于人工分步制作镜像、启用 EXC_GUARD 兼容选项，以及已验证 VM 的归档。基线为官方 1.0.14；升级后重新核对 CLI `--help`。EXP 是固件变体，不是独立分支。

## 选择入口

| 需求 | 入口 |
| --- | --- |
| 普通 EXP 新建并导出 | `scripts/exp.sh create NAME OUTPUT.tzst [vm create 参数]` |
| 新建时启用 EXC_GUARD，或人工控制后续阶段 | `scripts/exp.sh prepare NAME --force-exc-guard [固件参数]`，然后执行下方恢复流程 |
| 现有 VM 已验证，只需归档 | 停机后 `scripts/exp.sh export NAME OUTPUT.tzst` |
| 修复保留数据的现有 VM | 先备份和诊断，参见末尾“已有 VM”；不要把新建流程直接用于它 |

`prepare` 完整编译当前源码，再调用官方 `vm new → fw prepare → fw patch --variant exp`。没有复制补丁算法，也不会自动恢复或导出。默认不加 EXC_GUARD；明确需要时才传此选项。官方 1.0.14 `vm create` 内部 `forceExcGuard: false`，没有对应命令行参数，所以不能向 `create` 直接传递它，也不能靠环境变量假定它已生效。

## 1. 准备及打补丁

首次安装依赖执行 `./scripts/setup_tools.sh`。以下命令在仓库根目录的同一个终端执行，替换固件路径和 VM 名称。选择官方支持的 iPhone/cloudOS 配对，不能混用不匹配的任意版本。

```zsh
export VPHONE_LIBRARY_ROOT="$HOME/.vphone/VMs"
VM_NAME=myphone-exp-guard
CLI="$PWD/.build/vphone-cli.app/Contents/MacOS/vphone-cli"

# 只查看将执行的命令，不构建、不下载、不创建磁盘。
./scripts/exp.sh prepare "$VM_NAME" --force-exc-guard --dry-run \
  --iphone-source /absolute/firmware/iphone.ipsw \
  --cloudos-source /absolute/firmware/cloudos.ipsw

# 实际构建并准备、打补丁；不需要 EXC_GUARD 时删掉该选项。
./scripts/exp.sh prepare "$VM_NAME" --force-exc-guard \
  --iphone-source /absolute/firmware/iphone.ipsw \
  --cloudos-source /absolute/firmware/cloudos.ipsw
```

`prepare` 只接受 `--iphone-source`、`--cloudos-source`、`--iphone-version`、`--iphone-build`、`--force-exc-guard`、`--dry-run`。省略固件参数会进入官方选择或默认处理，复现时应显式提供两份源文件。空 VM 使用官方默认磁盘大小；特殊配置应自行用官方 `vm new --help`，再分别执行 `fw prepare` 和 `fw patch`。

名称已存在会提前拒绝，包括失败留下的半成品。失败后保留现场、查最后成功阶段，不自动删除或再次对已打补丁固件运行 patch。要重新准备，使用新的 VM 名称和原始 IPSW。完整构建失败时不会创建新 VM。

## 2. 恢复、安装与首启（只对刚创建的新 VM）

这些步骤会向新 VM 的磁盘写入系统。先确认目标名称和库路径；现有 VM 不适用。每一步成功后再执行下一步，勿把整段命令无检查地粘贴执行。

```zsh
"$CLI" vm info "$VM_NAME"
"$CLI" vm launch "$VM_NAME" --dfu &
```

等待 DFU 就绪，确认目标设备；如有其他 DFU 设备，应先排除歧义，并按官方 restore 参数显式指定目标。再依次执行：

```zsh
"$CLI" restore "$VM_NAME" --get-shsh
"$CLI" restore "$VM_NAME"
"$CLI" vm stop "$VM_NAME"
```

确认该 VM 的 host 已退出、磁盘不再被占用，才执行离线 CFW 安装：

```zsh
"$CLI" cfw install "$VM_NAME" --variant exp
"$CLI" vm launch "$VM_NAME" --variant exp
```

安装可能要求在终端输入 sudo 密码；不写入脚本、日志或命令参数。首次启动等待 JB setup 完成，必要时检查 guest `/var/log/vphone_jb_setup.log`。不要把历史 `DISABLE_LAUNCHD_HOOK=1` 或其他现场例外默认为新镜像必需参数。发生旧日志中的 launchdhook/DSC 问题应另行取证，不自动绕过。

## 3. 验收与导出

1. 检查完整 host bundle 含嵌套签名证书；记录源码 SHA、submodule gitlinks、两份 IPSW 的 SHA-256、变体与显式参数。
2. 通过官方 Install 菜单安装原始 IPA，冷启动并实际操作。EXC_GUARD 验收必须触发曾崩溃的 SDK 初始化；检查回调、PID 和新崩溃报告。广告 no_fill 不等于展示成功。
3. 正常停机，导出并验证归档：

```zsh
"$CLI" vm stop "$VM_NAME"
./scripts/exp.sh export "$VM_NAME" "$HOME/Downloads/$VM_NAME.tzst"
shasum -a 256 -c "$HOME/Downloads/$VM_NAME.tzst.sha256"
zstd -t "$HOME/Downloads/$VM_NAME.tzst"
```

脚本拒绝覆盖归档和导出占用中的磁盘。分发前还应将归档以新名字导入、启动并验证应用；仅压缩完整性检查不能证明可启动。归档包含 guest 数据和设备身份，分发镜像应使用专用干净 VM。当前旧归档 `exp-orblino-validated.tzst` 生成于 EXC_GUARD 修复之前，不含后来的补丁。

## 已有 VM：不要将固件生成误认为部署完成

只重编译 host、修改启动 `--variant exp`，或者运行 `fw patch`，不会把已安装磁盘里的内核自动换掉。官方通用路径是重新准备原始固件、打补丁、恢复、安装；恢复前必须备份并确认数据处理范围。

保留数据的定点维修参考 [J-2026-09-18-06](../../../research/debug_journal.md)：停机、备份 Disk.img/NVRAM/SEP/配置和实际 Preboot IMG4；临时目录中从原始 IPSW 动态生成官方 patch 记录；确认待修内核与目标匹配，仅应用所需记录并验证容器属性及精确差异；卸载磁盘后重启、复现验收。不得复用日志里的偏移、卷 UUID 或 disk 编号，也不得把整套新固件覆盖到有历史差异的 guest。

此类定点维修依赖现场内核和挂载状态，当前没有通用自动落盘脚本；不要将其包装成无需校验的一键热补丁。可快捷复用的是上述新建固件流程和已有验证 VM 的导出。

## 来源与验证范围

- [官方手工创建流程与 EXC_GUARD FAQ](https://github.com/Lakr233/vphone-cli/blob/1.0.14/README.md)
- [官方创建编排器](https://github.com/Lakr233/vphone-cli/blob/1.0.14/sources/vphone-cli/VPhoneCreateOrchestrator.swift)
- 本次脚本验证覆盖参数分流、失败中止和不覆盖已有 VM；未执行新的完整固件恢复。已有 VM 的官方 EXC_GUARD 补丁及 SDK 回调已实测，不能据此声称新建 EXP 全流程已通过。
