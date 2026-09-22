import Foundation

public struct ATASmartSnapshot {}

public enum DiskHealthSnapshot {
    case nvme(NVMeSmartLog, NVMeIdentify)
    case ata(ATASmartSnapshot)
}
