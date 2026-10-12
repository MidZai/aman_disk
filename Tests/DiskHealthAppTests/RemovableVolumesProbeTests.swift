import Testing
import Foundation
@testable import DiskHealthApp

/// The probe that triggers the “Removable Volumes” permission must pick volumes by their
/// properties, not by their name, and never touch the boot volume or a network share.
@Suite struct RemovableVolumesProbeTests {
    @Test func bootVolumeIsIdentifiedByAPINotByName() {
        #expect(!RemovableVolumesProbe.shouldTouch(URL(fileURLWithPath: "/")))
    }

    @Test func entriesOnTheBootVolumeAreSkippedWhateverTheirName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // Folders on the boot volume group (whatever their name), a symlink to “/” like the one
        // macOS puts in /Volumes, and a plain file: none of them is a removable volume.
        for name in ["Macintosh HD", "Backup"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Boot"), withDestinationURL: URL(fileURLWithPath: "/"))
        try Data().write(to: root.appendingPathComponent("not-a-volume.txt"))
        #expect(RemovableVolumesProbe.volumesToTouch(in: root).isEmpty)
    }

    @Test func realVolumesDirectoryNeverListsTheBootVolume() {
        let touched = RemovableVolumesProbe.volumesToTouch()
        #expect(touched.allSatisfy { ($0.resolvingSymlinksInPath().path != "/") && RemovableVolumesProbe.shouldTouch($0) })
    }
}
