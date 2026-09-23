import SwiftUI
import AppKit

@main
struct DiskHealthApp: App {
    @StateObject private var appManager = AppManager()
    
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
