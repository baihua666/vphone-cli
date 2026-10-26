#if VPHONE_CUSTOM_DISTRIBUTION
import SwiftUI

struct VPhoneLaunchpadAppUpdateView: View {
    @Environment(VPhoneLaunchpadModel.self) private var platform
    @Environment(\.dismissWindow) private var dismissWindow
    private var updates: VPhoneLaunchpadAppUpdateModel { platform.appUpdates }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launchpad 更新").font(.title2)
                    Text("当前版本：\(updates.currentBaseline) · 修订 \(updates.currentRevision)")
                        .foregroundStyle(.secondary)
                }
            }
            Text(updates.status).textSelection(.enabled)
            if updates.busy { ProgressView(value: updates.fraction) }
            if !updates.error.isEmpty {
                Text(updates.error).foregroundStyle(.red).textSelection(.enabled)
            }
            #if VPHONE_CUSTOM_APP_UPDATE
            Text("更新会自动下载、安装并重新打开 App。安装前请正常停止虚拟机。")
                .font(.caption).foregroundStyle(.secondary)
            #else
            Text("下载完成后请正常停止虚拟机、退出 App，再手动安装更新。")
                .font(.caption).foregroundStyle(.secondary)
            #endif
            HStack {
                Button("关闭") { dismissWindow(id: "app-update") }.keyboardShortcut(.cancelAction)
                Spacer()
                if updates.canPause { Button("暂停下载") { updates.pause() } }
                Button("检查更新") { updates.check() }.disabled(updates.busy)
                if updates.hasAppUpdate {
                    #if VPHONE_CUSTOM_APP_UPDATE
                    Button(updates.installing ? "正在更新…" : "更新并重启") { updates.updateApp(using: platform) }
                        .buttonStyle(.borderedProminent).disabled(updates.busy)
                    #else
                    Button("下载更新安装包") { updates.downloadApp() }.disabled(updates.busy)
                    #endif
                }
            }
            #if !VPHONE_CUSTOM_APP_UPDATE
            if let installer = updates.installer {
                Button("在 Finder 中显示安装包") { NSWorkspace.shared.activateFileViewerSelecting([installer]) }
            }
            #endif
        }
        .padding(24)
        .frame(width: 480)
    }
}
#endif
