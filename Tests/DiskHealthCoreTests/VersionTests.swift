import Testing
import Foundation
@testable import DiskHealthCore

/// The VERSION file at the repository root is the single source for build_app.sh and
/// scripts/bundle.sh; the constant the app and diskprobe show must match it.
@Suite struct VersionTests {
    @Test func versionFileMatchesTheConstant() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(file == AmanVersion.current)
        #expect(file.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
    }
}
