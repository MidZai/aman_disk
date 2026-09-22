import SwiftUI
import AppKit
import DiskHealthCore

struct RootView: View {
    @State private var chromeVisible = false
    @State private var selectedDiskIndex = 0
    @State private var hoverWindow: NSWindow?
    @State private var initialTimer: Timer?
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            VStack {
                Spacer()
                Text(DemoData.disks[selectedDiskIndex].physical.model)
                    .font(.largeTitle)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Floating chrome
            HStack(alignment: .top) {
                // Disk selector (left, 80pt offset)
                HStack(spacing: 8) {
                    ForEach(0..<DemoData.disks.count, id: \.self) { index in
                        let disk = DemoData.disks[index]
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
                    ActionButton(icon: "arrow.clockwise", help: "Actualiser") {}
                    ActionButton(icon: "doc.on.doc", help: "Copier le rapport") {}
                    ActionButton(icon: "clock.arrow.circlepath", help: "Historique") {}
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
        }
        .frame(minWidth: 980, minHeight: 640)
        .windowAccessor { window in
            self.hoverWindow = window
        }
        .onHover { inside in
            if initialTimer?.isValid == true { return } // Keep visible during initial timer
            setChromeVisible(inside)
        }
        .onAppear {
            setChromeVisible(true)
            initialTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                // If not currently hovering after 2s, hide it. We can't easily read native mouse pos here simply without a tracking area, 
                // but we can assume if they aren't triggering onHover, we hide.
                // Actually, SwiftUI's onHover handles state. We just reset the timer lock.
                self.initialTimer = nil
                self.setChromeVisible(false) // it will quickly reappear if mouse is actually inside, since onHover triggers continuously or we can just leave it false and wait for movement.
            }
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
    
    private func statusColor(_ status: DiskHealthCore.HealthStatus) -> Color {
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
