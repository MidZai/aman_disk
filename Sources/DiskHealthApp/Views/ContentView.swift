import SwiftUI
import AppKit
import DiskHealthCore



struct ContentView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var exportDisk: RealDisk?
    @State private var exportFormat: ExportFormat = .pdf
    var body: some View {
        NavigationSplitView {
            List(selection: $appManager.selection) {
                if !appManager.disks.isEmpty {
                    Section("Stockage") {
                        ForEach(appManager.disks) { disk in
                            NavigationLink(value: SidebarItem.physicalDisk(disk.id)) {
                                DiskRowView(disk: disk)
                                    .contextMenu {
                                        Button("Actualiser") {
                                            appManager.loadDisks()
                                        }
                                        Button("Copier le résumé") {
                                            ExportService.copySummary(disk: disk)
                                        }
                                        Button("Exporter le rapport…") {
                                            ExportService.exportJSON(disk: disk)
                                        }
                                        Divider()
                                        Button("Afficher dans Utilitaire de disque") {
                                            if let url = URL(string: "file:///System/Applications/Utilities/Disk%20Utility.app") {
                                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                                            }
                                        }
                                    }
                            }
                            
                            let childVolumes = appManager.volumes.filter { $0.physicalDiskBSDNames.contains(disk.physical.bsdName) }
                            ForEach(childVolumes) { volume in
                                NavigationLink(value: SidebarItem.volume(volume.id)) {
                                    VolumeRowView(volume: volume)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                    
                    let orphanVolumes = appManager.volumes.filter { vol in
                        !appManager.disks.contains(where: { vol.physicalDiskBSDNames.contains($0.physical.bsdName) })
                    }
                    
                    if !orphanVolumes.isEmpty {
                        Section("Autres Volumes") {
                            ForEach(orphanVolumes) { volume in
                                NavigationLink(value: SidebarItem.volume(volume.id)) {
                                    VolumeRowView(volume: volume)
                                }
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    SupportButton()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        } detail: {
            Group {
                if appManager.isLoading {
                    ProgressView("Analyse des disques…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else 
                if let selection = appManager.selection {
                    switch selection {
                    case .physicalDisk(let id):
                        if let disk = appManager.disks.first(where: { $0.id == id }) {
                            if disk.snapshot == nil {
                                UnsupportedDiskView(physical: disk.physical)
                            } else {
                                DiskDetailView(disk: disk)
                            }
                        } else {
                            Text("Disque introuvable")
                        }
                    case .volume(let id):
                        if let volume = appManager.volumes.first(where: { $0.id == id }) {
                            VolumeDetailView(volume: volume)
                        } else {
                            Text("Volume introuvable")
                        }
                    }
                } else {
                    Text("Sélectionnez un élément")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.easeInOut, value: appManager.selection)
            .overlay(alignment: .top) {
                ToastView()
            }
            .inspector(isPresented: $appManager.showDetails) {
                if let selection = appManager.selection {
                    InspectorView(selection: selection)
                } else {
                    Text("Aucune sélection")
                        .frame(minWidth: 280, idealWidth: 300, maxWidth: 350, maxHeight: .infinity)
                }
            }
            .sheet(item: $exportDisk) { disk in
                ExportSheet(disk: disk)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        appManager.loadDisks()
                    }) {
                        Label("Actualiser", systemImage: "arrow.clockwise").help("Actualiser la liste des disques")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if let sel = appManager.selection, case .physicalDisk(let id) = sel, let disk = appManager.disks.first(where: { $0.id == id }) {
                        Menu {
                            Button("Exporter en PDF…") { exportDisk = disk; exportFormat = .pdf }
                            Button("Exporter en texte…") { exportDisk = disk; exportFormat = .text }
                            Button("Exporter en JSON…") { exportDisk = disk; exportFormat = .json }
                            Divider()
                            Button("Copier le résumé") { ExportService.copySummary(disk: disk); ToastCenter.shared.show(message: "Résumé copié", systemImage: "doc.on.doc") }
                        } label: {
                            Label("Exporter", systemImage: "square.and.arrow.up").help("Exporter les données du disque")
                        }
                    } else {
                        Menu {
                            Text("Sélectionnez un disque").foregroundColor(.secondary)
                        } label: {
                            Label("Exporter", systemImage: "square.and.arrow.up").help("Exporter les données du disque")
                        }
                        .disabled(true)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        appManager.showDetails.toggle()
                    }) {
                        Label("Détails", systemImage: "info.circle").help("Afficher l'inspecteur de détails (⌘I)")
                    }
                }
            }
            .navigationTitle("Disk Health")
            .navigationSubtitle("Santé et informations des disques")
        }
        .onReceive(appManager.$disks) { disks in
            if appManager.selection == nil, let internalDisk = disks.first(where: { $0.physical.isInternal }) {
                appManager.selection = .physicalDisk(internalDisk.id)
            }
        }
    }
}

enum ExportFormat { case pdf, text, json }

struct ExportSheet: View {
    let disk: RealDisk
    @Environment(\.dismiss) var dismiss
    @State private var format: ExportFormat = .pdf
    @State private var includeSerial: Bool = false
    @State private var includeHistory: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Exporter le rapport")
                .font(.headline)
            
            Picker("Format", selection: $format) {
                Text("PDF").tag(ExportFormat.pdf)
                Text("Texte").tag(ExportFormat.text)
                Text("JSON").tag(ExportFormat.json)
            }
            .pickerStyle(.segmented)
            
            Toggle("Inclure le numéro de série", isOn: $includeSerial)
            Toggle("Inclure l'historique de température (7 jours)", isOn: $includeHistory)
            
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Exporter…") {
                    dismiss()
                    switch format {
                    case .pdf: ExportService.exportPDF(disk: disk, includeSerial: includeSerial, includeHistory: includeHistory)
                    case .text: ExportService.exportText(disk: disk, includeSerial: includeSerial, includeHistory: includeHistory)
                    case .json: ExportService.exportJSON(disk: disk, includeSerial: includeSerial, includeHistory: includeHistory)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420)
    }
}


struct DiskRowView: View {
    @EnvironmentObject var appManager: AppManager
    let disk: RealDisk
    
    var body: some View {
        HStack(spacing: 12) {
            DiskIconProvider.icon(for: disk)
                .font(.system(size: 24))
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(disk.physical.model)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                let sizeStr = Formatters.bytes(disk.physical.sizeBytes)
                let connStr = disk.physical.isInternal ? "Interne" : (disk.physical.connection == .usb ? "USB" : "Externe")
                
                Text("\(sizeStr) · \(connStr)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if appManager.isFusionDriveMember(disk) {
                    Text(Strings.fusionDriveMember)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
                .help(disk.health.status.rawValue.capitalized)
        }
        .padding(.vertical, 4)
    }
    
    // P6: Use HealthStatus extension instead of a duplicated switch.
    private var healthColor: Color { disk.health.status.color }

}

struct VolumeRowView: View {
    let volume: Volume
    
    var body: some View {
        HStack(spacing: 12) {
            DiskIconProvider.icon(for: volume)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .lineLimit(1)
                
                let sizeStr = Formatters.bytes(volume.totalBytes)
                Text("\(volume.format) · \(sizeStr)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SupportButton: View {
    @State private var isHovered = false
    
    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.supportURL)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "heart")
                Text("Soutenir le projet")
            }
            .font(.caption)
            .foregroundColor(isHovered ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .help("Ouvre la page Ko-fi du projet dans votre navigateur")
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
