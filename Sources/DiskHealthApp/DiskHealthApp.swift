import SwiftUI
import AppKit
import DiskHealthCore
import BenchmarkCore

enum AppScene {
    static let mainWindowID = "main"
}

/// Mode résident : fermer la fenêtre principale garde l'app dans la barre des menus
/// (sans icône dans le Dock) si l'option est active ; sinon l'app quitte.
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
    // La fermeture de la dernière fenêtre est gérée par MainWindowLifecycle.
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
        // Réponse différée : l'app se ferme une fois le fichier de test supprimé.
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
            // Le mode démo n'écrit jamais dans le vrai historique.
            let demoDir = FileManager.default.temporaryDirectory.appendingPathComponent("AmanDiskDemo-\(ProcessInfo.processInfo.processIdentifier)")
            HistoryStore.shared = HistoryStore(baseURL: demoDir)
            DiskEventLog.shared = DiskEventLog(baseURL: demoDir)
        } else {
            // Fichiers de test laissés par un test interrompu (plantage, arrêt forcé).
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
