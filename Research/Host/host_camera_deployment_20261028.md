# 宿主摄像头本机部署与模拟验收（2026-10-28）

用户已明确允许最小宿主源码接入，随后要求部署并测试；确认本机没有摄像头、目标为
USB 摄像头，允许维护期间停止实例，并要求结束后恢复原运行状态。本次不发布、不
上传镜像、不升级 guest／固件，不安装虚拟摄像头驱动或借用其它设备摄像头。

## 实际部署

源码宏 `VPHONE_EXPERIMENTAL_HOST_CAMERA` 默认关闭；本机测试产物显式开启。
Launchpad 官方基线仍为 2.13.4、helper 构建 21，使用原开发签名身份，属于本地 test。
已安装 `/Applications/vphone-launchpad.app`，严格深度验签通过；实际 App 主程序
SHA-256 为 `56eb809ec532004481ba25d0e41423eae3f6598a4d6eed9e8aeb7b7ac5423d9d`。
配套元数据和摄像头权限随启用构建生成，原 Decodo 私有资源完整保留。

为了避免完整新构建触发 guest 更新，测试 Core 从原安装包复制，仅替换
`Contents/MacOS/vphone-vm`，注入摄像头用途说明及测试元数据后重新封装签名。
原 CLI 和 guest-resources 保持原内容。Bundle admission、严格深度签名和真实安装均通过；
安装器按签名 seal 生成身份 `2.13.4-local.5591cc6b`，并保留原默认值。
只用既有 `vm set-bundle` 改测试机的 `bundle`，没有执行 `--update-environment`。

| 对象 | 维护前 | 结束时 |
| --- | --- | --- |
| `1-20261023` | 运行，Core `2.13.4-local.666ac4da` | 已恢复运行，原 Core 与绑定不变，vphoned 7 秒内应答 |
| `4-20261023` | 停止，Core `2.13.4-local.666ac4da` | 停止，测试 Core `2.13.4-local.5591cc6b` |
| 两台 guest 环境 | `2.13.4-local.666ac4da` | 均保持原版本 |
| 默认 Core | `2.13.4-local.666ac4da` | 不变 |
| 系统 Helper | ready，构建 21 | ready，构建 21；文件摘要与进程未替换 |

两台 `config.plist`、原 Core seal 校验一致；实例 1 的 `launchpad.json` 逐字节一致，
实例 4 的 sidecar 只有 `bundle` 字段变化。原 guest 与测试机最终环境报告中的
library 记录一致，vphoned 文件摘要仍为
`789c8a478d57359d9699ebb3241adf788916dcb998eae0e4839e4564c88ddbe2`。

## 验收结果与边界

| 检查 | 实际结果 |
| --- | --- |
| 宏关闭／开启／再关闭的完整 Core、Launchpad 构建 | 通过；关闭态无采集符号、入口、用途说明和新增摄像头权限 |
| Swift 6 严格并发模块与实际菜单／server Hook 测试 | 通过，含取消、迟到回调、重复启动、失败重试、实例隔离和来源释放 |
| 软件模拟输入 | 60 帧变化的 1280×720 BGRA，经实际渲染器和 producer 检验；模拟断开、重新连接、旧帧撤回、权限拒绝均通过 |
| 签名与权限 | 实际交付检查和签名夹具通过；停用清除新增权限，保留原麦克风／位置权限 |
| 已安装 VM 菜单 | 显示 Host Camera 来源；设备枚举不启动采集 |
| 真实 VM 相机链路 | 既有测试图案经 VSOCK 进入系统相机，完成可见预览和一次拍照 |
| 照片结果 | `/var/mobile/Media/DCIM/100APPLE/IMG_0001.JPG`，57,650 字节，1280×720；已拉取并查看图像 |
| 测试结束 | 来源关闭、推流停止、测试机正常停止，原运行实例恢复 |

软件输入夹具仅存在于测试，使用依赖注入，不加入生产菜单或生产采集路径。
它验证帧处理和生命周期，不模拟 macOS USB 驱动、真实 AVCaptureSession 或 TCC 弹窗。
VM 拍照使用既有测试图案，与软件夹具测试分开执行，不能合并声称真实 USB 端到端通过。

宿主为 Mac mini M4，未接 USB 摄像头；系统探测无物理摄像头，运行期菜单一度枚举到
Continuity Camera 的 iPhone 来源，但没有选择或启动它。未访问真实摄像头、未授予
新的系统摄像头权限，未测试第三方 APP、录像、实物热插拔、设备占用或多 VM 争用。
测试机自动锁定 RPC 返回永不；本次不以此替代全新镜像的完整初始化验收。

测试期间一次等待因实例已正常退出而超时，日志显示 guest 正常停止；未确立退出原因。
随后测试机单独重启成功，完成预览和拍照。调试读取启动日志时曾输出临时本地 API token；
对应进程已退出，后续日志按类别过滤，本记录不保存 token。

## USB 接入后的操作与回退

连接 USB 摄像头后启动 `4-20261023`，在 VM 的 Features → Source: Host Camera
选择该 USB 设备，再点 Start Streaming。首次按 macOS 提示给 Launchpad 摄像头权限；
检查系统相机动态预览、拍照，再检查目标 APP。摄像头授权、实际采集及拔插需单独验收。

原 App 完整备份在 `/Applications/.vphone-host-camera-20261028/previous.app`，
另有仓库忽略目录中的备份 `.build/host-camera-deploy/previous.app`。需要回退时，先
正常停止受影响 VM 并退出 Launchpad，将测试机重新绑定 `2.13.4-local.666ac4da`
（不带 guest 更新），再完整恢复原 App 并验签；原 Core 始终保留。
不需要重刷固件；回退不删除相机 APP 已保存的测试照片或系统已保存的授权。
源码回退方法见 [模块说明](../../Integrations/HostCamera/README.md)。

## 本机证据

不提交的 `.build/host-camera-deploy/` 包含开启构建／签名／安装日志、维护前后绑定、
配置与 helper 摘要、guest 环境报告、`simulation-tests.log`、`final-vms.json`、
`final-status.json`、`IMG_0001.JPG`；早期双态构建证据在 `.build/host-camera-tests/`。
这些是本地测试证据，不是可公开分发包；没有进行线上发布或上传虚拟机镜像。
