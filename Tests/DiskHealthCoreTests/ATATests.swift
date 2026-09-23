import XCTest
@testable import DiskHealthCore

final class ATATests: XCTestCase {
    func makeATASmartData(attributes: [(id: UInt8, flags: UInt16, current: UInt8, worst: UInt8, raw: [UInt8])]) -> Data {
        var data = [UInt8](repeating: 0, count: 512)
        for (i, attr) in attributes.enumerated() {
            if i >= 30 { break }
            let offset = 2 + (i * 12)
            data[offset] = attr.id
            data[offset+1] = UInt8(attr.flags & 0xFF)
            data[offset+2] = UInt8((attr.flags >> 8) & 0xFF)
            data[offset+3] = attr.current
            data[offset+4] = attr.worst
            for j in 0..<min(6, attr.raw.count) {
                data[offset+5+j] = attr.raw[j]
            }
        }
        
        let sum = data.prefix(511).reduce(0) { (UInt16($0) + UInt16($1)) % 256 }
        let checksum = (256 - sum) % 256
        data[511] = UInt8(checksum)
        return Data(data)
    }
    
    func makeATAThresholds(thresholds: [(id: UInt8, threshold: UInt8)]) -> Data {
        var data = [UInt8](repeating: 0, count: 512)
        for (i, t) in thresholds.enumerated() {
            if i >= 30 { break }
            let offset = 2 + (i * 12)
            data[offset] = t.id
            data[offset+1] = t.threshold
        }
        let sum = data.prefix(511).reduce(0) { (UInt16($0) + UInt16($1)) % 256 }
        let checksum = (256 - sum) % 256
        data[511] = UInt8(checksum)
        return Data(data)
    }

    func makeATAIdentify(model: String, rotationRate: Int) -> Data {
        var data = [UInt8](repeating: 0, count: 512)
        
        func writeString(_ str: String, offset: Int, length: Int) {
            let padded = str.padding(toLength: length, withPad: " ", startingAt: 0)
            let bytes = Array(padded.utf8)
            for i in stride(from: 0, to: length, by: 2) {
                data[offset + i] = bytes[i + 1]
                data[offset + i + 1] = bytes[i]
            }
        }
        
        writeString("SERIAL123", offset: 20, length: 20)
        writeString("FIRMWARE", offset: 46, length: 8)
        writeString(model, offset: 54, length: 40)
        
        data[434] = UInt8(rotationRate & 0xFF)
        data[435] = UInt8((rotationRate >> 8) & 0xFF)
        
        return Data(data)
    }

    func testRealFixtureParsing() throws {
        let fixtureURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("ata_apple_sm0512g")
            
        let smartData = try Data(contentsOf: fixtureURL.appendingPathComponent("smart.bin"))
        let thresholdsData = try Data(contentsOf: fixtureURL.appendingPathComponent("thresholds.bin"))
        let identifyData = try Data(contentsOf: fixtureURL.appendingPathComponent("identify.bin"))
        
        let snapshot = ATASmartParser.parse(smartData: smartData, thresholdsData: thresholdsData, identifyData: identifyData, statusExceeded: false)
        XCTAssertNotNil(snapshot)
        
        let snap = snapshot!
        XCTAssertTrue(snap.checksumValid)
        XCTAssertEqual(snap.model, "APPLE SSD SM0512G")
        XCTAssertEqual(snap.rotationRate, 1)
        
        // Assert a few attributes to match reference.json
        let attr9 = snap.attributes.first { $0.id == 9 }!
        XCTAssertEqual(attr9.current, 93)
        XCTAssertEqual(attr9.worst, 93)
        XCTAssertEqual(attr9.threshold, 0)
        XCTAssertEqual(attr9.rawValue, 31483)
    }

