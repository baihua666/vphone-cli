# 本地 vphone 存储审计（2026-10-10）

只读审计，未删除文件、分支或改动镜像。范围为本仓库与 ~/.vphone，未包含尚未识别的其他目录、APFS 快照或系统 swap。

## 测量

目录 du 合计 105763640 KiB，约 100.86 GiB。对范围内所有 >=1 MiB 普通文件使用 macOS F_LOG2PHYS_EXT 遍历物理区间、排序求并集，614589 个区间、0 错误：大文件并集 95086743604 字节（88.56 GiB）。小文件 du 合计 1417564160 字节（1.32 GiB）；小文件未去重，故总计约 89.9 GiB，是估算而非精确独占可释放值。检查时目标卷约 50 GiB 空闲。未发现运行中的 vphone VM 或 xcodebuild。

| 内容 | du 约 GiB | 处理建议 |
|---|---:|---|
| vm-fresh | 24.3 | 保留：定制工作镜像 |
| ~/.vphone/VMs/stock-regular-guard-20261008 | 17.6 | 保留：官方工作镜像 |
| .build/validation/pre-excguard-backup | 19.5 | 可删旧回滚镜像，删除后不能恢复其完整客体状态 |
| .build/validation/excguard-stage | 10.3 | 可删旧固件处理产物，非启动依赖 |
| ipsws 与 ~/.vphone/ipsws | 各 10.9 | 启动不需要；可都删，重刷时重新下载。存在共享，不可相加估算回收 |
| .build/out、.build/arm64-apple-macosx、.build/upstream-sync-tests | 共约 2.1 | 可重建的旧构建/测试缓存 |
| .venv、~/.vphone/venv | 共约 0.43 | 旧 Python 环境；删除后旧研究工具需另配环境，新产品不用 |
| .git | 1.2 | 保留，勿直接清对象；分支指针几乎不占空间 |

候选分组中 >=1 MiB 文件物理并集：旧备份 20981901358 字节；固件/IPSW/上述构建与环境缓存 24333999888 字节；两者与保留大文件区间没有交集。合计约 42.2 GiB 的文件物理区间；APFS 快照或范围外克隆可能继续持有这些块，不能保证 df 立即增加同等大小。小文件回收量未加入。

## 必须保留的运行边界

start.sh official 使用 ~/.vphone/runtimes/upstream-1.0.14/vphone-cli.app；custom 使用 .build/vphone-cli.app。因此不能整目录删除 .build。两份镜像的 Disk.img/NVRAM/SEPStorage/config/启动固件应成套保留。取证截图、哈希与日志优先保留，只清可重建大产物。

源码已有 main、codex/business-vm，以及两个历史备份指针 tb_dev、codex/pre-upstream-sync-20261008；仅一个 Git 工作区。删除历史分支几乎不能回收空间，并可能丢失尚未移植定制的入口，不以此作为主要清理手段。

当前源码已同步新版，但运行仍绑定旧版 1.0.14。现存两份镜像在此前完整 extent 对照中共享为 0；分支隔离不产生镜像共享，也不能称为已部署的新共享镜像产品。

MCP 当日读取官方 Documents/Guides/create-and-run.md：新版提供 vm rebase <second> --onto <first> --dry-run，比较后报告 newly shared；实际操作逐字节验证并只替换磁盘，保留设备身份/NVRAM/SEP。此功能尚未在本机两份旧 VM 验证，不直接运行新版命令改动旧镜像。后续先核对本地可用版本及兼容性再 dry-run，不能承诺固定节省量。

来源：https://github.com/Lakr233/vphone-cli/blob/main/Documents/Guides/create-and-run.md
