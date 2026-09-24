import SwiftUI
import DiskHealthCore

// Couleurs, libellés et symboles centralisés : une seule définition pour toutes les vues et rapports.
extension HealthStatus {
    public var color: Color {
        switch self {
        case .good:    return .green
        case .caution: return .orange
        case .bad:     return .red
        case .unknown: return .gray
        }
    }

    public var localizedLabel: String {
        switch self {
        case .good:    return Strings.statusGood
        case .caution: return Strings.statusCaution
        case .bad:     return Strings.statusBad
        case .unknown: return Strings.statusUnknown
        }
    }

    public var symbolName: String {
        switch self {
        case .good:    return "checkmark.circle"
        case .caution: return "exclamationmark.triangle"
        case .bad:     return "xmark.octagon"
        case .unknown: return "questionmark.circle"
        }
    }
}

extension AttributeState {
    /// Couleur du texte dans le tableau S.M.A.R.T.
    var tableColor: Color {
        switch self {
        case .normal, .informational: return .primary
        case .warning:                return .orange
        case .critical:               return .red
        }
    }

    /// Couleur de la pastille d'état.
    var dotColor: Color {
        switch self {
        case .normal:        return .green
        case .informational: return .clear
        case .warning:       return .orange
        case .critical:      return .red
        }
    }

    /// Libellé de la colonne « État ».
    var localizedLabel: String {
        switch self {
        case .normal:        return "Normal"
        case .warning:       return L("Needs attention", "À surveiller")
        case .critical:      return L("Critical", "Critique")
        case .informational: return "—"
        }
    }

    var fontWeight: Font.Weight {
        (self == .warning || self == .critical) ? .semibold : .regular
    }
}

extension TemperatureStatus {
    var color: Color {
        switch self {
        case .normal, .unknown: return .secondary
        case .elevated:         return .orange
        case .critical:         return .red
        }
    }
}

extension PhysicalDisk {
    /// « NVMe », « PCIe AHCI », « SATA »… (une seule définition, auparavant copiée dans 5 vues).
    var interfaceLabel: String {
        switch protocolType {
        case .nvme: return "NVMe"
        case .pcieAhci: return "PCIe AHCI"
        case .ata: return "SATA"
        case .usb: return "USB"
        case .sdCard: return L("SD card", "Carte SD")
        case .virtualDisk: return L("Virtual", "Virtuel")
        case .unknown: break
        }
        switch connection {
        case .nvmeInternal, .nvmeExternal: return "NVMe"
        case .sata: return "SATA"
        case .usb: return "USB"
        case .other: return L("Other", "Autre")
        }
    }

    var locationLabel: String { isInternal ? L("Internal", "Interne") : L("External", "Externe") }

    var mediumLabel: String {
        switch mediumType {
        case .solidState: return "SSD"
        case .rotational: return L("Hard drive", "Disque dur")
        case .unknown: return L("Disk", "Disque")
        }
    }
}
