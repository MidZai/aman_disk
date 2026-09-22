import SwiftUI
import AppKit

@main
struct DiskHealthApp: App {
    init() {
        if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1" {
            // Mode démo activé
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
    }
}
