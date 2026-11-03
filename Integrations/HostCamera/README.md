# 宿主实时摄像头实验

2026-10-28：经用户明确确认，已完成独立采集模块和最小静态 Hook 的源码接入。
实验默认关闭，所有本地产物均为 **test**。随后经用户授权部署并进行维护验收：
已安装配套 Launchpad，仅测试机 `4-20261023` 绑定摄像头测试 Core；原运行实例已恢复。
软件模拟与 VM 系统相机测试通过，尚无 USB 实物采集或目标第三方 APP 的验收结论。
详见[部署验收记录](../../Research/Host/host_camera_deployment_20261028.md)。

## 实现与边界

`VPhoneHostCamera/` 的三个采集／授权／帧处理源文件只依赖系统 AVFoundation、
Core Image、Core Video 和 Foundation。`Adapters/` 是唯一依赖现有 VM 帧协议和
菜单类型的位置；不依赖 CLI、guest 或 Launchpad 内部模型。全部实现受
`#if VPHONE_EXPERIMENTAL_HOST_CAMERA` 控制，默认不定义。

- `VPhoneHostCameraCapture` 枚举内置／外置视频设备，按设备 ID 选择；只有明确调用
  `start(deviceID:)` 才申请权限、启动采集。设备列表不触发授权或采集。
- 权限拒绝、系统限制、缺少用途说明、设备不存在、输入／输出不可用、启动失败
  均返回具体错误。权限弹窗由 macOS 处理，不读取 TCC 数据库、不绕过权限。
- 会话配置、启停、错误和采集回调串行执行，不在主线程启动阻塞式采集。
- 单槽帧缓冲限制内存；帧变更选择、停止及设备断开后失效。旧权限请求、旧设备
  回调不能停止或覆盖新选择；超过 500 ms 的帧不再供消费。
- 输出为 1280×720 BGRA、5120 字节行宽，保持比例并填充黑边；可适配既有
  `VPhoneFrameProducer`，继续使用原 VSOCK 1338。各实例持有自己的采集对象。
- 运行错误、被系统中断或设备断开时停止并报告失败；可以重新选择设备或点击
  Start Streaming 重试。手动停止、切换来源、关闭 VM 和通道断开都会停止采集。
- 通道重连仅恢复断线前仍在推流的实时来源；仅选择设备不会在连接后自行打开摄像头。
  不新增后台自启动、配置持久化、网络服务或音频采集。

## 最小产品接入与升级影响

原 `VPhoneFrameProducer` 只有 `nextFrame()`；没有实时来源注册、采集启停和权限
配置。Launchpad 的 CLI／RPC 也没有提供实时摄像头帧输入，所以仅新增 Launchpad
页面不能完成实时画面传输。不能把普通文件上传或循环改写共享内存作为替代协议。

采用静态 Hook／条件组装，不使用 method swizzling、DYLD 注入或系统扩展：

| 范围 | 最小必要改动 |
| --- | --- |
| `VPhoneCameraServer.swift` | 受宏控制的实时来源接入与采集生命周期 Hook；既有帧编码、VSOCK 和重连逻辑继续复用 |
| `VPhoneMenuCamera.swift` | 宏内插入设备来源、错误／状态及选择检查；具体设备处理放独立适配文件 |
| `VPhoneVirtualization.xcodeproj` | 在既有 kit target 显式登记五个独立源文件；kit 和 bundle target 引用同一配置；打包输入声明生成后的 Info.plist，确保注入用途说明后签名不会被后续处理覆盖 |
| Core 的 `StageBundle.sh`／用途说明与签名资源 | 仅在宏启用的产物中配置必要摄像头用途说明和权限；关闭后不得遗留权限或注册 |
| Launchpad 的构建／签名配置 | Launchpad 是 VM 的责任进程，按同一功能开关为其配置摄像头用途说明与权限，关闭后恢复原签名权限 |

旧 Core 没有该菜单，原操作不受影响。不因可选摄像头扩大到整个 VM 的启动拒绝，
不自动升级已有实例。Launchpad 启动的 VM 需要配套启用摄像头的 App 和 Core；
App 的签名和用途说明也必须有效。权限拒绝错误包含这一提示。旧 App 配新 Core 的
实际 TCC 行为尚未现场验证，不能假定只重建 Core 就足够。

不修改 CLI 参数／输出、guest、固件、DSC、内核、helper 协议、VM manifest 或
`launchpad.json` 的格式。不更改官方基线版本；新测试包继续使用真实基线及内容哈希身份。
构建不等于安装；本次授权部署只改变测试机的 Core 绑定字段，保留原 Core 和用户镜像。

## 编译开关与回退

- 宏：`VPHONE_EXPERIMENTAL_HOST_CAMERA`，默认关闭；不借用 `DEBUG`。
- 配置入口：`Configuration/HostCamera.xcconfig`，`VPHONE_HOST_CAMERA` 默认为空。
  VPhone 的 kit／bundle target 实际引用此文件；Launchpad 的既有 app xcconfig
  include 同一文件，并将条件传给 Swift 和 Info.plist 预处理。
- 开启参数：`VPHONE_HOST_CAMERA=VPHONE_EXPERIMENTAL_HOST_CAMERA`。Swift 关闭方式为
  清空 `VPHONE_HOST_CAMERA`，不能设置 `VPHONE_EXPERIMENTAL_HOST_CAMERA=0`。
