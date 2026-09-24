import SwiftUI
import AppKit
import DiskHealthCore
import BenchmarkCore

enum AppScene {
    static let mainWindowID = "main"
}

/// Resident mode: closing the main window keeps the app in the menu bar
/// (with no Dock icon) if the option is on; otherwise the app quits.
@MainActor
enum MainWindowLifecycle {
    static func windowDidOpen() {
        AppManager.sharedInstance?.isMainWindowVisible = true
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func windowDidClose() {
        AppManager.sharedInstance?.isMainWindowVisible = false
        let stay = UserDefaults.standard.object(forKey: PreferenceKey.stayInMenuBar) as? Bool ?? true
        if stay {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Closing the last window is handled by MainWindowLifecycle.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let benchmark = AppManager.sharedInstance?.benchmark, benchmark.isRunning else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = L("Quit Aman Disk?", "Quitter Aman Disk ?")
        alert.informativeText = Strings.benchQuitWarning
        alert.addButton(withTitle: L("Continue Test", "Continuer le test"))
        alert.addButton(withTitle: L("Stop and Quit", "Arrêter et quitter"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        // Deferred reply: the app quits once the test file has been deleted.
        benchmark.cancelForTermination()
        return .terminateLater
    }
}

@main
struct DiskHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appManager: AppManager

    init() {
        MigrationService.migrateIfNeeded()
        MigrationService.mergeLegacyHistoryIfNeeded()
        MigrationService.removeForeignPreferences()
        if AppManager.isDemo {
            // Demo mode never writes to the real history.
            let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("AmanDiskDemo-\(ProcessInfo.processInfo.processIdentifier)")
            HistoryStore.shared = HistoryStore(baseURL: demoDir)
            DiskEventLog.shared = DiskEventLog(baseURL: demoDir)
        } else {
            // Test files left behind by an interrupted test (crash, force quit).
            BenchInflight.cleanUpLeftovers()
        }
        _appManager = StateObject(wrappedValue: AppManager())
    }

    var body: some Scene {
        Window(AppInfo.name, id: AppScene.mainWindowID) {
            ContentView()
                .environmentObject(appManager)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { MainWindowLifecycle.windowDidOpen() }
                .onDisappear { MainWindowLifecycle.windowDidClose() }
        }
        .defaultSize(width: 1280, height: 860)
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
