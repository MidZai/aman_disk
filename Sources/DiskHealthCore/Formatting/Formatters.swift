import Foundation

public enum Formatters {
            public static var locale: Locale = .autoupdatingCurrent
    
    public static func date(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
    
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
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1
        nf.minimumFractionDigits = 0
        
        let formattedNumber = nf.string(from: NSNumber(value: val)) ?? "\(val)"
        return "\(formattedNumber) \(unit)"
    }
    
    public static func dataUnitsToBytesText(_ units: UInt64) -> String {
        let b = units * 512_000
        return bytes(b)
    }
    
    public static func integer(_ value: UInt64) -> String {
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.groupingSeparator = " "
        return nf.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    public static func largeNumber(_ value: UInt64) -> String {
        let million = Double(value) / 1_000_000.0
        let billion = Double(value) / 1_000_000_000.0
        
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1
        nf.minimumFractionDigits = 0
        
        if billion >= 1.0 {
            let numStr = nf.string(from: NSNumber(value: billion)) ?? "\(billion)"
            return "environ \(numStr) Md"
        } else if million >= 1.0 {
            let numStr = nf.string(from: NSNumber(value: million)) ?? "\(million)"
            return "environ \(numStr) M"
        } else {
            return integer(value)
        }
    }
    
    public static func hours(_ value: UInt64) -> String {
        return "\(integer(value)) h"
    }
    
    public static func cycles(_ value: UInt64) -> String {
        return "\(integer(value)) cycles"
    }
    
    public static func temperature(_ celsius: Int) -> String {
        return "\(celsius) °C"
    }
}

extension Formatters {
    public static func speed(_ megabytesPerSecond: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1
        nf.minimumFractionDigits = 0
        let formatted = nf.string(from: NSNumber(value: megabytesPerSecond)) ?? "\(megabytesPerSecond)"
        return "\(formatted) Mo/s"
    }
    
    public static func speedIOPS(_ iops: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        nf.minimumFractionDigits = 0
        nf.groupingSeparator = " "
        let formatted = nf.string(from: NSNumber(value: iops)) ?? "\(iops)"
        return "\(formatted) IOPS"
    }
    
    public static func percentage(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .percent
        nf.maximumFractionDigits = 1
        return nf.string(from: NSNumber(value: value / 100.0)) ?? "\(value) %"
    }
}
