# Launchpad 修订 8 升级测试发行

- 用户授权：再发布一个新修订供 r7 客户端升级测试；本机保留 r7，由用户操作更新。
- 官方基线保持 2.13.4（7f55bebdcbed913541928b9c4b1c1ca79abc0822），仅 App 发行修订增加到 8，功能沿用 r7。
- Core 保持 2.13.4-local.666ac4da，不改 VM 绑定、guest、Helper 或本地镜像目录。
- 旧 release workflow 对 launchpad-* 跳过两个上游打包任务，避免发布后又附加未登记、未正式签名的 ZIP。其它发行标签保持原行为。
- 发布目录仍只允许签名 App DMG、必要 Core ZIP、catalog；images / previousTags 为空，禁止上传镜像与分片。
- 验证范围：Release 构建/签名、发布目录校验、分发单元测试和线上 App/Core 实际下载校验。用户实际执行 r7→r8 的安装重启验收，未提前代测该步骤。
