import Testing
@testable import VPhoneFlywheel

@Suite @MainActor
struct VPhoneFlywheelNetworkPreparationTests {
    @Test func transientGuestProbeFailureRetriesWithoutChangingRoute() async throws {
        var calls = 0
        var waits = 0
        let ip = try await VPhoneFlywheelNetworkPreparation.verify(check: {
            calls += 1
            if calls < 3 { throw VPhoneFlywheelError("network not ready") }
            return "23.24.25.26"
        }, wait: { waits += 1 })
        #expect(ip == "23.24.25.26" && calls == 3 && waits == 2)
    }

    @Test func failedGuestProbeIsBoundedAndCancellationIsNotRetried() async {
        var calls = 0
        await #expect(throws: VPhoneFlywheelError.self) {
            try await VPhoneFlywheelNetworkPreparation.verify(check: {
                calls += 1
                throw VPhoneFlywheelError("offline")
            }, wait: {})
        }
        #expect(calls == 3)
        calls = 0
        await #expect(throws: CancellationError.self) {
            try await VPhoneFlywheelNetworkPreparation.verify(check: {
                calls += 1
                throw CancellationError()
            }, wait: { Issue.record("Cancellation must not retry") })
        }
        #expect(calls == 1)
    }
    @Test(arguments: [false, true])
    func natIsPreparedBeforeDecodoAndVerification(_ running: Bool) async throws {
        var events: [String] = []
        let ip = try await VPhoneFlywheelNetworkPreparation.run(isTunnel: false, isRunning: running,
            stop: { events.append("stop") }, setTunnel: { events.append("tunnel") },
            start: { events.append("start") }, connectDecodo: { events.append("decodo") },
            verify: { events.append("verify"); return "23.24.25.26" })
        #expect(events == (running ? ["stop"] : []) + ["tunnel", "start", "decodo", "verify"])
        #expect(ip == "23.24.25.26")
    }

    @Test func readyNetworkIsNotRestartedOrReconfigured() async throws {
        var events: [String] = []
        _ = try await VPhoneFlywheelNetworkPreparation.run(isTunnel: true, isRunning: true,
            stop: { Issue.record("Must not stop") }, setTunnel: { Issue.record("Must not reconfigure") },
            start: { Issue.record("Must not restart") }, connectDecodo: { events.append("decodo") },
            verify: { events.append("verify"); return "23.24.25.26" })
        #expect(events == ["decodo", "verify"])
    }

    @Test func stoppedTunnelStartsWithoutChangingItsNetwork() async throws {
        var events: [String] = []
        _ = try await VPhoneFlywheelNetworkPreparation.run(isTunnel: true, isRunning: false,
            stop: { Issue.record("Already stopped") }, setTunnel: { Issue.record("Already tunnel") },
            start: { events.append("start") }, connectDecodo: { events.append("decodo") },
            verify: { events.append("verify"); return "23.24.25.26" })
        #expect(events == ["start", "decodo", "verify"])
    }

    @Test func cancellationBeforeChangingNetworkDoesNotContinue() async {
        var events: [String] = []
        await #expect(throws: CancellationError.self) {
            try await VPhoneFlywheelNetworkPreparation.run(isTunnel: false, isRunning: true,
                stop: { events.append("stop"); throw CancellationError() },
                setTunnel: { events.append("tunnel") }, start: { events.append("start") },
                connectDecodo: { events.append("decodo") }, verify: { events.append("verify"); return "23.24.25.26" })
        }
        #expect(events == ["stop"])
    }

    @Test(arguments: ["stop", "tunnel", "start", "decodo", "verify"])
    func failureStopsRemainingStepsAndAllowsRetry(_ failure: String) async throws {
        var events: [String] = []
        func step(_ name: String) throws {
            events.append(name)
            if name == failure { throw VPhoneFlywheelError("failure at " + name) }
        }
        await #expect(throws: VPhoneFlywheelError.self) {
            try await VPhoneFlywheelNetworkPreparation.run(isTunnel: false, isRunning: true,
                stop: { try step("stop") }, setTunnel: { try step("tunnel") },
                start: { try step("start") }, connectDecodo: { try step("decodo") },
                verify: { try step("verify"); return "23.24.25.26" })
        }
        #expect(events.last == failure)
    }
}
