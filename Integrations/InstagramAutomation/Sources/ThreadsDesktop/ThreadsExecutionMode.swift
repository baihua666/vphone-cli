#if VPHONE_CUSTOM_THREADS_DESKTOP
public enum ThreadsExecutionMode: Sendable {
    case publish, photoValidation
    public func arguments(directory: String) -> [String] {
        [self == .photoValidation ? "threads-photo-check" : "threads-task", directory]
    }
    public func resultStatus(success: Bool) -> String {
        success ? "选图与附件核验通过（本次未发布）" : "选图核验失败（本次未发布）"
    }
}
#endif
