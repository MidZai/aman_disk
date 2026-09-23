import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppManager.sharedInstance?.runningBenchmarkDiskId != nil {
            let alert = NSAlert()
            alert.messageText = "Quitter Aman Disk ?"
            alert.informativeText = Strings.benchQuitWarning
            alert.addButton(withTitle: "Annuler")
            alert.addButton(withTitle: "Quitter")
            
            let res = alert.runModal()
            if res == .alertFirstButtonReturn {
                return .terminateCancel
            } else {
                AppManager.sharedInstance?.cancelRunningBenchmark()
                // Wait a bit for the cleanup
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                return .terminateNow
            }
        }
        return .terminateNow
    }
}

@main
struct DiskHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appManager = AppManager()
    
    init() {
        MigrationService.migrateIfNeeded()
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
