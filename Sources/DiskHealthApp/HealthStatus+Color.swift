import SwiftUI
import DiskHealthCore

// P6: Centralised HealthStatus colour and label, replacing the three duplicate
// switch statements scattered across ContentView, DiskDetailView, and SmartTableView.
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
}

// P6: Centralised AttributeState helpers, replacing the duplicate functions in
// SmartTableView and AttributeCell.
extension AttributeState {
    /// Foreground colour used in the SMART table cells.
    var tableColor: Color {
        switch self {
        case .normal, .informational: return .primary
        case .warning:                return .orange
        case .critical:               return .red
        }
    }

    /// Localised label shown in the "État" column.
    var localizedLabel: String {
        switch self {
        case .normal:        return "Normal"
        case .warning:       return "Attention"
        case .critical:      return "Critique"
        case .informational: return "—"
        }
    }

    /// Font weight for table cells in warning or critical state.
    var fontWeight: Font.Weight {
        (self == .warning || self == .critical) ? .semibold : .regular
    }
}

