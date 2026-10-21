---
name: vphone-app-install
description: 为直接 CLI 或 vphone-ws 管理的 2.x 虚拟 iPhone 安装本地 IPA/TIPA，核对安装和启动；适用于应用安装及镜像重建后的恢复。Launchpad 用户优先使用已有 vphone-guest-control 流程。
---

# 安装 vphone 应用

复用源码仓库 `VPhoneKit/VPhoneExternalAccessKit/VPhoneAPIClient.swift` 和 guest `apps.install`。本技能的 `scripts/install-app.sh` 只在 Mac 临时编译一个客户端；不修改固件，不向 guest 安装额外工具，不需要 sudo。适配已实测的 VPhone.bundle 2.8.0；旧 1.x 不能照搬。

若已经使用 Launchpad，先读现有 [vphone-guest-control](../vphone-guest-control/SKILL.md)；本脚本服务于现有独立 CLI / vphone-ws 环境，不要求为了安装应用更换管理器。

## 执行

1. 核对目标 VM、绑定的 bundle 版本及用户提供的本机 IPA/TIPA。先 `unzip -t` 验证归档，查看 `Payload/*.app/Info.plist` 的 bundle ID 与版本；记录来源。没有安装包时明确缺少输入，不从不明站点抓包，不把 Safari 网页当作 App 安装成功。
2. 复用已运行 VM 的 loopback HTTP API 和 token。没有监听时，先说明需要正常重启该 VM；不得杀掉别的 VM。按实际绑定的 2.x CLI 启动：

   ```sh
   # 固定 token 用私有文件保存，勿打印或放进命令行参数；日志同样设 600。
   VPHONE_API_TOKEN="$(cat /绝对路径/token)" /实际绑定的/VPhone.bundle/Contents/MacOS/vphone-cli \
     vm launch 目标名称 --library-root /实际机器库 --api-listen 127.0.0.1:18761
   ```

   token 由 `openssl rand -hex 32` 生成，文件权限 600。每台 VM 使用不同端口。若启动器已有监听，使用其真实地址与 token，不启动重复实例。不要给新 CLI 传旧版 `--variant`。首次 CFW 后，health 可能在苹果进度条期间已返回成功；它不证明桌面或 LaunchServices 已就绪。先等待桌面与 Setup 完成，再提交安装，减少与系统首次迁移重叠。若包已安装但启动暂未就绪，先读回状态，随后单独用 `apps.launch`、进程读回和截图验证，不重复安装同一包。
3. 用此技能目录下的脚本（可从任意 cwd 调用）：

   ```sh
   /本技能目录/scripts/install-app.sh --api-url http://127.0.0.1:18761 \
     --token-file /绝对路径/token --launch '/绝对路径/App.ipa'
   ```

   脚本检查连接，以 HTTP 流式上传，再以现有 WebSocket 客户端等待原生安装结果（上限 10 分钟，避免大型 IPA 超过 HTTP RPC 的 130 秒上限），读回用户应用列表；`--launch` 再验证启动后连续 20 秒存在。安装同 bundle ID 可能替换已有应用；需要保留数据时先核对授权与备份。失败会非零退出，不自动换安装路径、重装、重刷固件或修改补丁。超时不会取消客体正在执行的安装；先检查应用、临时目录和日志，不能据超时直接再次提交。
4. 查看真实前台截图/窗口并检查用户要求的核心功能。进程存活只证明短时启动，不能代表登录、联网、广告或业务功能成功。遇到退出，用 `logs.crashes {bundle_id}`、`logs.crash {path}` 取原始报告，区分 watchdog、签名、EXC_GUARD 等原因，保留安装成功与启动失败两个事实。

新版 `apps.install` 与窗口菜单共用签名和容器注册流程，RPC 执行结束时会删除上传的 IPA（成功或失败均如此）；若上传后尚未调用安装、或连接中断，先检查本轮准确路径是否残留。安装仍在执行时不要删除其输入。它绕过 installd，不能用于证明 Apple 安装服务的 hooks 生效。确需测试 installd 时按仓库规范使用 `ideviceinstaller -u <UDID> install <ipa>`；不要用会对 vphone 超时的 `devicectl`。

另有原生 `boot --config ... --install-ipa ...`，适合开机时安装，但日志仍须读回验证，不能与正在运行的实例同时启动。

## 维护和验证

脚本依赖本仓库源码与 Mac Xcode Command Line Tools，不能作为独立 VPhone.bundle 产品分发。修改后先运行 `scripts/install-app.sh --self-test`，再对授权测试 VM 实装一个已知 IPA。官方 API 参考：[vphoned HTTP API](https://github.com/Lakr233/vphone-cli/blob/main/Research/vphoned_http_api.md)；主分支可能比本机新，以本机代码和真实响应为准。
