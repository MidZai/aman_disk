import SwiftUI
import AppKit
import DiskHealthCore

struct UnsupportedDiskView: View {
    let physical: PhysicalDisk
    
    private var reason: UnsupportedReason {
        if case .unsupported(let r) = physical.healthCapability {
            return r
        }
        return .noSmartInterface
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
            return Strings.smartDisabledTitle
        case .virtualDisk:
            return Strings.virtualDiskTitle
        case .noSmartInterface:
            return Strings.noSmartInterfaceTitle
        case .readFailed:
            return Strings.readErrorTitle
        case .usbBridge:
            return Strings.unsupportedTitle
        }
    }
    
    private var messageText: String {
        switch reason {
        case .sdCardReader:
            return Strings.sdCardReaderText
        case .smartDisabled:
            return Strings.smartDisabledText
        case .virtualDisk:
            return Strings.virtualDiskText
        case .noSmartInterface:
            return Strings.noSmartInterfaceText
        case .readFailed(let code):
            return Strings.readErrorText(code: code)
        case .usbBridge:
            return Strings.unsupportedText1
        }
    }
    
    private var showExportButton: Bool {
        switch reason {
        case .sdCardReader, .smartDisabled, .virtualDisk:
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
                        
                        let sizeStr = Formatters.bytes(physical.sizeBytes)
                        let locStr = physical.isInternal ? "Interne" : "Externe"
                        let connStr: String = {
                            if physical.protocolType == .pcieAhci { return "PCIe AHCI" }
                            switch physical.connection {
                            case .nvmeInternal, .nvmeExternal: return "NVMe"
                            case .sata: return "SATA"
                            case .usb: return "USB"
                            case .other: return physical.protocolType == .unknown ? "Autre" : physical.protocolType.rawValue
                            }
                        }()
                        
                        Text("\(sizeStr) · \(connStr) · \(locStr)")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                // Orange card
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
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Commande pour activer S.M.A.R.T. (Terminal) :")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text("smartctl -s on /dev/\(physical.bsdName)")
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("smartctl -s on /dev/\(physical.bsdName)", forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Copier la commande")
                                }
                            }
                            .padding(.top, 4)
                        }
                        
                        if showExportButton {
                            Button(Strings.exportDiagnostic) {
                                exportDiagnostic()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
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
                
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .top)
            .frame(maxWidth: .infinity)
        }
    }
    
    private func exportDiagnostic() {
        let diag = Diagnostic(physical: physical)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        guard let data = try? encoder.encode(diag) else { return }
        
        let panel = NSSavePanel()
        panel.title = "Enregistrer le diagnostic DiskHealth"
        
        let filename: String
        if let vid = physical.usbVendorID, let pid = physical.usbProductID {
            let vidStr = String(format: "0x%04X", vid)
            let pidStr = String(format: "0x%04X", pid)
            filename = "DiskHealth_Diagnostic_\(vidStr)_\(pidStr).json"
        } else {
            filename = "DiskHealth_Diagnostic_\(physical.bsdName).json"
        }
        
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                ToastCenter.shared.show(message: "Diagnostic exporté", systemImage: "checkmark.circle")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                ToastCenter.shared.show(message: "L'export a échoué", systemImage: "xmark.octagon")
            }
        }
    }
}
