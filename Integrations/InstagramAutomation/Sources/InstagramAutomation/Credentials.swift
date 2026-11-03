import Foundation
import Security
import Darwin
#if VPHONE_CUSTOM_INSTAGRAM_AUTOMATION
enum Credentials {
    static func filePassword(_ account: String, directory: URL) throws -> String? {
        guard account.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else {
            throw Failure("测试账号格式无效")
        }
        let file = directory.appendingPathComponent(account + ".password")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        var text = try String(contentsOf: file, encoding: .utf8)
        if text.hasSuffix("\r\n") { text.removeLast() }
        else if text.hasSuffix("\n") { text.removeLast() }
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }) else {
            throw Failure("本机测试密码文件必须包含一行非空密码")
        }
        return text
    }
    static func read(_ account: String) throws -> String {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/vphone-social-tests")
        if let password = try filePassword(account, directory: directory) { return password }
        var value: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "vphone-instagram-test", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw Failure("钥匙串凭据不可用；先运行 set-password ACCOUNT")
        }
        return text
    }
    static func store(_ account: String) throws {
        let text = try hiddenInput("密码（隐藏输入）: ")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "vphone-instagram-test", kSecAttrAccount as String: account]
        let attributes = [kSecValueData as String: Data(text.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw Failure("无法保存钥匙串")
            }
        } else if status != errSecSuccess { throw Failure("无法更新钥匙串") }
        print("凭据已保存至本机钥匙串")
    }
    static func hiddenInput(_ prompt: String) throws -> String {
        FileHandle.standardError.write(Data(prompt.utf8))
        var original = termios()
        let terminal = isatty(STDIN_FILENO) == 1
        if terminal {
            guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw Failure("无法保护输入") }
            var hidden = original
            hidden.c_lflag &= ~tcflag_t(ECHO)
            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden) == 0 else { throw Failure("无法关闭回显") }
        }
        defer { if terminal { tcsetattr(STDIN_FILENO, TCSAFLUSH, &original); print("") } }
        guard let text = readLine(), !text.isEmpty else { throw Failure("未输入凭据") }
        return text
    }
}
#endif
