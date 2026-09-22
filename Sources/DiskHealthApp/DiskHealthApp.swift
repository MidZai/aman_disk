import SwiftUI
import AppKit

@main
struct DiskHealthApp: App {
    @StateObject private var appManager = AppManager()
    
    init() {
        if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] == "1" {
            // Mode démo activé
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appManager)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1380, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { DiskCommands(appManager: appManager) }
    }
}
