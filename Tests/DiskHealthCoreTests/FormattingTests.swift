import XCTest
@testable import DiskHealthCore

final class FormattingTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Formatters.bytes(48_300_000_000_000), "48,3 To")
        XCTAssertEqual(Formatters.bytes(2_000_000_000_000), "2 To")
        XCTAssertEqual(Formatters.bytes(512_000_000_000), "512 Go")
        XCTAssertEqual(Formatters.bytes(1_500_000_000), "1,5 Go")
    }
    
    func testInteger() {
        XCTAssertEqual(Formatters.integer(1207), "1 207")
        XCTAssertEqual(Formatters.integer(0), "0")
        XCTAssertEqual(Formatters.integer(2814), "2 814")
    }
    
    func testHoursAndTemperature() {
        XCTAssertEqual(Formatters.hours(2814), "2 814 h")
        XCTAssertEqual(Formatters.temperature(38), "38 °C")
    }
}
