# 宿主与客体运行版本验收

用于确认普通 vphoned 控制链路及部署版本，不验证固件补丁、设备身份或广告结果。

## 版本字段的含义

- 宿主 `VPhoneBuildInfo.commitHash` 是构建时的 Git 标识。
- Connect → Guest Version 向运行中的 daemon 发送 `version`，返回 `VPHONED_BUILD_HASH`，不是二进制 SHA-256。
- 握手时宿主发送暂存 daemon 的 SHA-256；客体读取自身可执行文件计算哈希，发现不同会请求更新。仅看到 `connected` 不能替代明确的 `hash OK` 证据：自文件读取失败时，旧协议并不会强制拒绝握手。
- Git 标识不会唯一标识包含未提交改动的构建；保留工作区差异和二进制 SHA-256。

## 现有入口与测试用例

| 用例 | 操作 | 通过条件 |
| --- | --- | --- |
| 客体往返 | Connect → Ping | 弹窗显示 `pong`；不是只检查窗口标题 connected |
| 运行版本 | Connect → Guest Version | 弹窗构建标识与本次编译传入的 `VPHONED_BUILD_HASH` 相同 |
| 部署文件 | 对构建、bundle 内和所选 VM 暂存 daemon 计算 SHA-256 | 三者相同；此项本身不代表客体已更新 |
| 客体更新 | 启动前后采集所选 UDID 的 vphoned 日志 | 若旧文件不同，应有更新及重启证据，随后出现 `hash OK` |
| 更新后功能 | 更新完成后再次执行 Ping 和 Guest Version | 两项都成功，版本为本次构建值 |

## 避免增量构建留下旧标识

当前 `scripts/vphoned/Makefile` 的输出仅依赖 `.m`、`.h` 文件；仅改变 `GIT_HASH` 不会触发重编译。需要验证当前提交标识时，先正常停止目标 VM，再使用已有 clean 入口：

```sh
make -C scripts/vphoned clean
./scripts/build.sh
codesign --verify --deep --strict .build/vphone-cli.app
shasum -a 256 .build/vphoned.signed \
  .build/vphone-cli.app/Contents/Resources/vphoned.signed
```

这只清理可重建的 daemon 产物，不删除 VM 数据。不要使用项目级 `make clean` 代替此命令。

第二台的入口仍是 `./start.sh 2`。它启动 `vm-fresh` 并暂存 daemon，连接建立后由现有握手更新客体。该命令不应用固件补丁。

按 `idevice_id -l` 实际识别的目标 UDID 采集：

```sh
idevicesyslog -u <目标UDID> --no-colors -p vphoned
```

启动过程可能先多次出现连接重置。记录最终握手和具体时间，不因首次未连接就立即重启，也不将一直未连接判为通过。测试结束停止日志采集器。

## 证据边界

上述用例证明控制链路与 daemon 部署，不证明某个业务功能分支执行。普通业务改动仍需各自的输入、预期输出和分支证据。`no_fill`、GUI 出现或宿主构建成功均不能替代运行态验收。