- 同一开关控制源码、菜单、采集生命周期和权限资源。Core 打包及 Launchpad 签名
  复用 `Build/HostCameraBuild.zsh`，从产物的 `VPhoneHostCameraEnabled` 标记生成
  临时 entitlements；不修改原基础权限文件，不给 helper／CLI／launcher 添加权限。
  Launchpad 签名从已构建产物读取开关，不依赖签名时的环境变量。
- 关闭并重建、重新签名后恢复原测试画面／视频文件路径，无实时入口及采集代码。
  停用当前运行的采集仍需调用 `stop()` 或退出对应进程；修改宏不会改变旧进程。
- 完整删除时移除本目录、上述源文件登记与配置引用、server／menu 条件 Hook、
  StageBundle／SignLaunchpad 的条件权限调用及 Info.plist 条件块／预处理配置。
  不需要重刷固件；关闭宏不会撤销 macOS 已保存的权限、清除 guest 共享帧，或
  删除 APP 已经保存的照片／录像。

显式开启构建（源码默认值保持关闭）：

```zsh
xcodebuild -workspace VPhone.xcworkspace -scheme VPhone -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeBundle -jobs 4 \
  VPHONE_HOST_CAMERA=VPHONE_EXPERIMENTAL_HOST_CAMERA build
xcodebuild -project VPhoneLaunchpad/VPhoneLaunchpad.xcodeproj -scheme VPhoneLaunchpad \
  -configuration Debug -derivedDataPath .build/LaunchpadDecodo -jobs 4 \
  VPHONE_HOST_CAMERA=VPHONE_EXPERIMENTAL_HOST_CAMERA build
```

关闭时删除两个命令中的该赋值或显式传 `VPHONE_HOST_CAMERA=` 后重建；App 还需按
既有签名流程重新签名。构建不等于安装；本次本机部署使用原开发签名身份，未做
Developer ID／公证分发或线上发布。

USB 接入后的验收入口：VM 窗口的 Features → Source: Host Camera → 设备 → Start Streaming，
按 macOS 提示授权，然后依次检查系统相机和目标 APP；Stop Streaming 停止实时采集。

## 已执行验证

```zsh
zsh Integrations/HostCamera/test.zsh
```

测试使用实际模块源码、Swift 6 严格并发和 macOS 15 deployment target，warnings
作为错误。先编译关闭态并检查符号中没有 `VPhoneHostCamera`／`AVCapture`，再显式
启用宏编译运行测试。测试不打开摄像头、不弹权限提示、不启动 VM，也没有测试服务器。

覆盖权限决策、缺用途说明、单帧上限、旧帧过期、停止后迟到回调、新旧选择竞争、
实例缓冲隔离，以及真实 CVPixelBuffer → Core Image → BGRA 像素、方向与横竖画面
黑边。通过实际 server／menu 源码检查开启／关闭接入；仅把无关 VM 面板的 owner
替换为测试夹具。延迟采集夹具覆盖立即停止、迟到启动、重复启动、迟到错误、失败
重试与释放；生产默认始终使用真实 AVFoundation。颜色图只在测试中创建。

权限测试还签名隔离的 Mach-O 夹具，验证开关、启用后停用的权限清理，并保留原有
麦克风／位置权限。它不代表 Launchpad 的 Developer ID 签名已完成。

完整构建与产物检查已通过：

| 检查 | 结果 |
| --- | --- |
| 独立模块与实际菜单／帧源接入的双态测试 | 通过，含取消、重试、帧映射与状态隔离 |
| Core 完整构建，关闭 → 开启 → 关闭 | 均通过；开启时包含采集代码／用途说明／摄像头权限，最终关闭态三者均无 |
| Core 开启／关闭产物 strict deep 签名验证 | 通过；最终宏仍默认关闭，版本声明未改 |
| Launchpad 完整构建，关闭 → 开启 → 关闭 | 均通过；开启态标记存在，最终关闭态标记和用途说明均无 |
| 签名夹具与权限生成／清理 | 通过；原麦克风／位置权限保留 |

日志和签名／Info.plist／符号快照在 `.build/host-camera-tests/`，不提交。
上述双态构建后，部署阶段又显式重建了开启态；源码默认值仍关闭。
新增纯测试输入夹具经实际渲染器与 producer 连续处理 60 帧 720p 动态画面，并覆盖
模拟拔插／重连、旧帧撤回与权限拒绝。生产默认仍为真实 AVFoundation，不包含模拟源。
真实 VM 使用既有测试图案完成系统相机预览与 JPEG 保存，尺寸为 1280×720。
模拟测试与此 VM 测试是两项独立验证，不代表 USB 采集已经端到端通过。

尚未验证：Launchpad 的 Developer ID／公证分发签名、真实 USB 摄像头采集和系统
授权、物理拔插／占用、多 VM 同时使用同一物理设备及目标第三方 APP。
不能用模块测试或 `Camera server: connected` 代替。摄像头图像不提供 TrueDepth／Face ID。

官方参考（2026-10-28 核对）：
[媒体采集授权](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)、
[Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)、
[采集会话](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)。