    func testHealthRules() {
        let identifyData = makeATAIdentify(model: "Generic Model", rotationRate: 1) // SSD
        
        // Good disk
        let goodAttr = [(id: UInt8(9), flags: UInt16(0), current: UInt8(100), worst: UInt8(100), raw: [UInt8](repeating: 0, count: 6))]
        let smartGood = makeATASmartData(attributes: goodAttr)
        let threshGood = makeATAThresholds(thresholds: [(id: 9, threshold: 0)])
        
        let snapGood = ATASmartParser.parse(smartData: smartGood, thresholdsData: threshGood, identifyData: identifyData, statusExceeded: false)!
        let evalGood = ATAHealthEvaluator.evaluate(snapshot: snapGood)
        XCTAssertEqual(evalGood.status, .good)
        
        // Threshold Exceeded -> Bad
        let snapBadExceeded = ATASmartParser.parse(smartData: smartGood, thresholdsData: threshGood, identifyData: identifyData, statusExceeded: true)!
        let evalBadExceeded = ATAHealthEvaluator.evaluate(snapshot: snapBadExceeded)
        XCTAssertEqual(evalBadExceeded.status, .bad)
        
        // current <= threshold -> Bad
        let badAttr = [(id: UInt8(5), flags: UInt16(0), current: UInt8(10), worst: UInt8(10), raw: [UInt8](repeating: 0, count: 6))]
        let smartBad = makeATASmartData(attributes: badAttr)
        let threshBad = makeATAThresholds(thresholds: [(id: 5, threshold: 20)])
        let snapBadAttr = ATASmartParser.parse(smartData: smartBad, thresholdsData: threshBad, identifyData: identifyData, statusExceeded: false)!
        let evalBadAttr = ATAHealthEvaluator.evaluate(snapshot: snapBadAttr)
        XCTAssertEqual(evalBadAttr.status, .bad)
        
        // Reallocated > 0 -> Caution
        let cautionAttr = [(id: UInt8(5), flags: UInt16(0), current: UInt8(100), worst: UInt8(100), raw: [UInt8]([3, 0, 0, 0, 0, 0]))]
        let smartCaution = makeATASmartData(attributes: cautionAttr)
        let snapCautionAttr = ATASmartParser.parse(smartData: smartCaution, thresholdsData: threshGood, identifyData: identifyData, statusExceeded: false)!
        let evalCautionAttr = ATAHealthEvaluator.evaluate(snapshot: snapCautionAttr)
        XCTAssertEqual(evalCautionAttr.status, HealthStatus.caution)
        
        // Temperature >= 60 for SSD -> Caution
        let tempAttr = [(id: UInt8(0xC2), flags: UInt16(0), current: UInt8(100), worst: UInt8(100), raw: [UInt8]([62, 0, 0, 0, 0, 0]))]
        let smartTemp = makeATASmartData(attributes: tempAttr)
        let snapTemp = ATASmartParser.parse(smartData: smartTemp, thresholdsData: threshGood, identifyData: identifyData, statusExceeded: false)!
        let evalTemp = ATAHealthEvaluator.evaluate(snapshot: snapTemp)
        XCTAssertEqual(evalTemp.status, HealthStatus.caution)
        
        // Checksum invalid
        var badChecksumSmart = smartGood
        badChecksumSmart[511] = 0 // Break checksum
        let snapChecksum = ATASmartParser.parse(smartData: badChecksumSmart, thresholdsData: threshGood, identifyData: identifyData, statusExceeded: false)!
        XCTAssertFalse(snapChecksum.checksumValid)

        var badChecksumThresh = threshGood
        badChecksumThresh[511] = 0 // Break checksum
        let snapThreshChecksum = ATASmartParser.parse(smartData: smartGood, thresholdsData: badChecksumThresh, identifyData: identifyData, statusExceeded: false)!
        XCTAssertFalse(snapThreshChecksum.thresholdsChecksumValid)
        XCTAssertTrue(snapThreshChecksum.checksumValid)
    }

    func testProfiles() {
        let appleProfile = ATACatalog.profile(for: "APPLE SSD SM0512G")
        XCTAssertEqual(appleProfile.name, "AppleSMFamily")
        
        let attrAEInfo = ATACatalog.attributeInfo(id: 0xAE, profile: appleProfile)
        XCTAssertEqual(attrAEInfo.role, .hostReadsBytes(multiplier: 1048576))
        
        let samsungProfile = ATACatalog.profile(for: "Samsung SSD 870 EVO 1TB")
        XCTAssertEqual(samsungProfile.name, "Samsung")   // I2: was wrongly "GenericATA" before fix
        
        let attrB1Info = ATACatalog.attributeInfo(id: 0xB1, profile: samsungProfile)
        XCTAssertEqual(attrB1Info.role, .lifeRemainingPercentNormalized)
    }

    func testDiskHealthSnapshotCodable() throws {
        let snap = ATASmartSnapshot(attributes: [], model: "TestModel", firmware: "FW", serialNumber: "SN", rotationRate: 0, thresholdExceeded: false, checksumValid: true, thresholdsChecksumValid: true)
        let diskSnap = DiskHealthSnapshot.ata(snap)
        let encoded = try JSONEncoder().encode(diskSnap)
        let decoded = try JSONDecoder().decode(DiskHealthSnapshot.self, from: encoded)
        XCTAssertEqual(diskSnap, decoded)

        let legacyJSON = """
        {
            "protocol": "ata",
            "attributes": [],
            "model": "LegacyModel",
            "firmware": "FW",
            "serialNumber": "SN",
            "rotationRate": 0,
            "thresholdExceeded": false,
            "checksumValid": true
        }
        """.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(DiskHealthSnapshot.self, from: legacyJSON)
        if case .ata(let ata) = legacyDecoded {
            XCTAssertEqual(ata.model, "LegacyModel")
            XCTAssertTrue(ata.checksumValid)
            XCTAssertTrue(ata.thresholdsChecksumValid)
        } else {
            XCTFail("Expected .ata snapshot")
        }
    }
}

