import Foundation
import Observation

@MainActor
@Observable
public final class VMStore {
    public private(set) var rows: [VMRow] = []
    public private(set) var loadError: String?

    private let client: VPhoneCLIClient
    private let probe: RunningStateProbe
    private let libraryRoot: String

    public init(client: VPhoneCLIClient, probe: RunningStateProbe, libraryRoot: String) {
        self.client = client; self.probe = probe; self.libraryRoot = libraryRoot
    }

    public func refresh() async {
        do {
            let reports = try await client.listVMs()
            var next: [VMRow] = []
            for report in reports {
                let context = try client.context(name: report.name)
                let resolved = context.executable != client.executable || context.isAlias
                    ? try await client.info(name: report.name) : report
                // Keep the library's alias as selection identity.
                let display = VMReport(name: report.name, cpuCount: resolved.cpuCount,
                    memoryMB: resolved.memoryMB, diskSizeBytes: resolved.diskSizeBytes,
                    network: resolved.network, udid: resolved.udid, restoreInfo: resolved.restoreInfo)
                let disk = context.directory.appendingPathComponent("Disk.img").path
                let running = (try? await probe.isRunning(diskImagePath: disk)) ?? false
                next.append(VMRow(report: display, isRunning: running))
            }
            rows = next
            loadError = nil
        } catch let error as VPhoneCLIError {
            loadError = error.userMessage
        } catch {
            loadError = String(describing: error)
        }
    }
}
