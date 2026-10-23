# ARM Store 下载适配器

2026-10-22 从站点自身公开前端源码分析，属于未公开承诺兼容性的内部接口，不是官方稳定 API SDK。

来源：
- https://armconverter.com/store/us/389801252
- https://armconverter.com/assets/index-DugM4joY.js
- https://armconverter.com/assets/AppDetails-pmOn2qdx.js
- https://armconverter.com/assets/LoginRequired-C_m_72_F.js

资源名会随部署改变。先从页面 script 引用重新定位，不依赖旧哈希永远可用。

## 已确认的前端协议

基础路径 `/decryptedappstore/download/{appId}/{bundleId}/{version}`。

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | 基础路径 `/info` | state、available、requestable、loginRequired、error |
| POST | 基础路径 `/schedule?country=us` | 申请任务，历史版本加 `&hist=true`；检查 success |
| GET | 基础路径 `/info` | enqueued / processing 时每三秒轮询 |
| POST | 基础路径 `/prepare` | ready 后获取临时 token，可能消耗账户配额 |
| GET | 基础路径 `?token=...` | 下载 IPA，可能重定向 CDN |
| POST | `/decryptedappstore/versions/{appId}/{currentVersion}?country=us` | 网页历史版本列表；本脚本暂未封装 |

版本参数优先级来自前端：versionId → shortVer → version → 当前商店 version。历史版本须显式指定 --historical。脚本不处理广告通行证，不改变会员身份，不绕过登录、付费限制、验证码或黑名单。不自动购买配额，也不重复提交失败任务。

## 命令

```sh
# 无登录或已有 Cookie 时只查询，不调用 schedule/prepare
./skills/vphone-app-install/scripts/download-armstore.sh \
  --app-id 389801252 --bundle-id com.burbn.instagram --version 452.0.0

# 登录会话文件内容：一行 Cookie 请求头值（不含 Cookie: 前缀）
# 文件需由用户提供，权限 0600；不要提交 Git 或粘贴到聊天。
./skills/vphone-app-install/scripts/download-armstore.sh \
  --app-id 389801252 --bundle-id com.burbn.instagram --version 452.0.0 \
  --cookie-file "$PWD/.local/armstore-cookie.txt" \
  --download --output "$HOME/Downloads/Instagram-452.0.0.ipa" --timeout 600
```

示例版本来自当时页面，执行前应核对目标版本。登录会话失效时需在浏览器正常重新登录，再更新私有 Cookie 文件；脚本不会读浏览器数据库或自动导出 Cookie。网站若要求验证码/浏览器挑战，应回到网页处理。

脚本为 zsh + Swift/Foundation，复用既有安装脚本的临时编译方式，不增加 Python、第三方运行依赖或 guest 工具。凭据不进入 argv；Cookie 仅发送给 armconverter.com，跨域 HTTPS 下载跳转剥离 Cookie/Authorization，API 跳转不跟随。错误不输出底层可能带 token 的 URL。

下载先写临时文件，校验 ZIP 完整性、唯一 Payload 主应用 Info.plist 和 bundle ID，成功后移动到目标路径；目标已存在则拒绝。版本号和包来源仍需人工核对，ZIP/标识校验不证明包未经修改。文件传输超时独立受 timeout 限制；排队超时不会取消服务端任务。

下载与安装分开：得到本机 IPA 后继续使用同目录 `install-app.sh`，避免下载请求直接触发软件执行。

## 验证范围

`download-armstore.sh --self-test` 检查默认只读、下载必要参数、ID/路径/超时边界。已进行未登录接口真实调用；没有提供 ARM Store Cookie，因此认证后的排队、prepare、CDN 下载和完整 IPA 校验仍待实测。不要将“脚本可编译”标为 Instagram 下载成功。

## 2026-10-22 登录自动化进一步调查

### 已观察事实

- 前端通过 `GET /decryptedappstore/user/info` 获取用户状态及服务端生成的 `login` 地址；页面直接跳转该地址，不提交 ARM Store 用户名密码。
- 无 Referer 的独立请求返回 403；带站内 Referer 的请求返回 anonymous 和 `/auth/login?next=...&direct=yes`。不能把所有 403 都当成密码错误。
- 实际 302 链：ARM Store `/auth/login` → `/auth/iosgods` → `https://iosgods.com/oauth/authorize/`，参数包含 response_type、client_id、redirect_uri、scope、state。必须保留该次登录的 Cookie 与 state，不硬编码复用授权码或 state。
- Chrome 中点击 Sign In 后，已有 iOSGods 会话自动完成登录并回到 ARM Store，页面显示已登录及剩余配额。这验证的是浏览器会话复用，没有输入账号密码，也没有验证首次密码登录。
- iOSGods 自身网页提供 `https://iosgods.com/login/`。本次普通 HTTP 客户端读取该登录页返回 `Just a moment...`，因此纯 HTTP 首次登录尚不能直接进行；没有绕过挑战，也没有提交猜测的登录字段。

