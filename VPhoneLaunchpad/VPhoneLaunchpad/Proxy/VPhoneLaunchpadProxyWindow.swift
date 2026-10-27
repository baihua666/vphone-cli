import SwiftUI

/// URL identity keeps same-named machines in different libraries separate and
/// lets openWindow focus an existing proxy window for the same machine.
struct VPhoneLaunchpadProxyWindow: View {
    let path: URL?
    @Environment(VPhoneLaunchpadModel.self) private var model

    var body: some View {
        Group {
            if let machine = model.machines.machines.first(where: { $0.path.url == path }) {
                VPhoneLaunchpadDecodoView(machine: machine, roots: model.machines.roots,
                    isRunning: model.machines.state(of: machine.path) == .running)
                    .id(machine.path)
                    .navigationTitle("代理出口 · \(machine.name)")
            } else {
                ContentUnavailableView("实例不可用", systemImage: "iphone.slash",
                    description: Text("实例已移除或资料库尚未加载，请从实例列表重新打开代理出口。"))
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}
