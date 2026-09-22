import SwiftUI
import AppKit
import DiskHealthCore

enum SidebarItem: Hashable {
    case physicalDisk(String)
    case volume(String)
}

struct ContentView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var selection: SidebarItem?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
                                            print("Copier le résumé")
                                        }
                                        Button("Exporter le rapport…") {
                                            print("Exporter le rapport…")
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
                if let selection = selection {
                    switch selection {
                    case .physicalDisk(let id):
                        if let disk = appManager.disks.first(where: { $0.id == id }) {
                            DiskDetailView(disk: disk)
                        } else {
                            Text("Disque introuvable")
                        }
                    case .volume(let id):
                        if let volume = appManager.volumes.first(where: { $0.id == id }) {
                            Text("Détail du volume \(volume.name)")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Text("Volume introuvable")
                        }
                    }
                } else {
                    Text("Sélectionnez un élément")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .inspector(isPresented: $appManager.showDetails) {
                Text("Inspector")
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        appManager.loadDisks()
                    }) {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Exporter en PDF…") { print("Exporter en PDF…") }
                        Button("Exporter en texte…") { print("Exporter en texte…") }
                        Button("Exporter en JSON…") { print("Exporter en JSON…") }
                        Divider()
                        Button("Copier le résumé") { print("Copier le résumé") }
                    } label: {
                        Label("Exporter", systemImage: "square.and.arrow.up")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        appManager.showDetails.toggle()
                    }) {
                        Label("Détails", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Disk Health")
            .navigationSubtitle("Santé et informations des disques")
        }
        .onReceive(appManager.$disks) { disks in
            if selection == nil, let internalDisk = disks.first(where: { $0.physical.isInternal }) {
                selection = .physicalDisk(internalDisk.id)
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
