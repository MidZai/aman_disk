import XCTest
@testable import DiskHealthCore

final class MockRegistryNode: IORegistryNode {
    var bsdName: String?
    var isWhole: Bool
    var className: String
    var conformingClasses: Set<String>
    var parents: [IORegistryNode]
    
    init(
        bsdName: String? = nil,
        isWhole: Bool = false,
        className: String = "IOMedia",
        conformingClasses: Set<String> = [],
        parents: [IORegistryNode] = []
    ) {
        self.bsdName = bsdName
        self.isWhole = isWhole
        self.className = className
        self.conformingClasses = conformingClasses
        self.parents = parents
    }
    
    func conformsTo(className: String) -> Bool {
        self.className == className || conformingClasses.contains(className)
    }
}

final class PhysicalDiskResolverTests: XCTestCase {
    func testSingleStoreContainer() {
        // Physical disk 0
        let disk0 = MockRegistryNode(
            bsdName: "disk0",
            isWhole: true,
            className: "IOMedia",
            conformingClasses: ["IOBlockStorageDevice"]
        )
        // Store partition disk0s2
        let disk0s2 = MockRegistryNode(
            bsdName: "disk0s2",
            isWhole: false,
            className: "IOMedia",
            parents: [disk0]
        )
        // Container Scheme
        let scheme = MockRegistryNode(
            bsdName: nil,
            isWhole: false,
            className: "AppleAPFSContainerScheme",
            conformingClasses: ["AppleAPFSContainerScheme"],
            parents: [disk0s2]
        )
        // Synthetic Container Media disk1
        let media = MockRegistryNode(
            bsdName: "disk1",
            isWhole: true,
            className: "AppleAPFSMedia",
            parents: [scheme]
        )
        // APFS Container
        let container = MockRegistryNode(
            bsdName: nil,
            isWhole: false,
            className: "AppleAPFSContainer",
            parents: [media]
        )
        // APFS Volume disk1s1
        let volume = MockRegistryNode(
            bsdName: "disk1s1",
            isWhole: false,
            className: "AppleAPFSVolume",
            parents: [container]
        )
        
        let physicalDisks = PhysicalDiskResolver.resolvePhysicalDisks(from: volume)
        XCTAssertEqual(physicalDisks, ["disk0"])
    }
    
    func testFusionDriveTwoStoresContainer() {
        // Store 1: SSD (disk0)
        let ssd = MockRegistryNode(
            bsdName: "disk0",
            isWhole: true,
            className: "IOMedia",
            conformingClasses: ["IOBlockStorageDevice"]
        )
        let ssdStore = MockRegistryNode(
            bsdName: "disk0s2",
            isWhole: false,
            className: "IOMedia",
            parents: [ssd]
        )
        
        // Store 2: HDD (disk1)
        let hdd = MockRegistryNode(
            bsdName: "disk1",
            isWhole: true,
            className: "IOMedia",
            conformingClasses: ["IOBlockStorageDevice"]
        )
        let hddStore = MockRegistryNode(
            bsdName: "disk1s2",
            isWhole: false,
            className: "IOMedia",
            parents: [hdd]
        )
        
        // Fusion Drive Container Scheme attaching to both stores
        let scheme = MockRegistryNode(
            bsdName: nil,
            isWhole: false,
            className: "AppleAPFSContainerScheme",
            conformingClasses: ["AppleAPFSContainerScheme"],
            parents: [ssdStore, hddStore]
        )
        
        // Synthetic Media disk2
        let media = MockRegistryNode(
            bsdName: "disk2",
            isWhole: true,
            className: "AppleAPFSMedia",
            parents: [scheme]
        )
        let container = MockRegistryNode(
            bsdName: nil,
            isWhole: false,
            className: "AppleAPFSContainer",
            parents: [media]
        )
        let volume = MockRegistryNode(
            bsdName: "disk2s1",
            isWhole: false,
            className: "AppleAPFSVolume",
            parents: [container]
        )
        
        let physicalDisks = PhysicalDiskResolver.resolvePhysicalDisks(from: volume)
        XCTAssertEqual(physicalDisks, ["disk0", "disk1"])
    }
    
    func testAppleRAIDTwoMembers() {
        let member1Disk = MockRegistryNode(
            bsdName: "disk2",
            isWhole: true,
            className: "IOMedia",
            conformingClasses: ["IOBlockStorageDevice"]
        )
        let member1Part = MockRegistryNode(
            bsdName: "disk2s2",
            isWhole: false,
            className: "IOMedia",
            parents: [member1Disk]
        )
        
        let member2Disk = MockRegistryNode(
            bsdName: "disk3",
            isWhole: true,
            className: "IOMedia",
            conformingClasses: ["IOBlockStorageDevice"]
        )
        let member2Part = MockRegistryNode(
            bsdName: "disk3s2",
            isWhole: false,
            className: "IOMedia",
            parents: [member2Disk]
        )
        
        let raidSet = MockRegistryNode(
            bsdName: nil,
            isWhole: false,
            className: "AppleRAIDSet",
            parents: [member1Part, member2Part]
        )
        let raidVolume = MockRegistryNode(
            bsdName: "disk4",
            isWhole: true,
            className: "IOMedia",
            parents: [raidSet]
        )
        
        let physicalDisks = PhysicalDiskResolver.resolvePhysicalDisks(from: raidVolume)
        XCTAssertEqual(physicalDisks, ["disk2", "disk3"])
    }
    
    func testVolumeBackwardCompatibility() throws {
        // Decode legacy JSON with single physicalDiskBSDName
        let legacyJson = """
        {
            "bsdName": "disk1s1",
            "name": "Macintosh HD",
            "mountPoint": "/",
            "format": "apfs",
            "totalBytes": 500000000000,
            "availableBytes": 250000000000,
            "physicalDiskBSDName": "disk0"
        }
        """.data(using: .utf8)!
        
        let decodedLegacy = try JSONDecoder().decode(Volume.self, from: legacyJson)
        XCTAssertEqual(decodedLegacy.physicalDiskBSDNames, ["disk0"])
        XCTAssertEqual(decodedLegacy.physicalDiskBSDName, "disk0")
        
        // Decode modern JSON with multiple physicalDiskBSDNames
        let modernJson = """
        {
            "bsdName": "disk2s1",
            "name": "Fusion Storage",
            "mountPoint": "/Volumes/Fusion",
            "format": "apfs",
            "totalBytes": 1500000000000,
            "availableBytes": 800000000000,
            "physicalDiskBSDNames": ["disk0", "disk1"]
        }
        """.data(using: .utf8)!
        
        let decodedModern = try JSONDecoder().decode(Volume.self, from: modernJson)
        XCTAssertEqual(decodedModern.physicalDiskBSDNames, ["disk0", "disk1"])
        XCTAssertEqual(decodedModern.physicalDiskBSDName, "disk0")
    }
}
