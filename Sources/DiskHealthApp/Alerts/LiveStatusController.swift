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
            // The alert is keyed by the drive's identity; the selection wants its current BSD name.
            if let diskId, let disk = AppManager.sharedInstance?.disks.first(where: { $0.historyKey == diskId }) {
                AppManager.sharedInstance?.selection = .physicalDisk(disk.id)
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
    /// Keyed by drive identity (model + serial). The 1.0 key, indexed by BSD name, is erased.
    private static let alertStatesKey = "alertStatesByIdentity"
    private static let legacyAlertStatesKey = "alertStates"
    
    let poster = SystemNotificationPoster()
    private var engine: AlertEngine
    private var cancellable: AnyCancellable?
    private weak var appManager: AppManager?
    private var lastDockState: DockIconRenderer.State?
    private var lastDockEnabled: Bool?
    
    private init() {
        UserDefaults.standard.removeObject(forKey: Self.legacyAlertStatesKey)
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
    
    /// Drives that were read, keyed by their identity (model + serial number), never by BSD name:
    /// `disk4` is whatever was plugged last, and must not inherit another drive's alert state.
    nonisolated static func alertReadings(for disks: [RealDisk]) -> [AlertReading] {
        disks.compactMap { disk in
            guard disk.physical.healthCapability == .supported, disk.snapshot != nil, let key = disk.historyKey else { return nil }
            return AlertReading(
                diskId: key,
                name: disk.physical.model,
                status: disk.health.status,
                firstReason: disk.health.reasons.first,
                temperatureC: disk.temperatureC,
                isRotational: disk.physical.mediumType == .rotational,
                lifePercent: AmanPalette.knownPercent(health: disk.health, capability: disk.physical.healthCapability)
            )
        }
    }

    /// Alert state is persisted only for drives with a real serial number: without one the identity
    /// is the model alone, which another drive could share.
    private var transientIds: Set<String> = []

    private func update(disks: [RealDisk]) {
        refreshDockIcon()
        
        let readings = Self.alertReadings(for: disks)
        guard !readings.isEmpty else { return }
        for disk in disks where (disk.serialNumber ?? "").isEmpty {
            if let key = disk.historyKey { transientIds.insert(key) }
        }
        engine.isEnabled = Self.alertsEnabled
        engine.process(readings)
        let persisted = engine.states.filter { !transientIds.contains($0.key) }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: Self.alertStatesKey)
        }
    }
    
    /// Updates the Dock icon only if the percentage, the status or the setting changes.
    func refreshDockIcon() {
        guard NSApp != nil else { return }
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
