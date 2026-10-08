# VPHONE 客体只读探针

独立 iOS 测试应用，用于在客体应用进程内读取公开系统接口。它不是 daemon
版本检查，不含广告 SDK，不更改系统属性，也不实现设备身份伪装。

## 构建与运行

在仓库根目录执行：

```sh
zsh tests/guest_probe/build.sh
```

产物为 `.build/validation/guest-probe/TBGuestProbe.ipa`。在正在运行的 VPHONE 中选择
**Apps → Install IPA/TIPA…** 安装；通过客体桌面的 **VPHONE Probe** 图标打开。
VPHONE 现有安装器会按已有流程重签测试应用。不要将这个包当作具有正式签名的真机发布包。

已配对且开发服务可用时，也可启动明确选定的目标设备：

```sh
xcrun devicectl device process launch --device <目标UDID> com.tb.vphone.guestprobe
```

每次应用进程启动或点击 **Refresh** 都会重新采集，并将 JSON 写入自身
`Documents/report.json`。应用声明文件共享以便取回报告：

```sh
.venv/bin/python -m pymobiledevice3 apps pull \
  --udid <目标UDID> --documents com.tb.vphone.guestprobe \
  Documents/report.json .build/validation/guest-probe/guest-report.json
```

用 `idevice_id -l` 确认 UDID，不使用默认第一台设备。`--documents` 下仍需
`Documents/report.json` 路径。设备上若已有同 bundle ID 的测试应用，安装会更新它。

## 运行态验收用例

1. 启动：页面出现 JSON，报告源文件 SHA-256 与 `main.m` 一致；查看 UID/EUID，
   不将 root 进程结果称为普通应用结果。
2. 实际调用：记录每项 `ok/value` 或 `errno/error`。读取被拒绝也是测量结果，
   不能把错误转换为“不是虚拟机”。
3. 刷新：保存第一份报告，点击 Refresh 后再次取回；第二份时间应更新、PID 应不变。
   按钮注入返回成功不足以通过，必须检查报告确实更新。
4. 对照：保存每次环境配置和报告后再比较；相同型号字符串不能证明真机等价。

自动点击无法可靠触发 Refresh 时，可以用上面的启动命令加
`--terminate-existing` 只重启此测试应用。两份报告的 PID 和时间都应改变；
这是进程重启用例，不能记作 Refresh 按钮用例通过。

本测试应用独立于生产功能宏，目的是在生产功能关闭时也能测量基线。
没有新增或更改 vphone、vphoned、内核及 DSC 的定制功能。

## 字段解释与边界

- `UIDevice.model` 通常是 `iPhone` 这类名称，不是硬件型号。
  参见 [Apple 文档](https://developer.apple.com/documentation/uikit/uidevice/model)。
- `TARGET_OS_SIMULATOR` 是此可执行文件的编译目标标志；值为 0 不证明运行环境是真机。
- UID 501 表示本次以 mobile 用户运行，不证明整个研究系统的沙箱与实体零售设备完全一致。
- 源文件 SHA-256 是构建输入标记，不是远程可信证明，也不是已部署固件的哈希。
- 本探针不判定“是否真机”，不验证 MobileGestalt 实验是否启用，不进行广告测试。
- 报告只含模型、系统版本、基础硬件查询、PID/UID 和时间，不采集 UDID、IDFA、定位、账号或文件内容。
