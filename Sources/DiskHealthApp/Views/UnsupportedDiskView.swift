import SwiftUI
import AppKit
import DiskHealthCore

struct UnsupportedDiskView: View {
    @EnvironmentObject var appManager: AppManager
    let physical: PhysicalDisk
    @State private var confirmEnable = false
    @State private var showHelpSheet = false

    /// Failure to turn on S.M.A.R.T. (automatically or manually).
    private var enableFailureCode: Int32? {
        if reason == .smartDisabled, case .failed(let code)? = appManager.smartNotices[physical.bsdName] { return code }
        return nil
    }
    
    private var reason: UnsupportedReason {
        if case .unsupported(let r) = physical.healthCapability {
            return r
        }
        if case .error(let c) = physical.smartAvailability {
            return .readFailed(code: "\(c)")
        }
        return .noSmartInterface
    }

    private var isUSB: Bool {
        physical.driveConnection == .usb || reason == .usbBridge
    }
    
    private var iconName: String {
        switch reason {
        case .sdCardReader, .smartDisabled, .virtualDisk, .usbBridge:
            return "info.circle"
        case .noSmartInterface, .readFailed:
            return "exclamationmark.triangle"
        }
    }
    
    private var titleText: String {
        switch reason {
        case .sdCardReader:
            return Strings.sdCardReaderTitle
        case .smartDisabled:
            return enableFailureCode == nil ? Strings.smartDisabledTitle : Strings.smartEnableFailedTitle
        case .virtualDisk:
            return Strings.virtualDiskTitle
        case .noSmartInterface:
            return Strings.noSmartInterfaceTitle
        case .readFailed:
            return Strings.readErrorTitle
        case .usbBridge:
            return Strings.usbNoSmartTitle
        }
    }
    
    private var messageText: String {
        switch reason {
        case .sdCardReader:
            return Strings.sdCardReaderText
        case .smartDisabled:
            return enableFailureCode.map(Strings.smartEnableFailedText(code:)) ?? Strings.smartDisabledText
        case .virtualDisk:
            return Strings.virtualDiskText
        case .noSmartInterface:
            return Strings.noSmartInterfaceText
        case .readFailed(let code):
            return Strings.readErrorText(code: code)
        case .usbBridge:
            return Strings.usbNoSmartText
        }
    }
    
    private var isReadFailed: Bool {
        if case .readFailed = reason { return true }
        return false
    }
    
