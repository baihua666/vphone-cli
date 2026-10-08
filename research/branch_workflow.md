# 官方基线与业务分支

- `main`：保留官方基线 `9c23c8adcd4b362120988ab9d228b959bcc23ae3`，不加入业务定制。该提交已通过官方 GitHub MCP 核实；不是最新上游 main。
- `codex/business-vm`：业务开发分支，从原 `tb_dev` 的 `0f76ba1` 继续，保留其构建工作流及现有未提交定制。
- `tb_dev`：保留旧指针，便于追溯；后续业务开发统一在 `codex/business-vm`。

业务分支包含可选 MobileGestalt 定制、EXP 工作流封装、官方/定制实例启动入口、App 验证工具、测试及研究记录。开关默认关闭，分支存在不代表客体已部署这些实验补丁。

镜像共享复用上游 APFS CoW 机制，当前业务成果是验证与使用约束，没有另造共享存储引擎。后续面向业务的模板、克隆、实例数据隔离代码也放本分支；不得把已验证的文件隔离当成全新 IDFA/SEP 身份。

## 开发和运行

```sh
git switch codex/business-vm
./scripts/build.sh
./start.sh custom
./start.sh official
```

`official` 固定使用库外官方 1.0.14 发布 app，`custom` 使用本地完整构建。Git 分支、已构建 app、已安装客体固件是三种状态；切换分支不会替换运行产物或重刷镜像。`main` 不提供业务分支的 start.sh。

当前工作镜像只有官方 `~/.vphone/VMs/stock-regular-guard-20261008` 和定制 `vm-fresh`；前者 Regular + 官方 force-exc-guard，后者历史 EXP。VM、IPSW、构建产物、取证截图及本地 .codegraph 索引不进入 Git。

升级官方基线时先核实上游提交，单独更新 main，再在业务分支合并并解决差异、重跑相关测试；不要把业务分支直接合入官方基线。此轮只整理本地分支，未推送远端。
