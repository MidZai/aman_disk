import SwiftUI
import AppKit
import DiskHealthCore

struct ContentView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var exportRequest: ExportRequest?

    var body: some View {
        if appManager.isMainWindowVisible {
            mainContent
        } else {
            // Fenêtre fermée : rien à mettre à jour (≈ 5 % de processeur économisés en continu).
            Color.clear
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(exportRequest: $exportRequest)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            DetailView()
                .overlay(alignment: .top) { ToastView() }
                .inspector(isPresented: $appManager.showDetails) {
                    InspectorView(selection: appManager.selection)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
                }
                .toolbar { toolbarContent }
                .navigationTitle(AppInfo.name)
                .navigationSubtitle(subtitle)
        }
        .sheet(item: $exportRequest) { request in
            ExportSheet(disk: request.disk, initialFormat: request.format)
        }
        .onReceive(NotificationCenter.default.publisher(for: .amanExportRequested)) { note in
            if let format = note.object as? ReportFormat, let disk = appManager.selectedDisk {
                exportRequest = ExportRequest(disk: disk, format: format)
            }
        }
        .onChange(of: appManager.disks.isEmpty) {
            selectDefaultDiskIfNeeded()
        }
        .onAppear(perform: selectDefaultDiskIfNeeded)
    }

    private var subtitle: String {
        appManager.selectedDisk?.physical.model ?? L("Drive health and performance", "Santé et performances des disques")
    }

    private func selectDefaultDiskIfNeeded() {
        guard appManager.selection == nil else { return }
        if let disk = appManager.bootDisk ?? appManager.disks.first {
            appManager.selection = .physicalDisk(disk.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Les onglets n'ont de sens que pour un disque physique.
            if appManager.selectedDisk != nil {
                Picker(L("View", "Vue"), selection: $appManager.activeTab) {
                    Text(L("Health", "Santé")).tag(DetailTab.health)
                    Text(L("Performance", "Performances")).tag(DetailTab.performance)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                .help(L("Health (⌘1) · Performance (⌘2)", "Santé (⌘1) · Performances (⌘2)"))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appManager.loadDisks()
            } label: {
                if appManager.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L("Refresh", "Actualiser"), systemImage: "arrow.clockwise")
                }
            }
            .help(L("Rescan drives (⌘R)", "Relire les disques (⌘R)"))
            .disabled(appManager.isRefreshing)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let disk = appManager.selectedDisk {
                    Button(L("Export as PDF…", "Exporter en PDF…")) { exportRequest = ExportRequest(disk: disk, format: .pdf) }
                    Button(L("Export as Text…", "Exporter en texte…")) { exportRequest = ExportRequest(disk: disk, format: .text) }
                    Button(L("Export as JSON…", "Exporter en JSON…")) { exportRequest = ExportRequest(disk: disk, format: .json) }
                    Divider()
                    Button(L("Copy Summary", "Copier le résumé")) {
                        ExportService.copySummary(disk: disk)
                        ToastCenter.shared.show(message: L("Summary copied", "Résumé copié"), systemImage: "doc.on.doc")
                    }
                }
            } label: {
                Label(L("Export", "Exporter"), systemImage: "square.and.arrow.up")
            }
            .disabled(appManager.selectedDisk == nil)
            .help(L("Export a report about the drive", "Exporter un rapport sur le disque"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appManager.showDetails.toggle()
            } label: {
                Label(L("Details", "Détails"), systemImage: "info.circle")
            }
            .help(L("Show or hide details (⌘I)", "Afficher ou masquer les détails (⌘I)"))
        }
    }
}

// MARK: - Barre latérale

private struct SidebarView: View {
    @EnvironmentObject var appManager: AppManager
    @Binding var exportRequest: ExportRequest?

