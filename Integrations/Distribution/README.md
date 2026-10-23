# VPhoneDistribution

Launchpad 首次使用、GitHub Releases 分发与版本目录的独立模块。依赖 Foundation/CryptoKit；不修改 Core/CLI/guest 协议。

- `Sources/VPhoneDistribution`：目录校验、版本记录、分片下载和导入流程。
- `Sources/DistributionPublisher`：发布附件生成/校验工具，仅开发机器运行。
- `scripts`：App 内部开发签名／公证打包、已有 Core 归档、Draft Release 上传。
- `Tests`：隔离临时目录回归，无用户 VM 或真实网络副作用。

详细流程见 [分发指南](../../Documents/Guides/launchpad-distribution.md)。

```sh
swift test --package-path Integrations/Distribution
```
