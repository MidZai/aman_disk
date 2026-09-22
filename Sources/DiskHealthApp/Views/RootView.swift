import SwiftUI
import AppKit
import DiskHealthCore

struct RootView: View {
    @StateObject private var appManager = AppManager()
    @State private var chromeVisible = false
    @State private var selectedDiskIndex = 0
    @State private var hoverWindow: NSWindow?
    @State private var initialTimer: Timer?
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        ZStack(alignment: .top) {
            if appManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appManager.disks.isEmpty {
                Text("Aucun disque physique trouvé.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let validIndex = min(selectedDiskIndex, max(0, appManager.disks.count - 1))
                let selectedDisk = appManager.disks[validIndex]
                
                // Halo background
                HealthHalo(status: selectedDisk.health.status)
                
                // Main content
                VStack(spacing: 22) {
                    // Hero Zone
                    HStack(spacing: 32) {
                        HealthGauge(assessment: selectedDisk.health)
                        
                        VStack(alignment: .leading, spacing: 22) {
                            HeroHeader(physical: selectedDisk.physical, assessment: selectedDisk.health)
                            StatTilesRow(physical: selectedDisk.physical, smart: selectedDisk.smart)
                        }
                        Spacer()
                    }
                    
                    // Bottom Zone
                    HStack(alignment: .top, spacing: 26) {
                        InfoList(physical: selectedDisk.physical, smart: selectedDisk.smart, identify: selectedDisk.identify)
                        
                        if let smart = selectedDisk.smart {
                            SmartTable(smart: smart)
                        } else {
                            UnsupportedDiskView(physical: selectedDisk.physical)
                        }
                    }
                }
                .padding(.top, 66)
                .padding(.bottom, 26)
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                
                // Floating chrome
                HStack(alignment: .top) {
                    // Disk selector (left, 80pt offset)
                    HStack(spacing: 8) {
                        ForEach(0..<appManager.disks.count, id: \.self) { index in
                            let disk = appManager.disks[index]
                            Button(action: {
                                selectedDiskIndex = index
                            }) {
                                HStack {
                                    Circle()
                                        .fill(statusColor(disk.health.status))
                                        .frame(width: 7, height: 7)
                                    Text(disk.physical.volumeNames.first ?? disk.physical.model)
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedDiskIndex == index ? Color.primary.opacity(0.12) : Color.clear)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassCapsule()
                    .padding(.leading, 80)
                    
                    Spacer()
                    
                    // Action buttons (right, 12pt offset)
                    HStack(spacing: 4) {
                        ActionButton(icon: "arrow.clockwise", help: Strings.refresh) {
                            appManager.loadDisks()
                        }
                        ActionButton(icon: "doc.on.doc", help: Strings.copyReport) {
                            copyReportToClipboard(disk: selectedDisk)
                        }
                        ActionButton(icon: "clock.arrow.circlepath", help: Strings.history) {}
                            .disabled(true)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .glassCapsule()
                    .padding(.trailing, 12)
                }
                .padding(.top, 12)
                .opacity(chromeVisible ? 1 : 0)
                .offset(y: chromeVisible ? 0 : -8)
                .allowsHitTesting(chromeVisible)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: chromeVisible)
                
                if appManager.needsSudo && !appManager.ignoreSudo {
                    Color.black.opacity(0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .edgesIgnoringSafeArea(.all)
                    
                    SudoRequestView {
                        appManager.ignoreSudo = true
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .windowAccessor(onWindow: { window in
            self.hoverWindow = window
            
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            
            window.standardWindowButton(.closeButton)?.alphaValue = 0
            window.standardWindowButton(.miniaturizeButton)?.alphaValue = 0
            window.standardWindowButton(.zoomButton)?.alphaValue = 0
        }, onHover: { inside in
            if initialTimer?.isValid == true { return }
            setChromeVisible(inside)
        })
        .onAppear {
            if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] != "1" {
                appManager.loadDisks()
            } else {
                appManager.isLoading = false
                // Load DemoData here
                let demoDisks = DemoData.disks.map { 
                    RealDisk(physical: $0.physical, smart: $0.smart, identify: $0.identify, health: $0.health)
                }
                appManager.disks = demoDisks
            }
            
            setChromeVisible(true)
            initialTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self.initialTimer = nil
                self.setChromeVisible(false)
            }
        }
    }
    
    private func copyReportToClipboard(disk: RealDisk) {
        struct Report: Codable {
            let identify: NVMeIdentify?
            let smart: NVMeSmartLog?
            let health: HealthAssessment
        }
        
        let report = Report(identify: disk.identify, smart: disk.smart, health: disk.health)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let data = try? encoder.encode(report), let string = String(data: data, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }
    
    private func setChromeVisible(_ visible: Bool) {
        chromeVisible = visible
        
        guard let window = hoverWindow else { return }
        let duration = reduceMotion ? 0.0 : 0.18
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            window.standardWindowButton(.closeButton)?.animator().alphaValue = visible ? 1 : 0
            window.standardWindowButton(.miniaturizeButton)?.animator().alphaValue = visible ? 1 : 0
            window.standardWindowButton(.zoomButton)?.animator().alphaValue = visible ? 1 : 0
        }
    }
    
    private func statusColor(_ status: HealthStatus) -> Color {
        switch status {
        case .good: return Color(nsColor: .systemGreen)
        case .caution: return Color(nsColor: .systemOrange)
        case .bad: return Color(nsColor: .systemRed)
        case .unknown: return Color(nsColor: .systemGray)
        }
    }
}

struct ActionButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
