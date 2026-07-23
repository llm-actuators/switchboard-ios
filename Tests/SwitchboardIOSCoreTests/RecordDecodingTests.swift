import XCTest
@testable import SwitchboardIOSCore

final class RecordDecodingTests: XCTestCase {
    func testDecodeMessage() throws {
        let json = #"""
        {"ts":"2026-06-22T10:00:00.123456Z","ch":"global","kind":"message","id":"abc123def456","from":"toolmaker-5123","to":["operator"],"body":"hello","subject":"test"}
        """#
        let r = try JSONDecoder().decode(Record.self, from: Data(json.utf8))
        XCTAssertEqual(r.ch, "global")
        XCTAssertEqual(r.kind, "message")
        XCTAssertEqual(r.from, "toolmaker-5123")
        XCTAssertEqual(r.to, ["operator"])
        XCTAssertEqual(r.subject, "test")
    }

    func testDecodeStatusWithFlags() throws {
        let json = #"""
        {"ts":"2026-06-22T10:00:00Z","ch":"global","kind":"status","from":"toolmaker-5123","flags":["dev","test"]}
        """#
        let r = try JSONDecoder().decode(Record.self, from: Data(json.utf8))
        XCTAssertEqual(r.kind, "status")
        XCTAssertEqual(r.flags, ["dev", "test"])
    }

    func testDecodeJournalWriteHasEmptyTo() throws {
        let json = #"""
        {"ts":"2026-06-22T10:00:00Z","ch":"global","kind":"message","id":"j1","from":"janitor","body":"journal entry"}
        """#
        let r = try JSONDecoder().decode(Record.self, from: Data(json.utf8))
        XCTAssertEqual(r.to, [])
    }
}
