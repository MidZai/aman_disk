import Foundation

public struct ActivityData {
    public let writtenStr: String?
    public let readStr: String?
    public let lifeRemaining: Int?
    
    public init(snapshot: DiskHealthSnapshot) {
        switch snapshot {
        case .nvme(let smart, _):
            let writtenTB = Double(smart.dataUnitsWritten) * 512_000.0 / 1_000_000_000_000.0
            let readTB = Double(smart.dataUnitsRead) * 512_000.0 / 1_000_000_000_000.0
            writtenStr = String(format: "%.1f To", writtenTB)
            readStr = String(format: "%.1f To", readTB)
            lifeRemaining = Int(100 - smart.percentageUsed)
        case .ata(let ataSnap):
            let profile = ATACatalog.profile(for: ataSnap.model)
            var w: UInt64? = nil
            var r: UInt64? = nil
            var life: Int? = nil
            
            for attr in ataSnap.attributes {
                let info = ATACatalog.attributeInfo(id: attr.id, profile: profile)
                if case .hostWritesBytes(let mult) = info.role {
                    w = attr.rawValue * mult
                } else if case .hostReadsBytes(let mult) = info.role {
                    r = attr.rawValue * mult
                } else if info.role == .lifeRemainingPercentNormalized {
                    life = Int(attr.current)
                }
            }
            
            if let w = w {
                let tb = Double(w) / 1_000_000_000_000.0
                writtenStr = String(format: "%.1f To", tb)
            } else { writtenStr = nil }
            
            if let r = r {
                let tb = Double(r) / 1_000_000_000_000.0
                readStr = String(format: "%.1f To", tb)
            } else { readStr = nil }
            
            lifeRemaining = life
        }
    }
}
