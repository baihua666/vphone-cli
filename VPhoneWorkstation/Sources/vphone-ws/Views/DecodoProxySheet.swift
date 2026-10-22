import SwiftUI
import VPhoneWSCore

struct DecodoProxySheet: View {
    struct Input {
        let username: String
        let password: String
        let zip: String
    }
    var initialZIP: String
    var onApply: (Input) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var zip = ""
    @State private var configurationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置 Decodo Residential").font(.headline)
            if let configurationMessage { Text(configurationMessage).font(.caption).foregroundStyle(.secondary) }
            Form {
                TextField("美国 ZIP 邮编", text: $zip, prompt: Text("五位数字，例如 02108"))
                TextField("代理用户名", text: $username, prompt: Text("原始用户名，不含地区和会话参数"))
                SecureField("代理密码", text: $password)
            }
            Text("填写 Decodo 控制台的代理认证信息，不是网站登录密码。需要已开通的 Residential 流量；此处不会购买或注册账号。")
                .font(.caption).foregroundStyle(.secondary)
            Text("为此虚拟机创建独立的五分钟 IP Lock 会话，并立即应用和检测出口。ZIP 是区域筛选，不保证具体街道距离；节点离线时可能连接失败。认证信息保存在本机 Clash 配置中。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存、应用并检测") {
                    let input = Input(username: username, password: password, zip: zip)
                    password = ""
                    dismiss()
                    onApply(input)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
                    || zip.range(of: #"^[0-9]{5}$"#, options: .regularExpression) == nil)
            }
        }
        .padding(20).frame(width: 480)
        .onAppear {
            zip = initialZIP
            do {
                if let configuration = try DecodoLocalConfiguration.load() {
                    username = configuration.username
                    password = configuration.password
                    if zip.isEmpty { zip = configuration.zip }
                    configurationMessage = "已读取本机配置，账号密码已填入。确认 ZIP 后可直接保存并检测。"
                }
            } catch { configurationMessage = error.localizedDescription }
        }
    }
}
