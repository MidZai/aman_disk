import SwiftUI
import DiskHealthCore

struct VolumeDetailView: View {
    @EnvironmentObject var appManager: AppManager
    let volume: Volume

    private var backingDisks: [RealDisk] {
        volume.physicalDiskBSDNames.compactMap(appManager.disk(withId:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    DiskIconProvider.icon(for: volume)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name)
                            .font(.title2.bold())
                        Text("\(volume.format) · \(Formatters.bytes(volume.totalBytes))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                spaceCard
                infoCard
                if !backingDisks.isEmpty { disksCard }

                HStack {
                    Text(L("Health is measured on the physical drive.", "La santé se mesure au niveau du disque physique."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let canTest = backingDisks.count == 1
                    Button(L("Test This Volume's Performance", "Tester les performances de ce volume")) {
                        guard canTest, let disk = backingDisks.first else { return }
                        appManager.requestedVolumeToTest = volume.id
                        appManager.selection = .physicalDisk(disk.id)
                        appManager.activeTab = .performance
                    }
                    .disabled(!canTest)
                    .help(canTest ? L("Opens the Performance tab with this volume", "Ouvre l'onglet Performances avec ce volume") : L("Can't test a volume spread across several drives.", "Impossible de tester un volume réparti sur plusieurs disques."))
                }
            }
            .padding(24)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var spaceCard: some View {
        // Guarded subtraction: some file systems report more free space than capacity.
        let available = min(volume.availableBytes, volume.totalBytes)
        let used = volume.totalBytes - available
        let ratio = volume.totalBytes > 0 ? Double(used) / Double(volume.totalBytes) : 0
        return card(L("Space", "Espace")) {
            ProgressView(value: ratio)
                .progressViewStyle(.linear)
                .tint(ratio > 0.9 ? .orange : .accentColor)
                .accessibilityLabel(L("Used space", "Espace utilisé"))
                .accessibilityValue(Formatters.percentage(ratio * 100))
            HStack {
                Text(L("\(Formatters.bytes(used)) used of \(Formatters.bytes(volume.totalBytes))", "\(Formatters.bytes(used)) utilisés sur \(Formatters.bytes(volume.totalBytes))"))
                Spacer()
                Text(L("\(Formatters.bytes(available)) available", "\(Formatters.bytes(available)) disponibles"))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .monospacedDigit()
            if volume.physicalDiskBSDNames.count <= 1 {
                Text(L("On APFS, volumes in the same container share the same space.", "Sur APFS, les volumes d'un même conteneur partagent le même espace."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var infoCard: some View {
        card(L("Information", "Informations")) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text(L("Mount point", "Point de montage")).foregroundStyle(.secondary)
                    Text(volume.mountPoint).textSelection(.enabled)
                }
                GridRow {
                    Text("Format").foregroundStyle(.secondary)
                    Text(volume.format)
                }
                GridRow {
                    Text(L("BSD name", "Nom BSD")).foregroundStyle(.secondary)
                    Text(volume.bsdName).textSelection(.enabled)
                }
            }
        }
    }

    private var disksCard: some View {
        card(backingDisks.count > 1 ? L("Physical drives (\(backingDisks.count))", "Disques physiques (\(backingDisks.count))") : L("Physical drive", "Disque physique")) {
            ForEach(backingDisks) { disk in
                HStack(spacing: 12) {
                    DiskIconProvider.icon(for: disk)
                        .font(.system(size: 26))
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(disk.physical.model)
                            .fontWeight(.medium)
                        Label {
                            Text(disk.snapshot == nil ? L("Health not available", "Santé non disponible") : disk.health.status.localizedLabel)
                        } icon: {
                            Circle().fill(disk.snapshot == nil ? Color.gray : disk.health.status.color).frame(width: 8, height: 8)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Show Drive", "Afficher le disque")) {
                        appManager.activeTab = .health
                        appManager.selection = .physicalDisk(disk.id)
                    }
                }
                if disk.id != backingDisks.last?.id { Divider() }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.15)))
    }
}
