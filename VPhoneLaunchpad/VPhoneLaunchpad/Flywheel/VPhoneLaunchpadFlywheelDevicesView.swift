import SwiftUI
import VPhoneFlywheel

struct VPhoneLaunchpadFlywheelDevicesView: View {
    let store: VPhoneFlywheelDeviceStore
    let machines: [VPhoneLaunchpadFlywheelMachine]
    let sourceError: String?
    let hasListed: Bool
    let pending: Set<String>
    let onRefresh: () async -> Void
    let onOpen: (VPhoneFlywheelMachineReference) -> Void
    let onToggle: (VPhoneFlywheelMachineReference) -> Void
    let onPrepare: (VPhoneFlywheelMachineReference) async throws -> VPhoneFlywheelMachineReference
    let onCheckNetwork: (VPhoneFlywheelMachineReference) async -> Void
    let onConfigureNetwork: (VPhoneFlywheelMachineReference) -> Void
    @State private var search = ""
    @State private var selected: UUID?
    @State private var editor: Editor?
    @State private var deletion: VPhoneFlywheelDevice?
    @State private var error: String?
    @State private var refreshing = false

    private struct Editor: Identifiable {
        let id = UUID()
        let device: VPhoneFlywheelDevice?
    }

    private var rows: [VPhoneFlywheelDevice] {
        store.devices.filter { $0.matches(search: search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("虚拟机管理").font(.title2.bold())
                    Text("\(store.devices.count) 台业务设备 · 地区为业务标签，代理设置请到平台管理")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("新增关联", systemImage: "plus") { editor = Editor(device: nil) }
                    .disabled(!hasListed || sourceError != nil || machines.isEmpty)
            }
            .padding(16)

            if let sourceError {
                Label("平台列表读取失败：\(sourceError)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 8)
            } else if !hasListed {
                ProgressView("正在读取平台虚拟机…").padding(8)
            }

            HStack {
                TextField("查询编号、名称、地区或备注", text: $search)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                Button("重置") { search = "" }.disabled(search.isEmpty)
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { refresh() }
                    .disabled(refreshing)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)

            Table(rows, selection: $selected) {
                TableColumn("设备编号", value: \.number).width(min: 70, ideal: 100, max: 180)
                TableColumn("名称") { device in
                    Text(device.machine.name).help(device.machine.id)
                }.width(min: 120, ideal: 200)
                TableColumn("地区") { device in
                    Text(device.region.isEmpty ? "未设置" : device.region)
                }.width(min: 60, ideal: 90, max: 180)
                TableColumn("备注", value: \.notes).width(min: 100, ideal: 240)
                TableColumn("状态") { device in
                    Text(status(device)).foregroundStyle(.secondary)
                }.width(min: 80, ideal: 100, max: 160)
                TableColumn("业务网络") { device in
                    Text(current(device.machine)?.state == .running
                        ? (VPhoneLaunchpadFlywheelNetwork.shared.messages[.init(libraryRoot: device.machine.libraryRoot,
                            name: device.machine.name)] ?? "尚未检查") : "未启动或关联不可用")
                        .font(.caption).foregroundStyle(.secondary)
                }.width(min: 150, ideal: 230)
                TableColumn("操作") { device in
                    actions(device)
                }.width(min: 190, ideal: 210)
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        store.devices.isEmpty ? "暂无业务设备" : "没有匹配的设备",
                        systemImage: "iphone",
                        description: Text(store.devices.isEmpty
                            ? "点击“新增关联”选择已有虚拟机；新建虚拟机请使用平台管理。"
                            : "请调整查询条件。")
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: machines.map(\.reference), initial: true) { _, _ in synchronizeMachines() }
        .onChange(of: hasListed) { _, _ in synchronizeMachines() }
        .onChange(of: sourceError) { _, _ in synchronizeMachines() }
        .sheet(item: $editor) { item in
            VPhoneLaunchpadFlywheelDeviceEditor(
                device: item.device, devices: store.devices,
                machines: sourceError == nil && hasListed ? machines.map(\.reference) : []
            ) { number, machine, region, notes in
                let isUnchangedBinding = item.device?.machine == machine
                // A sheet can remain open while the platform refreshes a rename.
                var savedMachine = isUnchangedBinding
                    ? (store.devices.first { $0.id == item.device?.id }?.machine ?? machine) : machine
                guard isUnchangedBinding || (hasListed && sourceError == nil && current(savedMachine) != nil) else {
                    throw VPhoneFlywheelError("平台实例已变化，请刷新并重新选择。")
                }
                if !isUnchangedBinding {
                    let validatedNumber = try VPhoneFlywheelValidation.number(number)
                    _ = try VPhoneFlywheelValidation.region(region)
                    guard !store.devices.contains(where: { $0.id != item.device?.id && $0.number == validatedNumber }) else {
                        throw VPhoneFlywheelError("设备编号已存在。")
                    }
                    savedMachine = try await onPrepare(savedMachine)
                }
                try store.save(id: item.device?.id, number: number, machine: savedMachine, region: region, notes: notes)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(error ?? "") }
        .confirmationDialog(
            "删除业务设备 \(deletion?.number ?? "")？",
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除业务记录", role: .destructive) {
                guard let deletion else { return }
                do { try store.delete(id: deletion.id) } catch { self.error = error.localizedDescription }
                self.deletion = nil
            }
        } message: {
            Text("仅删除 FLYWHEEL 的编号、地区、备注和关联。平台虚拟机及其磁盘会保留。")
        }
    }

    private func current(_ reference: VPhoneFlywheelMachineReference) -> VPhoneLaunchpadFlywheelMachine? {
        guard reference.directoryIdentity != nil else { return nil }
        return machines.first { reference.matches($0.reference) }
    }

    private func status(_ device: VPhoneFlywheelDevice) -> String {
        guard hasListed, sourceError == nil else { return "状态未知" }
        if device.machine.directoryIdentity == nil { return "需确认关联" }
        if pending.contains(device.machine.id) { return "操作中…" }
        guard let machine = current(device.machine) else { return "需重新关联" }
        switch machine.state {
        case .running: return "运行中"
        case .stopped: return "已关闭"
        case let .busy(activity): return activity
        }
    }

    private func actions(_ device: VPhoneFlywheelDevice) -> some View {
        let machine = current(device.machine)
        let available = hasListed && sourceError == nil && machine != nil
        let canToggle = available && !pending.contains(device.machine.id)
            && (machine?.state == .running || machine?.state == .stopped)
        return HStack(spacing: 10) {
            Button(machine?.state == .running ? "关闭" : "启动") { onToggle(device.machine) }
                .disabled(!canToggle)
            Button("编辑") { editor = Editor(device: device) }
            Menu {
                Button("平台管理…") { onOpen(device.machine) }.disabled(!available)
                Button("检查业务网络") { Task { await onCheckNetwork(device.machine) } }.disabled(!available)
                Button("准备网络与出口…") { onConfigureNetwork(device.machine) }.disabled(!available)
                Divider()
                Button("删除业务记录…", role: .destructive) { deletion = device }
            } label: { Text("更多") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .buttonStyle(.borderless)
    }

    private func refresh() {
        refreshing = true
        Task {
            defer { refreshing = false }
            do { try store.reload() } catch { self.error = error.localizedDescription }
            await onRefresh()
            synchronizeMachines()
        }
    }

    private func synchronizeMachines() {
        guard hasListed, sourceError == nil else { return }
        do { try store.synchronizeMachines(machines.map(\.reference)) }
        catch { self.error = error.localizedDescription }
    }
}
