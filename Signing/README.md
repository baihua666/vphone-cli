# Launchpad 内部测试签名

`LocalTest/launchpad-development.p12` 保存主 APP 当前开发签名证书及私钥，
导入密码位于 `LocalTest/password.txt`。两者一起提供签名能力，仅用于获授权的内部测试。
此目录不包含钥匙串中的其它身份，也不包含 Developer ID 分发或公证凭据。

## 另一台 Mac

1. 安装 Xcode，导入 `LocalTest/launchpad-development.p12` 到登录钥匙串，
   在系统提示中输入 `LocalTest/password.txt` 内的密码。
2. 在本机创建 `VPhoneLaunchpad/Configuration/Developer.xcconfig`，设置
   `VPHONE_LAUNCHPAD_TEAM` 为导入证书对应的 Team ID。该文件继续由 Git 忽略，
   不提交实际 Team ID。不要将证书名称括号中的个人标识当作 Team ID。
3. 按工程现有流程构建 Launchpad，然后从仓库根目录签名：

   ```zsh
   zsh VPhoneLaunchpad/Build/SignLaunchpad.sh \
     /完整路径/vphone-launchpad.app \
     'Apple Development: tubao1985@163.com (29SHL9856B)'
   ```

签名脚本会处理 helper、CLI、launcher 与主 APP，并验证签名和权限。
构建时使用的 Team ID 必须与签名身份一致，否则 helper 校验不能通过。
本开发签名不等于 Developer ID 公证发布；Windows 不能直接执行此 Xcode 构建流程。
