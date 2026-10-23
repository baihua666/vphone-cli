import Foundation
import Security
import CommonCrypto
import SQLite3

// Explicitly scoped to the ARM Store session: no history, passwords or other-site cookies.
@main struct ExportARMStoreSession {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 4, args[0] == "--profile", args[2] == "--output",
                  args[1].hasPrefix("/"), args[3].hasPrefix("/") else {
                throw error("用法：export-armstore-session.sh --profile /Chrome/Default --output /private/cookie.txt")
            }
            let data = try session(profile: args[1])
            let output = URL(fileURLWithPath: args[3])
            let temporary = output.deletingLastPathComponent().appendingPathComponent(".session-" + UUID().uuidString)
            let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { throw error("无法创建私有会话文件") }
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? file.close(); try? FileManager.default.removeItem(at: temporary) }
            try file.write(contentsOf: Data(("session=" + data + "\n").utf8))
            try file.synchronize()
            guard rename(temporary.path, output.path) == 0 else { throw error("无法保存会话文件") }
            print("已保存 ARM Store session（0600）；未输出凭据")
        } catch let e as NSError where e.domain == "ARMStoreSession" {
            FileHandle.standardError.write(Data((e.localizedDescription + "\n").utf8)); exit(1)
        } catch {
            FileHandle.standardError.write(Data("会话导出失败；未输出敏感底层信息\n".utf8)); exit(1)
        }
    }
    static func error(_ text: String) -> NSError {
        NSError(domain: "ARMStoreSession", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    static func session(profile: String) throws -> String {
        var database: OpaquePointer?
        guard sqlite3_open_v2(profile + "/Cookies", &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw error("无法只读打开指定 Chrome Cookie 数据库") }
        defer { sqlite3_close(database) }
        var query: OpaquePointer?
        let sql = "SELECT encrypted_value,expires_utc FROM cookies WHERE host_key='armconverter.com' AND name='session' AND path='/'"
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK else { throw error("Cookie 数据库结构不受支持") }
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW, let bytes = sqlite3_column_blob(query, 0) else { throw error("指定配置尚未登录 ARM Store") }
        let encrypted = Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
        let expiry = sqlite3_column_int64(query, 1)
        guard expiry == 0 || Double(expiry) / 1_000_000 - 11_644_473_600 > Date().timeIntervalSince1970 else { throw error("ARM Store 会话已过期，请正常登录") }
        guard encrypted.starts(with: Data("v10".utf8)) else { throw error("当前 Chrome 加密格式不受支持") }
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "Chrome Safe Storage",
            kSecAttrAccount: "Chrome", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let password = item as? Data else { throw error("钥匙串未授权或密钥不可用；未读取会话明文") }
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let derived = password.withUnsafeBytes { p in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.bindMemory(to: Int8.self).baseAddress, password.count,
                                salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        guard derived == kCCSuccess else { throw error("密钥派生失败") }
        let ciphertext = Data(encrypted.dropFirst(3)), iv = [UInt8](repeating: 32, count: 16)
        var decoded = [UInt8](repeating: 0, count: ciphertext.count + 16), count = 0
        let capacity = decoded.count
        let result = ciphertext.withUnsafeBytes { p in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    key, key.count, iv, p.baseAddress, ciphertext.count, &decoded, capacity, &count)
        }
        guard result == kCCSuccess else { throw error("会话解密失败") }
        let host = Data("armconverter.com".utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = host.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(host.count), &digest) }
        var plaintext = Data(decoded.prefix(count))
        if plaintext.starts(with: digest) { plaintext.removeFirst(digest.count) }
        guard let value = String(data: plaintext, encoding: .utf8), !value.isEmpty,
              value.utf8.allSatisfy({ $0 > 32 && $0 < 127 && $0 != 59 }) else { throw error("会话格式或站点绑定校验失败") }
        return value
    }
}