    private var showExportButton: Bool {
        switch reason {
        case .smartDisabled:
            return enableFailureCode != nil
        case .sdCardReader, .virtualDisk:
            return false
        case .noSmartInterface, .readFailed, .usbBridge:
            return true
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    DiskIconProvider.icon(for: physical)
                        .font(.system(size: 48))
                        .frame(width: 56, height: 56)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(physical.model)
                            .font(.system(size: 24, weight: .semibold))
                        
                        Text("\(Formatters.bytes(physical.sizeBytes)) · \(physical.detailInterfaceLabel) · \(physical.locationLabel)")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                if case .usbBridge = reason {
                    usbNoSmartCard
                    usbDetailsSection
                } else if isUSB {
                    nonUSBCard
                    usbDetailsSection
                } else {
                    nonUSBCard
                }

                volumesSection
                
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .top)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showHelpSheet) {
            USBEnclosureHelpSheet(onExport: exportDiagnostic)
        }
    }

    // MARK: - USB Calm Neutral Card

    private var usbNoSmartCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "info.circle")
                .font(.system(size: 22))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 10) {
                Text(Strings.usbNoSmartTitle)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(Strings.usbNoSmartText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button(Strings.learnMore) {
                        showHelpSheet = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button(Strings.exportDiagnostic) {
                        exportDiagnostic()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Non-USB Card

    private var nonUSBCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundColor(.orange)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 10) {
                Text(titleText)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(messageText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if reason == .smartDisabled {
                    smartActions
                        .padding(.top, 4)
                } else if case .readFailed = reason {
                    HStack(spacing: 10) {
                        Button(Strings.retry) {
                            appManager.loadDisks()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appManager.isRefreshing)

                        if appManager.isRefreshing {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
                
                if showExportButton {
                    if isReadFailed {
                        Button(Strings.exportDiagnostic) {
                            exportDiagnostic()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    } else {
                        Button(Strings.exportDiagnostic) {
                            exportDiagnostic()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Technical Details Grid

    private var usbDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.driveInformation)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    InfoPair(label: L("Capacity", "Capacité"), value: Formatters.bytes(physical.sizeBytes))
                    InfoPair(label: Strings.bridgeChip, value: physical.usbBridgeLabel ?? "—")
                }
                GridRow {
                    InfoPair(label: L("Interface", "Interface"), value: physical.detailInterfaceLabel)
                    InfoPair(label: Strings.linkSpeed, value: physical.usbLinkSpeedLabel ?? "—")
                }
                GridRow {
                    InfoPair(label: L("Type", "Type"), value: physical.mediumLabel)
                    InfoPair(label: Strings.protocolLabel, value: physical.usbProtocolLabel ?? "—")
                }
                GridRow {
                    InfoPair(label: L("Location", "Emplacement"), value: physical.locationLabel)
                    InfoPair(label: L("BSD name", "Nom BSD"), value: physical.bsdName)
                }
            }
            .fixedSize()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Volumes & Partitions

    private var volumesSection: some View {
        let matchingVolumes = appManager.volumes.filter { $0.physicalDiskBSDNames.contains(physical.bsdName) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(Strings.volumesAndPartitions)
                .font(.headline)

            if !matchingVolumes.isEmpty {
                VStack(spacing: 8) {
                    ForEach(matchingVolumes) { vol in
                        HStack(spacing: 12) {
                            DiskIconProvider.icon(for: vol)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vol.name)
                                    .font(.body.weight(.medium))
                                Text("\(vol.format) · \(Formatters.bytes(vol.totalBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vol.availableBytes > 0 {
                                Text(L("\(Formatters.bytes(vol.availableBytes)) free", "\(Formatters.bytes(vol.availableBytes)) libres"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        if vol.id != matchingVolumes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            } else if !physical.volumeNames.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(physical.volumeNames, id: \.self) { name in
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.body.weight(.medium))
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            } else {
                Text(Strings.noMountedVolumes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    /// “Try Again” after a failure, otherwise “Turn On S.M.A.R.T.…” with a confirmation.
    @ViewBuilder
    private var smartActions: some View {
        let isEnabling = appManager.enablingSmart.contains(physical.bsdName)
        HStack(spacing: 10) {
            if enableFailureCode != nil {
                Button(Strings.retry) { appManager.enableSmart(diskId: physical.bsdName) }
                    .disabled(isEnabling)
            } else {
                Button(Strings.smartEnableButton) { confirmEnable = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(isEnabling)
            }
            if isEnabling {
                ProgressView().controlSize(.small)
            }
        }
        .confirmationDialog(Strings.smartEnableConfirmTitle, isPresented: $confirmEnable) {
            Button(L("Turn On", "Activer")) { appManager.enableSmart(diskId: physical.bsdName) }
            Button(L("Cancel", "Annuler"), role: .cancel) {}
        } message: {
            Text(Strings.smartEnableConfirmText)
        }
    }

    private func exportDiagnostic() {
        let diag = Diagnostic(physical: physical)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        guard let data = try? encoder.encode(diag) else { return }
        
        let panel = NSSavePanel()
        panel.title = L("Save Aman Disk Diagnostic", "Enregistrer le diagnostic Aman Disk")
        
        let filename: String
        if let vid = physical.usbVendorID, let pid = physical.usbProductID {
            let vidStr = String(format: "0x%04X", vid)
            let pidStr = String(format: "0x%04X", pid)
            filename = "Aman-Disk-diagnostic_\(vidStr)_\(pidStr).json"
        } else {
            filename = "Aman-Disk-diagnostic_\(physical.bsdName).json"
        }
        
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                ToastCenter.shared.show(message: L("Diagnostic exported", "Diagnostic exporté"), systemImage: "checkmark.circle")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                ToastCenter.shared.show(message: L("Export failed", "L'export a échoué"), systemImage: "xmark.octagon")
            }
        }
    }
}

// MARK: - USB Enclosure Explanation Sheet

struct USBEnclosureHelpSheet: View {
    let onExport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(Strings.usbHelpTitle)
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helpSection(
                        icon: "cpu",
                        title: Strings.usbHelpSection1Title,
                        text: Strings.usbHelpSection1Text
                    )

                    helpSection(
                        icon: "bolt.fill",
                        title: Strings.usbHelpSection2Title,
                        text: Strings.usbHelpSection2Text
                    )

                    satDriverHelpSection

                    helpSection(
                        icon: "heart.fill",
                        title: Strings.usbHelpSection4Title,
                        text: Strings.usbHelpSection4Text
                    )
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button(Strings.exportDiagnostic) {
                    dismiss()
                    onExport()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(Strings.done) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560, height: 560)
    }

    private var satDriverHelpSection: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.usbHelpSection3Title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(Strings.usbHelpSection3Text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: "https://github.com/kasbert/OS-X-SAT-SMART-Driver") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(Strings.viewOnGitHub)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 2)
            }
        }
    }

    private func helpSection(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
