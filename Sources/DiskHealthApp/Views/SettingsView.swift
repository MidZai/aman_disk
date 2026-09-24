import SwiftUI
import ServiceManagement
import DiskHealthCore

/// Clés des préférences (UserDefaults).
enum PreferenceKey {
    static let stayInMenuBar = "stayInMenuBar"
    static let showMenuBarTemperature = "showMenuBarTemperature"
    static let dockShowsHealth = "dockShowsHealth"
    static let alertsEnabled = "alertsEnabled"
    static let autoEnableSmart = "autoEnableSmart"
    static let language = Localization.defaultsKey
}

/// Réglages : une seule page, formulaire groupé (⌘,).
struct SettingsView: View {
    @AppStorage(PreferenceKey.stayInMenuBar) private var stayInMenuBar = true
    @AppStorage(PreferenceKey.showMenuBarTemperature) private var showMenuBarTemperature = false
    @AppStorage(PreferenceKey.dockShowsHealth) private var dockShowsHealth = true
    @AppStorage(PreferenceKey.alertsEnabled) private var alertsEnabled = false
    @AppStorage(PreferenceKey.autoEnableSmart) private var autoEnableSmart = true
    @AppStorage(PreferenceKey.language) private var language = AppLanguage.english.rawValue
    @State private var notificationsDenied = false

    @State private var launchAtLogin = false
    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?
    @State private var historySize: UInt64 = 0
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section(L("General", "Général")) {
                Picker(L("Language", "Langue"), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { Text($0.nativeName).tag($0.rawValue) }
                }
                if language != Localization.language.rawValue {
                    HStack {
                        Text(L("Takes effect after relaunching Aman Disk.", "Prend effet au redémarrage d'Aman Disk."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Relaunch Now", "Redémarrer maintenant"), action: relaunch)
                    }
                }
                Toggle(L("Stay in the menu bar when the window is closed", "Rester dans la barre des menus quand la fenêtre est fermée"), isOn: $stayInMenuBar)
                Toggle(L("Open Aman Disk at login", "Ouvrir Aman Disk à l'ouverture de session"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text(L("Allow it in System Settings › General › Login Items", "À autoriser dans Réglages Système › Général › Ouverture"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Open System Settings", "Ouvrir Réglages Système")) {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle(L("Turn on S.M.A.R.T. automatically if it's off", "Activer S.M.A.R.T. automatiquement s'il est désactivé"), isOn: $autoEnableSmart)
                Text(L("SATA drives only, once per drive. Aman Disk never changes anything else on a drive.", "Disques SATA uniquement, une seule fois par disque. Aman Disk ne modifie rien d'autre sur un disque."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(L("Menu Bar", "Barre des menus")) {
                Toggle(L("Show the temperature next to the icon", "Afficher la température à côté de l'icône"), isOn: $showMenuBarTemperature)
            }
            
            Section("Dock") {
                Toggle(L("Dock icon: show drive health", "Icône du Dock : afficher la santé du disque"), isOn: $dockShowsHealth)
                    .onChange(of: dockShowsHealth) { LiveStatusController.shared.refreshDockIcon() }
            }
            
            Section(L("Alerts", "Alertes")) {
                Toggle(L("Notify me when a drive's status changes", "Me prévenir quand un disque change d'état"), isOn: Binding(
                    get: { alertsEnabled },
                    set: { setAlerts($0) }
                ))
                if notificationsDenied {
                    Text(L("Notifications are turned off in System Settings", "Notifications refusées dans Réglages Système"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("“Needs attention” or “Likely failing” status, high temperature for 5 minutes, remaining life below 50%, 25% or 10%.", "État « À surveiller » ou « Défaillance probable », température élevée pendant 5 minutes, durée de vie sous 50 %, 25 % ou 10 %."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("Data", "Données")) {
                LabeledContent(L("Temperature history", "Historique de température"), value: Formatters.bytes(historySize))
                Button(L("Clear Temperature History…", "Effacer l'historique de température…"), role: .destructive) {
                    confirmClear = true
                }
                .confirmationDialog(L("Clear temperature history?", "Effacer l'historique de température ?"), isPresented: $confirmClear) {
                    Button(L("Clear", "Effacer"), role: .destructive) {
                        HistoryStore.shared.removeAll()
                        refreshHistorySize()
                    }
                    Button(L("Cancel", "Annuler"), role: .cancel) {}
                } message: {
                    Text(L("All recorded measurements will be deleted. This can't be undone.", "Toutes les mesures enregistrées seront supprimées. Cette action est irréversible."))
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

    /// L'autorisation n'est demandée qu'à l'activation. Refusée : l'interrupteur revient à « désactivé ».
    private func setAlerts(_ enabled: Bool) {
        guard enabled else {
            alertsEnabled = false
            return
        }
        alertsEnabled = true
        Task { @MainActor in
            let granted = await LiveStatusController.shared.poster.requestAuthorization()
            notificationsDenied = !granted
            if !granted { alertsEnabled = false }
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
            loginError = L("Couldn't change the login item: \(error.localizedDescription)", "Impossible de modifier l'ouverture à la connexion : \(error.localizedDescription)")
        }
        refreshLoginStatus()
    }

    /// Relance l'app : la langue n'est lue qu'au démarrage.
    private func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func refreshHistorySize() {
        historySize = HistoryStore.shared.diskUsageBytes()
    }
}
