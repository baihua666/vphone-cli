import SwiftUI

/// A single business window shares the platform model, never its navigation state.
struct VPhoneLaunchpadFlywheelWindow: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VPhoneLaunchpadFlywheelView { path in
            model.machines.selection = [path]
            model.showsInspector = true
            openWindow(id: "main")
        }
        .frame(minWidth: 900, minHeight: 480)
        .navigationTitle("FLYWHEEL")
    }
}
