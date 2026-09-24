import AppKit
import Combine
import SwiftUI
import UserNotifications
import DiskHealthCore

/// Opens the main window from AppKit code (click on a notification).
/// The action is captured by the menu bar label, which is always present.
@MainActor
enum WindowOpener {
    static var openMain: (() -> Void)?
    
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openMain?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Real system notifications.
final class SystemNotificationPoster: NSObject, NotificationPosting, UNUserNotificationCenterDelegate {
    static let diskIdKey = "diskId"
    
    /// `UNUserNotificationCenter` requires a real `.app` bundle (it crashes under `swift run`).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }
    
    override init() {
        super.init()
        if Self.isAvailable {
            UNUserNotificationCenter.current().delegate = self
        }
    }
    
    /// Asks for permission (only when the user turns alerts on).
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    
    func post(_ event: AlertEvent) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = AppInfo.name
        content.body = event.message
        content.sound = .default
        content.userInfo = [Self.diskIdKey: event.diskId]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    
    // Clicking the notification opens the page of the drive it's about.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let diskId = response.notification.request.content.userInfo[Self.diskIdKey] as? String
        await MainActor.run {
            if let diskId {
                AppManager.sharedInstance?.selection = .physicalDisk(diskId)
                AppManager.sharedInstance?.activeTab = .health
            }
            WindowOpener.showMainWindow()
        }
    }
}

/// Connects drive readings to the Dock icon and the alerts.
@MainActor
final class LiveStatusController {
    static let shared = LiveStatusController()
    private static let alertStatesKey = "alertStates"
    
    let poster = SystemNotificationPoster()
    private var engine: AlertEngine!
    private var cancellable: AnyCancellable?
    private weak var appManager: AppManager?
    private var lastDockState: DockIconRenderer.State?
    private var lastDockEnabled: Bool?
    
    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.alertStatesKey)
            .flatMap { try? JSONDecoder().decode([String: AlertEngine.DiskState].self, from: $0) } ?? [:]
        engine = AlertEngine(poster: poster, states: saved, isEnabled: Self.alertsEnabled)
    }
    
    static var dockShowsHealth: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.dockShowsHealth) as? Bool ?? true
    }
    
    static var alertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.alertsEnabled)
    }
    
    func start(appManager: AppManager) {
        guard self.appManager == nil else { return }
        self.appManager = appManager
        cancellable = appManager.$disks
            .receive(on: RunLoop.main)
            .sink { [weak self] disks in self?.update(disks: disks) }
    }
    
    private func update(disks: [RealDisk]) {
        refreshDockIcon()
        
        let readings = disks.filter { $0.physical.isInternal && $0.snapshot != nil }.map { disk in
            AlertReading(
                diskId: disk.id,
                name: disk.physical.model,
                status: disk.health.status,
                firstReason: disk.health.reasons.first,
                temperatureC: disk.temperatureC,
                isRotational: disk.physical.mediumType == .rotational,
                lifePercent: AmanPalette.knownPercent(health: disk.health, capability: disk.physical.healthCapability)
            )
        }
        guard !readings.isEmpty else { return }
        engine.isEnabled = Self.alertsEnabled
        engine.process(readings)
        if let data = try? JSONEncoder().encode(engine.states) {
            UserDefaults.standard.set(data, forKey: Self.alertStatesKey)
        }
    }
    
    /// Updates the Dock icon only if the percentage, the status or the setting changes.
    func refreshDockIcon() {
        let enabled = Self.dockShowsHealth
        let state = appManager?.bootDisk.map {
            DockIconRenderer.State(health: $0.health, capability: $0.physical.healthCapability)
        }
        guard enabled != lastDockEnabled || state != lastDockState else { return }
        lastDockEnabled = enabled
        lastDockState = state
        
        if enabled, let state, !state.isOfficialIcon {
            NSApp.applicationIconImage = DockIconRenderer.image(state: state)
        } else {
            // The bundle's official icon.
            NSApp.applicationIconImage = nil
        }
    }
}
