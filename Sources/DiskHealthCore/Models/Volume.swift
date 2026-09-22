import Foundation

public struct Volume: Codable, Identifiable, Hashable {
    public var id: String { bsdName }
    public let bsdName: String
    public let name: String
    public let mountPoint: String
    public let format: String
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let physicalDiskBSDName: String?
    
    public init(bsdName: String, name: String, mountPoint: String, format: String, totalBytes: UInt64, availableBytes: UInt64, physicalDiskBSDName: String?) {
        self.bsdName = bsdName
        self.name = name
        self.mountPoint = mountPoint
        self.format = format
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.physicalDiskBSDName = physicalDiskBSDName
    }
}
