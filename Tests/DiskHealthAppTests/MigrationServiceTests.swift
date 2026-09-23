import XCTest
@testable import DiskHealthApp

final class MigrationServiceTests: XCTestCase {
    func testMigration() {
        // Prepare fake old folder
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDir = appSupport.appendingPathComponent("io.github.aman-disk.DiskHealth")
        let newDir = appSupport.appendingPathComponent("io.github.aman-disk.AmanDisk")
        
        // Clean up
        try? fm.removeItem(at: oldDir)
        try? fm.removeItem(at: newDir)
        UserDefaults.standard.removeObject(forKey: "migratedFromDiskHealth")
        
        // Create old dir and a dummy file
        try? fm.createDirectory(at: oldDir.appendingPathComponent("History"), withIntermediateDirectories: true)
        try? "dummy".write(to: oldDir.appendingPathComponent("History").appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
        
        MigrationService.migrateIfNeeded()
        
        XCTAssertTrue(fm.fileExists(atPath: newDir.appendingPathComponent("History").appendingPathComponent("test.txt").path))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "migratedFromDiskHealth"))
        
        // Clean up
        try? fm.removeItem(at: oldDir)
        try? fm.removeItem(at: newDir)
        UserDefaults.standard.removeObject(forKey: "migratedFromDiskHealth")
    }
}
