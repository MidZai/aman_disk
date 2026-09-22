import SwiftUI
import AppKit
import DiskHealthCore

struct UnsupportedDiskView: View {
    let physical: PhysicalDisk
    @State private var showWhy = false
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("Disque non supporté")
                .font(.headline)
            
            
            HStack(spacing: 12) {
                Button("Pourquoi ?") {
                    showWhy.toggle()
                }
                .popover(isPresented: $showWhy, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protocoles S.M.A.R.T.").font(.headline)
                        Text("Les disques USB et certains adaptateurs ne transmettent pas les commandes NVMe natives nécessaires pour lire l'état de santé du disque. macOS empêche cet accès pour des raisons de sécurité et de pilotes.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(width: 300)
                }
                
                Button("Exporter le diagnostic") {
                    exportDiagnostic()
                }
                .buttonStyle(.borderedProminent)
                
                if ProcessInfo.processInfo.environment["DISKHEALTH_DEMO"] != "1" {
                    Button("Mode Démo") {
                        restartInDemoMode()
                    }
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func exportDiagnostic() {
        // keep the same
        let diag = Diagnostic(physical: physical)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        guard let data = try? encoder.encode(diag) else { return }
        
        let panel = NSSavePanel()
        panel.title = "Enregistrer le diagnostic DiskHealth"
        let vid = physical.usbVendorID.map { String(format: "0x%04X", $0) } ?? "0xXXXX"
        let pid = physical.usbProductID.map { String(format: "0x%04X", $0) } ?? "0xYYYY"
        panel.nameFieldStringValue = "DiskHealth_Diagnostic_\(vid)_\(pid).json"
        panel.allowedContentTypes = [.json]
        
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
    
    private func restartInDemoMode() {
        let process = Process()
        let executableURL = Bundle.main.executableURL!
        process.executableURL = executableURL
        var env = ProcessInfo.processInfo.environment
        env["DISKHEALTH_DEMO"] = "1"
        process.environment = env
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}
