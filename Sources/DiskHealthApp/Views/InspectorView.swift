import SwiftUI
import DiskHealthCore

struct InspectorView: View {
    @EnvironmentObject var appManager: AppManager
    let selection: SidebarItem
    
    @State private var showSerial = false
    
    var disk: RealDisk? {
        switch selection {
        case .physicalDisk(let id):
            return appManager.disks.first(where: { $0.id == id })
        case .volume(let id):
            let vol = appManager.volumes.first(where: { $0.id == id })
            if let phys = vol?.physicalDiskBSDNames.first {
                return appManager.disks.first(where: { $0.id == phys })
            }
            return nil
        }
    }
    
    var body: some View {
        if let disk = disk {
            Form {
                Section("Identification") {
                    LabeledContent("Modèle", value: disk.physical.model)
                    
                    LabeledContent("N° de série") {
                        HStack {
                            if showSerial {
                                let rawSerial = disk.identify?.serialNumber ?? "—"
                                Text(rawSerial)
                            } else {
                                Text(serialObfuscated)
                            }
                            Button {
                                showSerial.toggle()
                            } label: {
                                Image(systemName: showSerial ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    let fw = disk.identify?.firmwareRevision ?? "—"
                    LabeledContent("Firmware", value: fw)
                    LabeledContent("Nom BSD", value: disk.physical.bsdName)
                }
                
                Section("Capacité") {
                    LabeledContent("Capacité totale", value: formatGB(disk.physical.sizeBytes))
                    if let identify = disk.identify, identify.totalCapacityBytes > 0 {
                        LabeledContent("Espace NVM total", value: formatGB(identify.totalCapacityBytes))
                    }
                }
                
                Section("Températures fabricant") {
                    let warn = disk.identify?.warningTempKelvin ?? 0
                    let crit = disk.identify?.criticalTempKelvin ?? 0
                    let warnStr = warn > 0 ? "\(warn - 273) °C" : "Non défini"
                    let critStr = crit > 0 ? "\(crit - 273) °C" : "Non défini"
                    LabeledContent("Seuil d'alerte", value: warnStr)
                    LabeledContent("Seuil critique", value: critStr)
                }
                
                Section("Connexion") {
                    LabeledContent("Interface", value: interfaceStr(disk.physical))
                    LabeledContent("Emplacement", value: disk.physical.isInternal ? "Interne" : "Externe")
                    if let vid = disk.physical.usbVendorID, let pid = disk.physical.usbProductID {
                        LabeledContent("VID:PID", value: String(format: "0x%04X:0x%04X", vid, pid))
                    }
                }
                
                let diskVolumes = appManager.volumes.filter { $0.physicalDiskBSDNames.contains(disk.id) }
                if !diskVolumes.isEmpty {
                    Section("Volumes") {
                        ForEach(diskVolumes) { vol in
                            Text(vol.name)
                        }
                    }
                }
                
                Section {
                    Button("Copier toutes les informations") {
                        let serialStr = disk.identify?.serialNumber ?? "—"
                        let text = "Modèle: \(disk.physical.model)\nSérie: \(serialStr)\n"
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 280, idealWidth: 300, maxWidth: 350, maxHeight: .infinity)
        } else {
            Text("Aucune information")
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 350, maxHeight: .infinity)
        }
    }
    
    private var serialObfuscated: String {
        guard let s = disk?.identify?.serialNumber, s.count > 4 else {
            return disk?.identify?.serialNumber ?? "—"
        }
        let suffix = s.suffix(4)
        return "••••\(suffix)"
    }
    
    private func formatGB(_ bytes: UInt64) -> String {
        let sizeGB = Double(bytes) / 1_000_000_000.0
        return String(format: "%.1f Go", sizeGB)
    }
    
    private func interfaceStr(_ phys: PhysicalDisk) -> String {
        switch phys.connection {
        case .nvmeInternal, .nvmeExternal: return "NVMe"
        case .sata: return "SATA"
        case .usb: return "USB"
        case .other: return "Autre"
        }
    }
}
