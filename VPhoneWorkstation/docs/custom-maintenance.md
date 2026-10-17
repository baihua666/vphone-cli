# 定制分支维护

GUI 已迁入主 monorepo 的 `VPhoneWorkstation/`，日常工作统一使用主仓库的 `tb_dev`，不再向相邻旧 vphone-ws 仓库提交新开发。

完整流程、目录边界、固定运行宿主和双上游同步方法见 [monorepo 开发说明](../../Documents/Guides/monorepo-development.md)。

从主仓库根目录执行：

```sh
./scripts/dev.sh test gui
./scripts/dev.sh build gui
./scripts/dev.sh run
```

从 GUI 子目录仍可执行 `swift test` 和 `./scripts/bundle.sh`；构建不会自动部署底层 CLI 或修改 VM。GUI 上游通过主仓库的 `workstation-upstream` 以 `git subtree pull --prefix=VPhoneWorkstation workstation-upstream main` 同步。
