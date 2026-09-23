import SwiftUI
import AppKit

enum AppScene {
    static let mainWindowID = "main"
}

/// Mode résident : fermer la fenêtre principale garde l'app dans la barre des menus
/// (sans icône dans le Dock) si l'option est active ; sinon l'app quitte.
@MainActor
enum MainWindowLifecycle {
    static func windowDidOpen() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    static func windowDidClose() {
        let stay = UserDefaults.standard.object(forKey: PreferenceKey.stayInMenuBar) as? Bool ?? true
        if stay {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.terminate(nil)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // La fermeture de la dernière fenêtre est gérée par MainWindowLifecycle.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
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
        MigrationService.mergeLegacyHistoryIfNeeded()
    }
    
    var body: some Scene {
        Window(AppInfo.name, id: AppScene.mainWindowID) {
            ContentView()
                .environmentObject(appManager)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { MainWindowLifecycle.windowDidOpen() }
                .onDisappear { MainWindowLifecycle.windowDidClose() }
        }
        .defaultSize(width: 1380, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { DiskCommands(appManager: appManager) }
        
        Settings {
            SettingsView()
        }
        
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(appManager)
        } label: {
            MenuBarLabel(appManager: appManager)
        }
        .menuBarExtraStyle(.window)
    }
}
