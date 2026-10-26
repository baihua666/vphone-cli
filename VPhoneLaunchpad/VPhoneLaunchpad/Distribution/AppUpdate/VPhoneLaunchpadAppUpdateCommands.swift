#if VPHONE_CUSTOM_DISTRIBUTION && VPHONE_CUSTOM_APP_UPDATE
import SwiftUI

struct VPhoneLaunchpadAppUpdateCommands: Commands {
    let model: VPhoneLaunchpadModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查 App 更新…") {
                openWindow(id: "distribution")
                model.distribution.check()
            }
        }
    }
}
#endif
