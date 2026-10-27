#if VPHONE_EXPERIMENTAL_NFC_NO_RF
import Foundation

struct VPhoneNFCCheckFailure: Error { let message: String }

final class VPhoneNFCChecks {
    private(set) var count = 0
    func check(_ condition: Bool, _ message: String, line: Int = #line) throws {
        guard condition else { throw VPhoneNFCCheckFailure(message: "line \(line): \(message)") }
        count += 1
    }
    func fails(_ expected: VPhoneNFCError, _ action: () throws -> Void, line: Int = #line) throws {
        do { try action() } catch let error as VPhoneNFCError {
            try check(error == expected, "expected \(expected), got \(error)", line: line)
            return
        }
        throw VPhoneNFCCheckFailure(message: "line \(line): expected failure \(expected)")
    }
}

final class VPhoneNFCResultCapture {
    var results: [Result<[UInt8], VPhoneNFCError>] = []
    func receive(_ result: Result<[UInt8], VPhoneNFCError>) { results.append(result) }
    var failure: VPhoneNFCError? {
        guard case .failure(let error) = results.last else { return nil }
        return error
    }
    var bytes: [UInt8]? {
        guard case .success(let bytes) = results.last else { return nil }
        return bytes
    }
}
#endif
