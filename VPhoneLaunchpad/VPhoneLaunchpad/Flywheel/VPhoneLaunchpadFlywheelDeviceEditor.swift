import SwiftUI
import VPhoneWSCore
import VPhoneFlywheel

struct VPhoneLaunchpadFlywheelDeviceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let device: VPhoneFlywheelDevice?
    let devices: [VPhoneFlywheelDevice]
    let machines: [VPhoneFlywheelMachineReference]
    let onSave: (String, VPhoneFlywheelMachineReference, String, String) async throws -> Void
    @State private var number: String
    @State private var selectedMachine: VPhoneFlywheelMachineReference?
    @State private var region: String
    @State private var notes: String
    @State private var error: String?
    @State private var busy = false

    init(
        device: VPhoneFlywheelDevice?, devices: [VPhoneFlywheelDevice], machines: [VPhoneFlywheelMachineReference],
        onSave: @escaping (String, VPhoneFlywheelMachineReference, String, String) async throws -> Void
    ) {
        self.device = device
        self.devices = devices
        self.machines = machines
        self.onSave = onSave
        _number = State(initialValue: device?.number ?? "")
        _selectedMachine = State(initialValue: device?.machine)
        _region = State(initialValue: device?.region ?? "")
        _notes = State(initialValue: device?.notes ?? "")
    }

    private var choices: [VPhoneFlywheelMachineReference] {
        let occupied = Set(devices.filter { $0.id != device?.id }.map(\.machine.id))
        return machines.filter { !occupied.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(device == nil ? "新增业务设备" : "编辑业务设备")
                .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Form {
                Section {
                    TextField("设备编号", text: $number)
                    Text("只接受数字 0–9，编号唯一；保存时移除前导零。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("平台虚拟机", selection: $selectedMachine) {
                        Text("请选择已有虚拟机").tag(nil as VPhoneFlywheelMachineReference?)
                        if let device, !choices.contains(device.machine) {
                            Text("\(device.machine.name)（原关联暂不可用）").tag(Optional(device.machine))
                        }
                        ForEach(choices) { machine in
                            Text("\(machine.name) — \(machine.libraryRoot)").tag(Optional(machine))
                        }
                    }
                    if let selectedMachine {
                        LabeledContent("名称", value: selectedMachine.name)
                        Text(selectedMachine.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } footer: {
                    Text("名称跟随原目录更新。旧记录首次升级需重新选择平台实例确认身份；删除、替换或跨资料库移动后需重新关联。")
                }
                Section {
                    Picker("地区", selection: $region) {
                        Text("未设置").tag("")
                        ForEach(VPhoneFlywheelValidation.regionCodes.sorted(), id: \.self) { code in
                            Text("\(code) · \(Locale.current.localizedString(forRegionCode: code) ?? code)").tag(code)
                        }
                    }
                    TextField("备注", text: $notes, axis: .vertical).lineLimit(3...6)
                } footer: {
                    Text("地区仅用于业务分类，不会修改代理或虚拟机位置。")
                }
                if let selectedMachine, selectedMachine != device?.machine {
                    Section("业务网络准备") {
                        @Bindable var network = VPhoneLaunchpadFlywheelNetwork.shared
                        Text("保存时自动准备此实例的 tunnel 与 DECODO，并验证 guest 出口后完成登记；必要时会正常关闭并启动该实例。失败后可独立重试，既有 VM 和业务数据保留。")
                            .font(.caption)
                        TextField("新出口城市参数", text: $network.city)
                        TextField("物理 Wi-Fi 网卡", text: $network.device)
                        if !NativeDecodoController.usesEmbeddedCredentials {
                            TextField("本机代理凭据文件", text: $network.credentialsPath)
                        }
                        Text("仅新申请原生 ISP 出口时使用；已生效的 DECODO 会直接复用。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let message = network.messages[.init(libraryRoot: selectedMachine.libraryRoot, name: selectedMachine.name)] {
                            Text(message).font(.caption).textSelection(.enabled)
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedMachine == nil)
            }
            .padding(20)
        }
        .frame(width: 580, height: 700)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
    }

    private func save() {
        guard let selectedMachine else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await onSave(number, selectedMachine, region, notes)
                dismiss()
            } catch { self.error = VPhoneLaunchpadError.message(for: error) }
        }
    }
}