    var body: some View {
        List(selection: $appManager.selection) {
            if !appManager.disks.isEmpty {
                Section(AppManager.isDemo ? L("Drives (demo)", "Disques (démo)") : L("Internal drives", "Disques internes")) {
                    ForEach(appManager.disks) { disk in
                        DiskRowView(disk: disk, isFusionMember: appManager.isFusionDriveMember(disk),
                                    isBenchmarking: appManager.benchmark.runningDiskId == disk.id)
                            .tag(SidebarItem.physicalDisk(disk.id))
                            .contextMenu { contextMenu(for: disk) }

                        ForEach(appManager.volumes(on: disk)) { volume in
                            VolumeRowView(volume: volume)
                                .padding(.leading, 16)
                                .tag(SidebarItem.volume(volume.id))
                        }
                    }
                }
            } else if !appManager.isLoading {
                Text(L("No internal drive found", "Aucun disque interne détecté"))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SupportButton()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func contextMenu(for disk: RealDisk) -> some View {
        Button(L("Refresh", "Actualiser")) { appManager.loadDisks() }
        Button(L("Copy Summary", "Copier le résumé")) {
            ExportService.copySummary(disk: disk)
            ToastCenter.shared.show(message: L("Summary copied", "Résumé copié"), systemImage: "doc.on.doc")
        }
        Button(L("Export Report…", "Exporter le rapport…")) { exportRequest = ExportRequest(disk: disk, format: .pdf) }
        Divider()
        Button(L("Open Disk Utility", "Ouvrir Utilitaire de disque")) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Zone de détail

private struct DetailView: View {
    @EnvironmentObject var appManager: AppManager

    var body: some View {
        if appManager.isLoading {
            ProgressView(L("Scanning drives…", "Analyse des disques…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch appManager.selection {
            case .physicalDisk(let id)?:
                if let disk = appManager.disk(withId: id) {
                    // `.id` : chaque disque a sa propre identité de vue (état local, animation de l'anneau).
                    if appManager.activeTab == .performance {
                        PerformanceTabView(disk: disk, appManager: appManager).id(disk.id)
                    } else if disk.snapshot == nil {
                        UnsupportedDiskView(physical: disk.physical).id(disk.id)
                    } else {
                        DiskDetailView(disk: disk).id(disk.id)
                    }
                } else {
                    placeholder(L("This drive is no longer connected", "Ce disque n'est plus connecté"), systemImage: "externaldrive.badge.xmark")
                }
            case .volume(let id)?:
                if let volume = appManager.volumes.first(where: { $0.id == id }) {
                    VolumeDetailView(volume: volume).id(volume.id)
                } else {
                    placeholder(L("This volume is no longer mounted", "Ce volume n'est plus monté"), systemImage: "externaldrive.badge.xmark")
                }
            case nil:
                placeholder(L("Select a drive", "Sélectionnez un disque"), systemImage: "internaldrive")
            }
        }
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Export

enum ReportFormat: String, CaseIterable, Identifiable {
    case pdf, text, json
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pdf: return "PDF"
        case .text: return L("Text", "Texte")
        case .json: return "JSON"
        }
    }
}

struct ExportRequest: Identifiable {
    let id = UUID()
    let disk: RealDisk
    let format: ReportFormat
}

extension Notification.Name {
    /// Demande d'export depuis le menu (⌘E) ; l'objet est le `ReportFormat`.
    static let amanExportRequested = Notification.Name("AmanExportRequested")
}

struct ExportSheet: View {
    let disk: RealDisk
    @Environment(\.dismiss) private var dismiss
    @State private var format: ReportFormat
    @State private var includeSerial = false
    @State private var includeHistory = true

    init(disk: RealDisk, initialFormat: ReportFormat) {
        self.disk = disk
        _format = State(initialValue: initialFormat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Export Report", "Exporter le rapport"))
                    .font(.headline)
                Text(disk.physical.model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Format", selection: $format) {
                ForEach(ReportFormat.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(L("Include serial number", "Inclure le numéro de série"), isOn: $includeSerial)
                Toggle(L("Include temperature history (7 days)", "Inclure l'historique de température (7 jours)"), isOn: $includeHistory)
                    .disabled(disk.historyKey == nil)
            }

            Text(L("The report also includes the latest performance test, if there is one. Nothing is sent anywhere: the file stays on your Mac.", "Le rapport contient aussi le dernier test de performances, s'il existe. Rien n'est envoyé : le fichier reste sur votre Mac."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L("Cancel", "Annuler"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Export…", "Exporter…")) {
                    let options = ExportOptions(includeSerial: includeSerial, includeHistory: includeHistory && disk.historyKey != nil)
                    let chosen = format
                    let disk = disk
                    dismiss()
                    // Le panneau d'enregistrement s'ouvre une fois la feuille refermée.
                    DispatchQueue.main.async {
                        ExportService.export(disk: disk, format: chosen, options: options)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - Lignes de la barre latérale

struct DiskRowView: View {
    let disk: RealDisk
    let isFusionMember: Bool
    let isBenchmarking: Bool

    var body: some View {
        HStack(spacing: 10) {
            DiskIconProvider.icon(for: disk)
                .font(.system(size: 22))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(disk.physical.model)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(Formatters.bytes(disk.physical.sizeBytes)) · \(disk.physical.interfaceLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isFusionMember {
                    Text(Strings.fusionDriveMember)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isBenchmarking {
                ProgressView()
                    .controlSize(.mini)
                    .help(L("Performance test running", "Test de performances en cours"))
            } else if disk.snapshot != nil {
                Circle()
                    .fill(disk.health.status.color)
                    .frame(width: 8, height: 8)
                    .help(disk.health.status.localizedLabel)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue(disk.snapshot != nil ? disk.health.status.localizedLabel : "")
    }
}

struct VolumeRowView: View {
    let volume: Volume

    var body: some View {
        HStack(spacing: 10) {
            DiskIconProvider.icon(for: volume)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(L("\(Formatters.bytes(volume.availableBytes)) available", "\(Formatters.bytes(volume.availableBytes)) disponibles"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}

/// Carte « Soutenir » en bas de la barre latérale : visible sans être envahissante.
struct SupportButton: View {
    @State private var isHovered = false

    private static let tint = Color.pink

    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.supportURL)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Self.tint.gradient, in: Circle())
                    .scaleEffect(isHovered ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Support Aman Disk", "Soutenir Aman Disk"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(L("Free & open source · Ko-fi", "Gratuit et libre · Ko-fi"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0.5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Self.tint.opacity(isHovered ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Self.tint.opacity(0.25)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help(L("Opens the project's Ko-fi page in your browser", "Ouvre la page Ko-fi du projet dans votre navigateur"))
        .accessibilityLabel(L("Support Aman Disk on Ko-fi", "Soutenir Aman Disk sur Ko-fi"))
        .onHover { hovering in
            isHovered = hovering
            // set() et non push()/pop() : un survol interrompu ne laisse pas le curseur main bloqué.
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}
