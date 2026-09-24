import SwiftUI
import DiskHealthCore
import AppKit
import DiskHealthCore

struct DiskCommands: Commands {
    @ObservedObject var appManager: AppManager
    
    init(appManager: AppManager) {
        self.appManager = appManager
    }
    
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About \(AppInfo.name)", "À propos de \(AppInfo.name)")) {
                showAboutPanel()
            }
        }
        
        CommandGroup(after: .help) {
            Button(L("Support Aman Disk on Ko-fi…", "Soutenir Aman Disk sur Ko-fi…")) {
                NSWorkspace.shared.open(AppInfo.supportURL)
            }
        }
        
        CommandGroup(before: .sidebar) {
            Button(L("Health", "Santé")) { appManager.activeTab = .health }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(appManager.selectedDisk == nil)
            Button(L("Performance", "Performances")) { appManager.activeTab = .performance }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(appManager.selectedDisk == nil)
            Divider()
            Button(appManager.showDetails ? L("Hide Details", "Masquer les détails") : L("Show Details", "Afficher les détails")) {
                appManager.showDetails.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            Toggle(L("Raw S.M.A.R.T. Values", "Valeurs brutes S.M.A.R.T."), isOn: $appManager.showRawValues)
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu(L("Drive", "Disque")) {
            Button(L("Refresh", "Actualiser")) {
                appManager.loadDisks()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button(L("Export Report…", "Exporter le rapport…")) {
                NotificationCenter.default.post(name: .amanExportRequested, object: ReportFormat.pdf)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(appManager.selectedDisk == nil)

            Button(L("Copy Summary", "Copier le résumé")) {
                if let disk = appManager.selectedDisk {
                    ExportService.copySummary(disk: disk)
                    ToastCenter.shared.show(message: L("Summary copied", "Résumé copié"), systemImage: "doc.on.doc")
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(appManager.selectedDisk == nil)

            Divider()

            Button(L("Open Data Folder", "Ouvrir le dossier des données")) {
                if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent(AppInfo.bundleIdentifier) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func showAboutPanel() {
        let credits = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 6
        
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        
        let line1 = NSAttributedString(
            string: L("Open source app under the MIT license.\n", "Application open source sous licence MIT.\n"),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let line2 = NSAttributedString(
            string: L("Source code on GitHub\n", "Code source sur GitHub\n"),
            attributes: [
                .font: font,
                .link: AppInfo.repositoryURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let line3 = NSAttributedString(
            string: L("Support the project on Ko-fi\n", "Soutenir le projet sur Ko-fi\n"),
            attributes: [
                .font: font,
                .link: AppInfo.supportURL,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let line4 = NSAttributedString(
            string: L("Aman means “water” in Kabyle. The ring is also the letter ⴰ of the Tifinagh alphabet.\n", "Aman signifie « eau » en kabyle. L'anneau est aussi la lettre ⴰ de l'alphabet tifinagh.\n"),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        let line5 = NSAttributedString(
            string: L("Aman Disk never connects to the Internet.\n", "Aman Disk ne se connecte jamais à Internet.\n"),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        let line6 = NSAttributedString(
            string: L("Free and open source, MIT License.", "Logiciel libre, sous licence MIT."),
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
        credits.append(line5)
        credits.append(line6)
        
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let logoName = isDark ? "aman-disk-logo-sombre@2x" : "aman-disk-logo-clair@2x"
        
        if let url = Bundle.main.url(forResource: logoName, withExtension: "png"), let img = NSImage(contentsOf: url) {
            options[.applicationIcon] = img
        }
        
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
