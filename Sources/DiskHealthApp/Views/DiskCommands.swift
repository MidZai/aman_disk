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
                print("Copier le résumé")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button("Exporter en PDF…") {
                print("Exporter en PDF…")
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
