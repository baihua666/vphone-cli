import Foundation
import Observation

/// Session evidence, scoped to the selected artifact or destination. Persisted
/// receipts prove import only; they never prove a cached hash or guest readiness.
@MainActor @Observable public final class DistributionSetupProgress {
    public enum Step: Hashable, Sendable { case permissions, core, image, launch }
    public enum State: Equatable, Sendable {
        case pending, running, completed, paused, failed(String)
    }
    private struct Key: Hashable, Sendable { let step: Step; let scope: String }
    private var states: [Key: State] = [:]
    public init() {}
    public func state(_ step: Step, scope: String) -> State {
        states[Key(step: step, scope: scope)] ?? .pending
    }
    private func set(_ state: State, for step: Step, scope: String) {
        states[Key(step: step, scope: scope)] = state
    }
    public func perform<T>(_ step: Step, scope: String,
                           describeError: (Error) -> String = { $0.localizedDescription },
                           operation: @MainActor () async throws -> T) async throws -> T {
        set(.running, for: step, scope: scope)
        do {
            let result = try await operation()
            try Task.checkCancellation()
            set(.completed, for: step, scope: scope)
            return result
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled
            set(cancelled ? .paused : .failed(describeError(error)), for: step, scope: scope)
            throw error
        }
    }
}
