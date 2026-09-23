import SwiftUI
import AppKit

struct DiskCommands: Commands {
    @ObservedObject var appManager: AppManager
    
    init(appManager: AppManager) {
        self.appManager = appManager
    }
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("À propos de \(AppInfo.name)") {
                showAboutPanel()
            }
        }
        
        CommandGroup(after: .help) {
            Button("Soutenir Disk Health sur Ko-fi…") {
                NSWorkspace.shared.open(AppInfo.supportURL)
            }
        }
        
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
    
    private func showAboutPanel() {
        let credits = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 6
        
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        
        let line1 = NSAttributedString(
            string: "Application open source sous licence MIT.\n",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let line2 = NSAttributedString(
            string: "Code source sur GitHub\n",
            attributes: [
                .font: font,
                .link: AppInfo.repositoryURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let line3 = NSAttributedString(
            string: "Soutenir le projet sur Ko-fi\n",
            attributes: [
                .font: font,
                .link: AppInfo.supportURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let line4 = NSAttributedString(
            string: "Logiciel libre, sous licence MIT.",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        credits.append(line1)
        credits.append(line2)
        credits.append(line3)
        credits.append(line4)
        
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
    }
}
