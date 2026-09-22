import SwiftUI
import AppKit
import DiskHealthCore

struct UnsupportedDiskView: View {
    let physical: PhysicalDisk
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text(Strings.unsupportedTitle)
                .font(.headline)
            
            VStack(spacing: 12) {
                Text(Strings.unsupportedText1)
                Text(Strings.unsupportedText2)
            }
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)
            
            HStack(spacing: 12) {
                Button(Strings.exportDiagnostic) {
                    exportDiagnostic()
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                
                Button(Strings.viewSupported) {}
                    .buttonStyle(.link)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func exportDiagnostic() {
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
            do {
                try data.write(to: url)
                
                let alert = NSAlert()
                alert.messageText = "Diagnostic exporté"
                alert.informativeText = "Le fichier a été enregistré avec succès. Vous pouvez maintenant l'ajouter à une issue sur GitHub."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Erreur"
                alert.informativeText = "Impossible d'enregistrer le fichier : \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
