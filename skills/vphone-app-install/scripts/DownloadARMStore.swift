import Foundation

@main struct Main {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-test"] {
            do {
                let valid = ["--app-id", "389801252", "--bundle-id", "com.burbn.instagram", "--version", "452.0.0"]
                let options = try Options(valid)
                guard !options.download, options.country == "us" else { throw fail("默认只读测试失败") }
                let client = try Client(options)
                let request = client.request(URL(string: client.base + "/prepare")!, method: "POST")
                guard request.httpMethod == "POST",
                      request.value(forHTTPHeaderField: "Referer") == "https://armconverter.com/store/us/389801252",
                      request.value(forHTTPHeaderField: "Cookie") == nil else { throw fail("请求上下文测试失败") }
                for args in [valid + ["--download"], valid + ["--timeout", "nan"], valid + ["--version", "x"],
                             ["--app-id", "../1", "--bundle-id", "com.test.app", "--version", "1"],
                             valid + ["--output", "relative.ipa"]] {
                    var rejected = false
                    do { _ = try Options(args) } catch { rejected = true }
                    guard rejected else { throw fail("参数边界测试失败") }
                }
                print("Self-test passed: read-only defaults, required download inputs, path/ID/timeout validation")
                return
            } catch { fputs("Self-test failed\n", stderr); exit(1) }
        }
        if args.isEmpty || args == ["--help"] {
            print("download-armstore.sh --app-id ID --bundle-id ID --version VERSION [--country us] [--cookie-file /private/cookie.txt] [--download --output /path/App.ipa] [--historical] [--timeout 600]\n默认只查询；download 会消耗网站配额。Cookie 文件只放请求头值，权限 0600。")
            return
        }
        do { try await Client(Options(args)).run() }
        catch let error as DownloadError { fputs(error.message + "\n", stderr); exit(1) }
        catch let error as URLError { fputs("网络请求失败（URL 错误码 \(error.code.rawValue)）；未输出含凭据的 URL\n", stderr); exit(1) }
        catch { fputs("请求或文件操作失败；未输出可能含凭据的底层错误，请检查网络及文件权限\n", stderr); exit(1) }
    }
}
