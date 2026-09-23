import SwiftUI
import ServiceManagement
import DiskHealthCore

/// Clés des préférences (UserDefaults).
enum PreferenceKey {
    static let stayInMenuBar = "stayInMenuBar"
    static let showMenuBarTemperature = "showMenuBarTemperature"
}

/// Réglages : une seule page, formulaire groupé (⌘,).
struct SettingsView: View {
    @AppStorage(PreferenceKey.stayInMenuBar) private var stayInMenuBar = true
    @AppStorage(PreferenceKey.showMenuBarTemperature) private var showMenuBarTemperature = false

    @State private var launchAtLogin = false
    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?
    @State private var historySize: UInt64 = 0
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Général") {
                Toggle("Rester dans la barre des menus quand la fenêtre est fermée", isOn: $stayInMenuBar)
                Toggle("Ouvrir Aman Disk à l'ouverture de session", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("À autoriser dans Réglages Système › Général › Ouverture")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Ouvrir Réglages Système") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Barre des menus") {
                Toggle("Afficher la température à côté de l'icône", isOn: $showMenuBarTemperature)
            }

            Section("Données") {
                LabeledContent("Historique de température", value: Formatters.bytes(historySize))
                Button("Effacer l'historique de température…", role: .destructive) {
                    confirmClear = true
                }
                .confirmationDialog("Effacer l'historique de température ?", isPresented: $confirmClear) {
                    Button("Effacer", role: .destructive) {
                        HistoryStore.shared.removeAll()
                        refreshHistorySize()
                    }
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("Toutes les mesures enregistrées seront supprimées. Cette action est irréversible.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            refreshLoginStatus()
            refreshHistorySize()
        }
    }

    private func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "Impossible de modifier l'ouverture à la connexion : \(error.localizedDescription)"
        }
        refreshLoginStatus()
    }

    private func refreshHistorySize() {
        historySize = HistoryStore.shared.diskUsageBytes()
    }
}
