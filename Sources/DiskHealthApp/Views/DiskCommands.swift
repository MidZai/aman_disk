import SwiftUI

struct DiskCommands: Commands {
    @ObservedObject var appManager: AppManager
    
    init(appManager: AppManager) {
        self.appManager = appManager
    }
    
    var body: some Commands {
        CommandMenu("Disque") {
            Button("Actualiser") {
                appManager.loadDisks()
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Button("Copier le résumé") {
                if case .physicalDisk(let id) = appManager.selection, let disk = appManager.disks.first(where: { $0.id == id }) {
                    ExportService.copySummary(disk: disk)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button("Exporter le rapport (JSON)…") {
                if case .physicalDisk(let id) = appManager.selection, let disk = appManager.disks.first(where: { $0.id == id }) {
                    ExportService.exportJSON(disk: disk)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            
            Divider()
            
            Button("Afficher les détails") {
                appManager.showDetails.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            
            Toggle("Afficher les valeurs brutes", isOn: $appManager.showRawValues)
                .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}