### 推荐对业务暴露的边界（设计，尚未实现）

业务入口统一为 `install-from-store.sh --auth-file /absolute/auth.json --app-id ... --vm ...`。用户只维护一个授权文件，账号为 iOSGods 账号；模板是本目录 armstore-auth.example.json。真实文件放 `.local/`，0600，不进 Git。

内部顺序：
1. 获取按账号隔离的进程锁，避免两个安装同时登录/重复申请并消耗配额。
2. 验证私有会话缓存，已有效则直接使用；会话缓存由脚本维护，不要求用户另配 Cookie。
3. 无会话时沿当前服务端 OAuth 入口正常登录；账号密码只交给核对后的 iOSGods 登录域名。若已有身份提供商会话，直接完成 OAuth 回跳。
4. 遇到浏览器挑战、验证码、MFA 或新授权确认，返回 `AUTH_INTERACTION_REQUIRED`，保留可恢复会话，不反复提交密码。不能声称只有用户名密码便能消除这些服务端要求。
5. 获取应用元数据/目标版本 → 查询/申请/轮询 → 下载并校验 → 复用 install-app.sh → 读回安装状态。执行前解析目标 VM 的绑定 runtime 与现有 API，不能把两台 VM 的地址/token 混用。
6. 业务只接收成功结果或明确失败类型：认证交互、配额/权限、排队超时、下载校验失败、安装失败。安装超时不自动重新安装，先读回客体状态。

“一个授权文件”是一个用户配置入口，不等于运行时不允许产生会话缓存、下载缓存或验证日志。账号密码不写日志/argv；会话和临时下载 token 不提交 Git。

### 当前交付与仍缺验证

现有下载脚本及安装脚本可复用，但账号密码自动登录、自动会话导出、统一安装入口尚未实现。缺少用户提供的本机 iOSGods 授权文件，且普通 HTTP 登录页受到浏览器挑战，因此尚不能验证完整密码登录流程。不能用假成功登录适配器把流程拼成“已完成”。如需实现浏览器登录适配器，需在正常登录页面核对真实字段及跳转后，再使用授权文件完成首次实测；挑战必须正常处理。

## 2026-10-22 按钮行为复核

重新获取站点 `LoginRequired-C_m_72_F.js`，与先前缓存一致。`startDecrypt → maybeSchedule → maybeScheduleAsync` 先调用 `refreshState`；后者请求 `/info`，在 `ready` 时直接 POST `/prepare` 并将返回 token 放入下载链接。刷新页面后没有内存中的 token，因此按钮文案不能用来判断服务端是否已有包。仅凭再次显示 DECRYPT THIS APP 就要求不要点击，判断不准确。

当前 `maybeShowAdsAndThen` 实现直接调用传入函数；源码仍有广告通行证相关分支，不能据此承诺广告或配额规则永久不变。常规账户仍须通过服务端认证和额度检查。

下载脚本已实现 info / ready→prepare / 需要时 schedule 的链路，本轮补充站内 Referer，并通过请求构造自测。没有 Cookie 的实际 info 请求返回 HTTP 401，说明认证仍是阻塞。浏览器已登录不等于独立 URLSession 自动拥有 Cookie；当前本机没有 ARM Store Cookie 文件。统一配置安装入口已实现（见 SKILL.md），但自动会话获取和认证下载验收仍未完成。

## 2026-10-22 会话复用实测完成

新增 `ExportARMStoreSession.swift` / `export-armstore-session.sh`。当前用户明确授权复用浏览器会话，适配器仅查询指定 profile 下 host_key=armconverter.com、name=session、path=/ 的记录。通过 Security.framework 请求 Chrome Safe Storage；依据 Chromium 130 的 macOS v10 格式进行 PBKDF2/AES-CBC 解密，检查域名摘要（存在时）、过期时间和 Cookie 字符格式。凭据仅在内存和本机 0600 缓存中，不输出或进入 argv/Git。格式依据：https://github.com/chromium/chromium/blob/130.0.6723.58/components/os_crypt/sync/os_crypt_mac.mm 。该旧版源码仅解释 v10 兼容格式，不代表核实了当前 Chrome 全部实现。

真实结果：认证 info 返回 ready=true（state=ready）、available=true、requestable=false；prepare 和下载成功，ZIP 和 bundle ID 校验通过。第一次网络请求失败，重试完成，没有重新调用 schedule。网站 452.0.0 路径实际提供包内 452.0.1（build 1093431980）；统一入口严格校验发现差异，配置显式记录 packageVersion 后继续。仍不代表 IPA 为厂商原始签名或已通过 App 功能验收。
