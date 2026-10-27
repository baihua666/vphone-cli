# Launchpad 修订 11 公开分发

在已向用户说明本地修订 11 内置真实网站账号和 ISP 凭据、下载者可提取、此前仅线下交付后，用户明确要求“上传版本”。本次按现有 GitHub Releases 渠道发布该已交付的确切安装包，不重新编译或替换包内容，不将账号值提交源码。

App 官方基线 2.13.4、修订 11，保留公开 r10 的 ARM Store 更新及其原有预设，增加 Decodo 免输入默认配置。App 源码为 `f7dc4781b577addee8a0711abe1116473b8272af`；构建中使用的私有账号输入仍不入库。此次发行源码提交仅新增发布工具的精确包审批与本记录，App 和 Core 内容沿用已验证产物。

授权的 DMG SHA-256 为 `1ef6ef7397e7bfebb97beccc54956f833c87e9b2d24089e8a40979cdfaeeaf80`。publisher 默认仍拒绝含账号的安装包；只有显式 `VPHONE_APPROVED_ACCOUNT_DMG_SHA256` 与被验证的 DMG 哈希完全相同才接受，不能授权另一个未来包。镜像和分片禁止上传的规则不变。

发布只含该 App DMG、已验证 Core `2.13.4-local.9e7ad669` ZIP 及发行清单；`images=[]`、`previousTags=[]`。保留历史发行，不替换本机 App、不安装 Core、不变更 VM 或代理。准备、草稿核对、公开 metadata 和实际下载证据放在 `.build/r11-evidence/`；草稿从认证发行列表获取 ID，依赖步骤使用 `set -euo pipefail`，避免草稿 tag API 404 后继续公开。
