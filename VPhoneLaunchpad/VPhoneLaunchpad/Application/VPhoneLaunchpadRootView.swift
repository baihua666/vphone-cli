import SwiftUI

struct VPhoneLaunchpadRootView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        @Bindable var host = model.host
        @Bindable var bundles = model.bundles
        VPhoneLaunchpadMachinesView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    #if VPHONE_CUSTOM_APPLICATION_MANAGEMENT
                    Button { openWindow(id: "applications") } label: { Label("应用管理", systemImage: "app.badge") }
                    #endif
                    #if VPHONE_CUSTOM_DISTRIBUTION
                    Button { openWindow(id: "distribution") } label: { Label("版本与镜像", systemImage: "arrow.down.circle") }
                    #endif
                    panelButton(.hostSetup, systemImage: "checklist", needsAttention: model.hostNeedsAttention)
                    panelButton(.coreBundle, systemImage: "shippingbox", needsAttention: model.bundleNeedsAttention)
                    Button {
                        openWindow(id: "flywheel")
                    } label: {
                        Label("FLYWHEEL", systemImage: "square.grid.2x2")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("打开 FLYWHEEL 业务窗口")
                }
            }
            .navigationTitle(String(localized: "Machines"))
            .task {
                #if VPHONE_CUSTOM_DISTRIBUTION
                if !UserDefaults.standard.bool(forKey: "distribution.setupSeen") { openWindow(id: "distribution") }
                #endif
                await model.start()
            }
            // Free space changes as machines restore and IPSWs download; the
            // Host Setup row follows it.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    host.refreshDiskSpace()
                }
            }
            // Coming back from Settings, with or without Host Setup open.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                host.refreshDeveloperTools()
                host.refreshDiskSpace()
            }
            .sheet(item: $model.panel, onDismiss: model.panelDidDismiss) { panel in
                Group {
                    switch panel {
                    case .hostSetup:
                        VPhoneLaunchpadHostSetupView()
                    case .coreBundle:
                        VPhoneLaunchpadCoreBundleView()
                    case .bundleInstall:
                        VPhoneLaunchpadInstallView()
                    case .ipswCache:
                        VPhoneLaunchpadIPSWCacheView()
                    }
                }
                .environment(model)
            }
            // A sheet shows its own errors; these cover work done with none
            // open, such as the helper update on launch.
            .errorAlert($host.actionError, isEnabled: model.panel == nil)
            .errorAlert($bundles.actionError, isEnabled: model.panel == nil)
    }

    private func panelButton(_ panel: VPhoneLaunchpadModel.Panel, systemImage: String, needsAttention: Bool) -> some View {
        Button {
            model.present(panel)
        } label: {
            Label {
                Text(panel.title)
            } icon: {
                if needsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: systemImage)
                }
            }
        }
        .help(needsAttention ? "\(panel.title) needs attention" : panel.title)
    }
}

extension View {
    /// Presents an action error as an alert and clears it when dismissed.
    func errorAlert(_ error: Binding<VPhoneLaunchpadError?>, isEnabled: Bool = true) -> some View {
        alert(
            error.wrappedValue?.message ?? "",
            isPresented: Binding(
                get: { isEnabled && error.wrappedValue != nil },
                set: {
                    if !$0 {
                        error.wrappedValue = nil
                    }
                },
            ),
            presenting: error.wrappedValue,
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.detail ?? "")
        }
    }
}
