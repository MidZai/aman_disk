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
                        .frame(width: 64, height: 64)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name)
                            .font(.system(size: 24, weight: .semibold))
                        
                        let sizeStr = Formatters.bytes(volume.totalBytes)
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
                    let usedStr = Formatters.bytes(usedBytes)
                    let totalStr = Formatters.bytes(volume.totalBytes)
                    let availStr = Formatters.bytes(volume.availableBytes)
                    let ratio = volume.totalBytes > 0 ? Double(usedBytes) / Double(volume.totalBytes) : 0
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(0, geo.size.width * ratio))
                        }
                    }
                    .frame(height: 10)
                    
                    HStack {
                        Text("\(usedStr) utilisés sur \(totalStr)")
                        Spacer()
                        Text("\(availStr) disponibles")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                
                let backingDisks = volume.physicalDiskBSDNames.compactMap { bsd in
                    appManager.disks.first(where: { $0.id == bsd })
                }
                
                if !backingDisks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(backingDisks.count > 1 ? "Disques physiques (\(backingDisks.count))" : "Disque physique")
                            .font(.headline)
                        
                        ForEach(backingDisks) { physDisk in
                            HStack(spacing: 12) {
                                DiskIconProvider.icon(for: physDisk)
                                    .font(.system(size: 28))
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
                                    appManager.selection = .physicalDisk(physDisk.id)
                                }
                            }
                            if physDisk.id != backingDisks.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
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
