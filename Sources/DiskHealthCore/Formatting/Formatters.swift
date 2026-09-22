import Foundation

public enum Formatters {
    private static let frLocale = Locale(identifier: "fr_FR")
    
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        f.countStyle = .decimal
        f.isAdaptive = true
        // The ByteCountFormatter doesn't easily let us hide the fractional part ONLY when 0.
        // We will do a custom formatting for bytes to exactly match the requirement.
        return f
    }()
    
    public static func bytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1_000.0
        let mb = Double(bytes) / 1_000_000.0
        let gb = Double(bytes) / 1_000_000_000.0
        let tb = Double(bytes) / 1_000_000_000_000.0
        
        let val: Double
        let unit: String
        
        if tb >= 1.0 {
            val = tb
            unit = "To"
        } else if gb >= 1.0 {
            val = gb
            unit = "Go"
        } else if mb >= 1.0 {
            val = mb
            unit = "Mo"
        } else if kb >= 1.0 {
            val = kb
            unit = "ko"
        } else {
            val = Double(bytes)
            unit = "octets"
        }
        
        let nf = NumberFormatter()
        nf.locale = frLocale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1
        nf.minimumFractionDigits = 0 // hides if integer
        
        let formattedNumber = nf.string(from: NSNumber(value: val)) ?? "\(val)"
        return "\(formattedNumber) \(unit)"
    }
    
    public static func dataUnitsToBytesText(_ units: UInt64) -> String {
        let b = units * 512_000
        return bytes(b)
    }
    
    public static func integer(_ value: UInt64) -> String {
        let nf = NumberFormatter()
        nf.locale = frLocale
        nf.numberStyle = .decimal
        nf.groupingSeparator = " " // explicitly set space
        return nf.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    public static func hours(_ value: UInt64) -> String {
        return "\(integer(value)) h"
    }
    
    public static func temperature(_ celsius: Int) -> String {
        return "\(celsius) °C"
    }
}
