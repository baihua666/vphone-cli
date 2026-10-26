#if VPHONE_CUSTOM_DISTRIBUTION
import SwiftUI

struct VPhoneLaunchpadAppUpdateCommands: Commands {
    let model: VPhoneLaunchpadModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查 App 更新…") {
                openWindow(id: "app-update")
                model.appUpdates.check()
            }
        }
    }
}
#endif
