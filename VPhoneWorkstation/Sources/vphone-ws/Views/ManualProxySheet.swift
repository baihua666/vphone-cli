import SwiftUI
import VPhoneWSCore

struct ManualProxySheet: View {
    let proxy: ClashProxyService
    let client: VPhoneCLIClient
    let machine: String
    let route: VMProxyRoute
    var onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = ""
    @State private var kind = VMManualProxy.Kind.http
    @State private var username = ""
    @State private var password = ""
    @State private var tls = false
    @State private var udp = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加已购代理 IP").font(.headline)
            Form {
                TextField("名称", text: $name, prompt: Text("例如：供应商 A · 美国 01"))
                Picker("协议", selection: $kind) {
                    Text("HTTP / HTTPS").tag(VMManualProxy.Kind.http)
                    Text("SOCKS5").tag(VMManualProxy.Kind.socks5)
                }
                TextField("服务器", text: $host, prompt: Text("IP 或域名，不带协议和端口"))
                TextField("端口", text: $port)
                TextField("用户名", text: $username)
                SecureField("密码", text: $password)
                Toggle("加密连接到代理（TLS）", isOn: $tls)
                if kind == .socks5 { Toggle("供应商支持 UDP 转发", isOn: $udp) }
            }
            .disabled(busy)
            Text("填写供应商提供的连接信息。TLS 需供应商入口支持；能访问 HTTPS 网站不代表入口支持 TLS。保存后在本实例出口中选择并应用。认证信息保存在本机 Clash 配置中。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("取消") { dismiss() }.disabled(busy)
                Button("保存到出口列表") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || name.isEmpty || host.isEmpty || port.isEmpty)
            }
        }
        .padding(20).frame(width: 480)
        .onChange(of: kind) { _, _ in udp = false }
    }

    private func save() {
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let endpoint = try VMManualProxy(name: name, host: host, port: Int(port) ?? 0, kind: kind,
                    username: username, password: password, tls: tls, udp: udp)
                try await proxy.addProxy(context: client.context(name: machine), proxy: endpoint, expected: route)
                password = ""
                onSaved(endpoint.name)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
