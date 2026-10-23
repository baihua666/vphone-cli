import SwiftUI
import VPhoneFlywheel

/// The only adapter between the business library and Launchpad's machine model.
struct VPhoneLaunchpadFlywheelView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var store: VPhoneFlywheelDeviceStore?
    @State private var loadError: String?
    @State private var pending: Set<String> = []
    @State private var networkMachine: VPhoneLaunchpadMachine?
    let onOpenMachine: (VPhoneLaunchpadMachinePath) -> Void

    var body: some View {
        @Bindable var library = model.machines
        Group {
            if let store {
                VPhoneLaunchpadFlywheelDevicesView(
                    store: store,
                    machines: library.machines.map { machine in
                        VPhoneLaunchpadFlywheelMachine(
                            reference: reference(machine), state: library.state(of: machine.path)
                        )
                    },
                    sourceError: library.listError,
                    hasListed: library.hasListed,
                    pending: pending,
                    onRefresh: { await library.refresh() },
                    onOpen: openMachine,
                    onToggle: toggleMachine,
                    onPrepare: prepareMachine,
                    onCheckNetwork: { reference in
                        guard let machine = resolve(reference) else { return }
                        await VPhoneLaunchpadFlywheelNetwork.shared.check(machine, library: model.machines)
                    },
                    onConfigureNetwork: { reference in networkMachine = resolve(reference) }
                )
            } else if let loadError {
                ContentUnavailableView {
                    Label("无法打开 FLYWHEEL 数据", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(loadError)
                    Text("平台虚拟机管理仍可使用。现有业务数据不会被重置。")
                } actions: {
                    Button("重试", action: loadStore)
                }
            } else {
                ProgressView("正在读取业务设备…")
            }
        }
        .task { if store == nil { loadStore() } }
        .errorAlert($library.actionError)
        .sheet(item: $networkMachine) { machine in
            VPhoneLaunchpadFlywheelNetworkPreparationView(machine: machine).environment(model)
        }
    }

    private func loadStore() {
        do {
            store = try VPhoneFlywheelDeviceStore(url: VPhoneFlywheelDeviceStore.defaultURL)
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }

    private func reference(_ machine: VPhoneLaunchpadMachine) -> VPhoneFlywheelMachineReference {
        let url = URL(fileURLWithPath: machine.libraryRoot).appendingPathComponent(machine.name)
        return .init(libraryRoot: machine.libraryRoot, name: machine.name, udid: machine.udid,
                     directoryIdentity: VPhoneFlywheelMachineReference.directoryIdentity(at: url))
    }

    private func resolve(_ reference: VPhoneFlywheelMachineReference) -> VPhoneLaunchpadMachine? {
        guard model.machines.hasListed, model.machines.listError == nil,
              reference.directoryIdentity != nil,
              let machine = model.machines.machines.first(where: { reference.matches(self.reference($0)) }) else {
            model.machines.actionError = VPhoneLaunchpadError("实例不可用或关联已变化，请刷新后重新关联。")
            return nil
        }
        return machine
    }

    private func openMachine(_ reference: VPhoneFlywheelMachineReference) {
        guard let machine = resolve(reference) else { return }
        onOpenMachine(machine.path)
    }

    private func toggleMachine(_ reference: VPhoneFlywheelMachineReference) {
        guard !pending.contains(reference.id), let machine = resolve(reference) else { return }
        let state = model.machines.state(of: machine.path)
        guard state == .running || state == .stopped else { return }
        pending.insert(reference.id)
        Task {
            defer { pending.remove(reference.id) }
            // Existing operations resolve the machine's pinned bundle and do preflight.
            if state == .running {
                await model.machines.stop(machine.path)
            } else {
                await model.machines.start(machine.path)
            }
        }
    }

    private func prepareMachine(_ reference: VPhoneFlywheelMachineReference) async throws -> VPhoneFlywheelMachineReference {
        guard let machine = resolve(reference) else { throw VPhoneFlywheelError("实例关联已变化，请重新选择。") }
        _ = try await VPhoneLaunchpadFlywheelNetwork.shared.prepare(machine, library: model.machines)
        guard let current = model.machines.machines.first(where: { $0.path == machine.path }),
              self.reference(current).directoryIdentity == reference.directoryIdentity else {
            throw VPhoneFlywheelError("准备期间实例关联已变化，请重新选择。")
        }
        return self.reference(current)
    }
}

struct VPhoneLaunchpadFlywheelMachine: Identifiable {
    let reference: VPhoneFlywheelMachineReference
    let state: VPhoneLaunchpadMachineLibrary.RunState
    var id: String { reference.id }
}
