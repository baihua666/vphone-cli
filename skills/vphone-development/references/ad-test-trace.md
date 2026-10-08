# VPHONE 测试广告操作与后台时间核对

使用 `scripts/ad_test_trace.py`，依赖 Python 3.9+、Xcode/Swift（自动定位按钮时）、`idevicesyslog` 和运行中的 VPHONE 控制 socket。不修改 IPA、SDK 或 VPHONE 生产源码。

## 日常快捷入口

优先使用二次封装，省去设备 ID、输出目录、广告位等重复参数：

```zsh
./scripts/ad_test_trace.sh                 # 激励广告；确认后执行一次
./scripts/ad_test_trace.sh interstitial    # 插屏广告；确认后执行一次
./scripts/ad_test_trace.sh --dry-run       # 只预览，不执行
./scripts/ad_test_trace.sh --capture-only  # 仅采集人工操作
```

默认使用项目 `vm`、Orblino App/广告位、UTC 时区、45 秒采集。匹配 VM 的 `udid-prediction.txt` 与连接设备列表，不因同时连接真机而取错设备。结果写入 `.build/validation/ad-tests/时间-随机ID-格式/`，运行前会打印完整路径。

默认只需确认一次测试前置条件，输入 `y` 开始；已检查测试设备和页面状态时，可用 `./scripts/ad_test_trace.sh rewarded --yes`。`--yes` 只省略终端确认，不会注册测试设备或修改授权。另一 VM 用 `--vm /absolute/path`；后台时区不同用 `--timezone Asia/Shanghai`。完整选项见 `--help`，复杂排障仍可用下方 Python 入口。

## 操作前

1. 在 Pangle 登记当前 guest IDFA 为测试设备，等待生效；VM 导入或重建后重新核对身份。
2. 打开 Orblino Debug 应用的广告测试页，选择“测试设备验证”，确认测试设备开关及既有隐私选择。脚本不会配置平台测试设备、切换验证模式或修改隐私设置。
3. 将“加载并展示激励广告”或“加载并展示插屏广告”滚动至完全可见，停止操作页面。广告 App ID、广告位填写对应页面值；脚本把这些值作为操作员提供的元数据，不声称已从 SDK 请求中读取。
4. 用 `idevice_id -l` 获取当前 UDID。同一设备不要同时运行多个采集/操作脚本；先停止自己的旧采集器，不终止无关 VM。

## 一次自动请求

在仓库根目录运行，替换 UDID 和唯一输出目录：

```zsh
python3 scripts/ad_test_trace.py \
  --socket vm/vphone.sock \
  --udid '<当前UDID>' \
  --output .build/validation/ad-test-001 \
  --request --test-device-confirmed \
  --format rewarded --app-id 8895377 --placement-id 983634549 \
  --report-timezone UTC --seconds 45
```

插屏使用 `--format interstitial --placement-id 983639115`，先让插屏按钮可见。`--seconds` 是注入操作后的采集时长，不是开始时间或循环间隔。每次只操作一次；无填充不自动重试。需要多次独立样本时，重新检查页面和前置条件并使用新输出目录。

自动模式从完整分辨率截图中，用 macOS Vision **精确识别测试面板的加载按钮**，连续两次确认位置稳定，再按 config.plist 的 guest 分辨率注入触摸。找不到唯一按钮、页面移动或日志设备连接失败，都不发起操作。不点击广告素材、下载/跳转按钮，不自动关闭广告。OCR 和编译可能耗时，以 `ui_request_sent` 时间为实际脚本操作时间，而非进程启动时间。

`--test-device-confirmed` 是操作者对已检查平台配置和当前页面的明确声明；不是服务端测试状态探测。脚本只在日志中看到测试设备模式、`canRun=true`、`attached=true`、非 token 请求时计为应用请求开始；不匹配即停止后续动作。此检查发生在操作后，不能代替操作前的测试设备登记检查。

只采集自己人工操作的证据：去掉 `--request --test-device-confirmed`。此模式不注入任何触摸。调试失败会保留证据、清理自己创建的日志进程；输出目录已存在时拒绝覆盖。

## 产物与时间口径

- `run.json`：参数、设备、操作者提供的 App/广告位、报表时区。
- `events.jsonl` / `events.csv`：UTC、报表时区时间、小时桶、单调时钟耗时、分类、原始日志。多行 SDK 错误的续行也保留。
- `hours.csv`：每个报表小时的应用请求开始数，以及建议查询时间。
- `summary.json`：请求开始、加载成功并尝试展示、失败、奖励回调；曝光和点击没有可靠埋点时为 null，不伪造为 0。
- `before.jpg`、`before-tap.png`、`after.jpg` 等截图：证据；失败时可能只有部分文件。

UTC/报表时间是 **Mac 收到日志的时间**，原始 guest 时间保留在 message；不是服务端入库时间。单调时钟可计算按钮操作到日志回调的观测耗时，不能称为精确服务器请求耗时。小时边界附近需结合原始日志检查前后两个桶。

## 后台核对流程

1. 操作前保存后台基线：同一 App、同一广告位、小时粒度、时区以及请求/返回/曝光/点击/收益。保存导出文件或截图，标记获取时间。测试窗口内若有其他设备流量，后续差值无法单独归因于本次操作。
2. 运行脚本，先确认 `app_request_starts=1`。`ui_command_ack` 只表示触摸注入被接受；`load_success_show_attempt` 只表示应用开始展示，不证明曝光已回传。
3. 后台时区要与 `--report-timezone` 完全一致。例如北京时间 15:xx 在 UTC 报表对应当天 07:00 小时桶。
4. 按官方文档，小时报表 H 时可看 H−5 及以前的数据。脚本保守建议在目标小时结束后再等五小时核对；这是建议时间，不保证平台在那一刻完成更新。不要因为立即刷新未变化就判为丢数据。
5. 当前后台请求/返回指标标有“不含美国”，核对前须确认地区口径；不要把这些指标当全球总请求。刷新页面可能丢失应用筛选，刷新后重核筛选。等待数据成熟后，用完全相同筛选保存后值，与基线和 `hours.csv` 并排比较。后台请求数减基线是聚合差值，不能直接等同应用调用数：SDK 请求/重试口径、其他流量及测试流量统计范围都可能不同。
6. 结论区分“时间桶一致”“聚合数量一致”和“单请求归因已确认”。当前测试面板日志没有贯通后台的 request ID，最多支持前两项，不能证明每次操作与后台记录一一对应。

官方说明测试设备会返回测试广告，测试状态广告位的请求不计收益；但这里没有证据证明测试设备所有事件一定进入普通报表。先确认后台是否提供测试诊断或测试流量统计。无增长时不能切换正式广告刷量来替代核对。正式收益、点击和反作弊识别不属于这个脚本的验收目标。

参考：[测试广告](https://www.pangleglobal.com/knowledge/test-ads)、[报表生成时间](https://www.pangleglobal.com/kr/knowledge/view-data-report)。
