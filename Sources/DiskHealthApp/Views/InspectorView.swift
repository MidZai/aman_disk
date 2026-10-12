import SwiftUI
import DiskHealthCore

struct InspectorView: View {
    @EnvironmentObject var appManager: AppManager
    let selection: SidebarItem?

    @State private var showSerial = false

    private var disk: RealDisk? {
        switch selection {
        case .physicalDisk(let id)?:
            return appManager.disk(withId: id)
        case .volume(let id)?:
            let volume = appManager.volumes.first { $0.id == id }
            return volume?.physicalDiskBSDNames.first.flatMap(appManager.disk(withId:))
        case .disconnectedDisk(let key)?:
            return appManager.disconnectedDisk(withId: key)?.disk
        case nil:
            return nil
        }
    }

    var body: some View {
        if let disk {
            Form {
                Section(L("Identification", "Identification")) {
                    LabeledContent(L("Model", "Modèle")) {
                        Text(disk.physical.model)
                            .textSelection(.enabled)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    LabeledContent(L("Serial number", "N° de série")) {
                        HStack(spacing: 6) {
                            Text(showSerial ? (disk.serialNumber ?? "—") : SerialMasking.masked(disk.serialNumber))
                                .textSelection(.enabled)
                                .environment(\.layoutDirection, .leftToRight)
                            if disk.serialNumber != nil {
                                Button {
                                    showSerial.toggle()
                                } label: {
                                    Image(systemName: showSerial ? "eye.slash" : "eye").accessibilityHidden(true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showSerial ? L("Hide serial number", "Masquer le numéro de série") : L("Show serial number", "Afficher le numéro de série"))
                            }
                        }
                    }
                    LabeledContent(L("Firmware", "Programme interne")) {
                        Text(disk.firmware ?? "—")
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    LabeledContent(L("BSD name", "Nom BSD")) {
                        Text(disk.physical.bsdName)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }

                Section(L("Capacity", "Capacité")) {
                    LabeledContent(L("Capacity", "Capacité"), value: Formatters.bytes(disk.physical.sizeBytes))
                    if let identify = disk.identify, identify.totalCapacityBytes > 0 {
                        LabeledContent(L("Reported NVMe capacity", "Capacité NVMe annoncée"), value: Formatters.bytes(identify.totalCapacityBytes))
                    }
                }

                Section(L("Temperature thresholds", "Seuils de température")) {
                    let (warning, critical) = temperatureLimits(disk)
                    LabeledContent(L("Warning", "Alerte"), value: warning)
                    LabeledContent(L("Critical", "Critique"), value: critical)
                }

                Section(L("Connection", "Connexion")) {
                    LabeledContent(L("Interface", "Interface"), value: disk.physical.detailInterfaceLabel)
                    LabeledContent(L("Location", "Emplacement"), value: disk.physical.locationLabel)
                    LabeledContent(L("Media", "Support"), value: disk.physical.mediumLabel)
                    if disk.physical.isSATTranslationActive {
                        LabeledContent(L("Driver", "Pilote"), value: "SAT SMART Driver")
                    }
                }

                let diskVolumes = appManager.volumes(on: disk)
                if !diskVolumes.isEmpty {
                    Section(L("Volumes", "Volumes")) {
                        ForEach(diskVolumes) { vol in
                            LabeledContent(vol.name, value: L("\(Formatters.bytes(vol.availableBytes)) free", "\(Formatters.bytes(vol.availableBytes)) libres"))
                        }
                    }
                }

                Section {
                    Button(L("Copy Summary", "Copier le résumé")) {
                        ExportService.copySummary(disk: disk)
                        ToastCenter.shared.show(message: L("Summary copied", "Résumé copié"), systemImage: "doc.on.doc")
                    }
                    .help(L("Copies the status and key figures, without the serial number", "Copie l'état et les indicateurs clés, sans le numéro de série"))
                }
            }
            .formStyle(.grouped)
        } else {
            Text(L("No selection", "Aucune sélection"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Thresholds reported by the drive (NVMe), otherwise the generic thresholds used by the app.
    private func temperatureLimits(_ disk: RealDisk) -> (String, String) {
        if let id = disk.identify, id.warningTempKelvin > 0 || id.criticalTempKelvin > 0 {
            let warning = id.warningTempKelvin > 0 ? Formatters.temperature(Int(id.warningTempKelvin) - 273) : L("Not reported", "Non annoncé")
            let critical = id.criticalTempKelvin > 0 ? Formatters.temperature(Int(id.criticalTempKelvin) - 273) : L("Not reported", "Non annoncé")
            return (L("\(warning) (manufacturer)", "\(warning) (fabricant)"), L("\(critical) (manufacturer)", "\(critical) (fabricant)"))
        }
        let limits = TemperatureStatus.genericThresholds(isRotational: disk.physical.mediumType == .rotational)
        return (L("\(Formatters.temperature(limits.warning)) (default)", "\(Formatters.temperature(limits.warning)) (par défaut)"), L("\(Formatters.temperature(limits.critical)) (default)", "\(Formatters.temperature(limits.critical)) (par défaut)"))
    }
}
