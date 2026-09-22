import SwiftUI
import AppKit
import DiskHealthCore



struct ContentView: View {
    @EnvironmentObject var appManager: AppManager
    
    
    var body: some View {
        NavigationSplitView {
            List(selection: $appManager.selection) {
                if !appManager.disks.isEmpty {
                    Section("Disques physiques") {
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
                        }
                    }
                }
                
                if !appManager.volumes.isEmpty {
                    Section("Volumes") {
                        ForEach(appManager.volumes) { volume in
                            NavigationLink(value: SidebarItem.volume(volume.id)) {
                                VolumeRowView(volume: volume)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .listStyle(.sidebar)
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
                            if disk.smart == nil {
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
            .inspector(isPresented: $appManager.showDetails) {
                if let selection = appManager.selection {
                    InspectorView(selection: selection)
                } else {
                    Text("Aucune sélection")
                        .frame(minWidth: 280, idealWidth: 300, maxWidth: 350, maxHeight: .infinity)
                }
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
                            Button("Exporter en PDF…") { print("Non implémenté") }
                            Button("Exporter en texte…") { print("Non implémenté") }
                            Button("Exporter en JSON…") { ExportService.exportJSON(disk: disk) }
                            Divider()
                            Button("Copier le résumé") { ExportService.copySummary(disk: disk) }
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
                        Label("Détails", systemImage: "info.circle").help("Afficher l'inspecteur de détails")
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

struct DiskRowView: View {
    let disk: RealDisk
    
    var body: some View {
        HStack(spacing: 8) {
            DiskIconProvider.icon(for: disk)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(disk.physical.model)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                                // Formatters doesn't have a formatBytes... Oh wait, in Phase 1 I might have done it. Let's just use a basic division.
                let sizeGB = Double(disk.physical.sizeBytes) / 1_000_000_000.0
                let sizeStr = String(format: "%.1f Go", sizeGB)
                let connStr = disk.physical.isInternal ? "Interne" : (disk.physical.connection == .usb ? "USB" : "Externe")
                
                Text("\(sizeStr) · \(connStr)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
                .help(disk.health.status.rawValue.capitalized)
        }
        .padding(.vertical, 2)
    }
    
    private var healthColor: Color {
        switch disk.health.status {
        case .good: return .green
        case .caution: return .orange
        case .bad: return .red
        case .unknown: return .gray
        }
    }
}

struct VolumeRowView: View {
    let volume: Volume
    
    var body: some View {
        HStack(spacing: 8) {
            DiskIconProvider.icon(for: volume)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(volume.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                let sizeGB = Double(volume.totalBytes) / 1_000_000_000.0
                let sizeStr = String(format: "%.1f Go", sizeGB)
                Text("\(volume.format) · \(sizeStr)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
