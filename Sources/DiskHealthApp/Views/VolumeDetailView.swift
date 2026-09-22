import SwiftUI
import DiskHealthCore

struct VolumeDetailView: View {
    @EnvironmentObject var appManager: AppManager
    
    
    let volume: Volume
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    DiskIconProvider.icon(for: volume)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name)
                            .font(.system(size: 22, weight: .semibold))
                        
                        let sizeGB = Double(volume.totalBytes) / 1_000_000_000.0
                        let sizeStr = String(format: "%.1f Go", sizeGB)
                        Text("\(volume.format) · \(sizeStr)")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Espace").font(.headline)
                    
                    let usedBytes = volume.totalBytes - volume.availableBytes
                    let usedGB = Double(usedBytes) / 1_000_000_000.0
                    let totalGB = Double(volume.totalBytes) / 1_000_000_000.0
                    let availGB = Double(volume.availableBytes) / 1_000_000_000.0
                    let ratio = volume.totalBytes > 0 ? Double(usedBytes) / Double(volume.totalBytes) : 0
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.2))
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(0, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 10)
                    
                    HStack {
                        Text(String(format: "%.1f Go utilisés sur %.1f Go", usedGB, totalGB))
                        Spacer()
                        Text(String(format: "%.1f Go disponibles", availGB))
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Informations").font(.headline)
                    
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("Point de montage").foregroundColor(.secondary)
                            Text(volume.mountPoint)
                        }
                        GridRow {
                            Text("Format").foregroundColor(.secondary)
                            Text(volume.format)
                        }
                        GridRow {
                            Text("Nom BSD").foregroundColor(.secondary)
                            Text(volume.bsdName)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                if let physID = volume.physicalDiskBSDName, let physDisk = appManager.disks.first(where: { $0.id == physID }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Disque physique").font(.headline)
                        
                        HStack(spacing: 12) {
                            DiskIconProvider.icon(for: physDisk)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                            
                            VStack(alignment: .leading) {
                                Text(physDisk.physical.model)
                                    .fontWeight(.medium)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(healthColor(for: physDisk))
                                        .frame(width: 8, height: 8)
                                    Text(healthLabel(for: physDisk))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button("Afficher le disque") {
                                appManager.selection = .physicalDisk(physID)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                
                Text("La santé se mesure au niveau du disque physique.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .top)
            .frame(maxWidth: .infinity)
        }
    }
    
    private func healthColor(for disk: RealDisk) -> Color {
        switch disk.health.status {
        case .good: return .green
        case .caution: return .orange
        case .bad: return .red
        case .unknown: return .gray
        }
    }
    
    private func healthLabel(for disk: RealDisk) -> String {
        switch disk.health.status {
        case .good: return "En bonne santé"
        case .caution: return "Attention"
        case .bad: return "Critique"
        case .unknown: return "Inconnu"
        }
    }
}
