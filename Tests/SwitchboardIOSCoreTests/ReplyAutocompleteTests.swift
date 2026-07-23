import XCTest
@testable import SwitchboardIOSCore

/// Behavioral spec for the `#`-triggered reply autocomplete (compose view).
/// The filter is the real logic behind the UI; these exercise it against
/// realistic wire records (message + mechanical system kinds interleaved).
final class ReplyAutocompleteTests: XCTestCase {
    private func rec(_ json: String) -> Record {
        try! JSONDecoder().decode(Record.self, from: Data(json.utf8))
    }

    /// A realistic slice of a channel log: two human messages bracketed by the
    /// mechanical delivered/read/join records that dominate a real wire.
    private func sampleRecords() -> [Record] {
        [
            rec(#"{"ts":"2026-07-21T10:00:00Z","ch":"triad","kind":"join","from":"advocate"}"#),
            rec(#"{"ts":"2026-07-21T10:00:01Z","ch":"triad","kind":"message","id":"aaa111","from":"operator","to":["overseer-toolmaker"],"subject":"autocomplete ask","body":"need # autocomplete"}"#),
            rec(#"{"ts":"2026-07-21T10:00:02Z","ch":"triad","kind":"delivered","id":"d1","from":"overseer-toolmaker","in_reply_to":"aaa111"}"#),
            rec(#"{"ts":"2026-07-21T10:00:03Z","ch":"triad","kind":"read","id":"r1","from":"overseer-toolmaker","in_reply_to":"aaa111"}"#),
            rec(#"{"ts":"2026-07-21T10:00:04Z","ch":"triad","kind":"message","id":"bbb222","from":"janitor","to":["operator"],"subject":"anti-saga done","body":"codified as doctrine"}"#),
        ]
    }

    func testEmptyQueryReturnsRecentReferenceableOnly_mechanicalExcluded() {
        let out = ReplyAutocomplete.suggestions(from: sampleRecords(), query: "")
        // delivered/read/join are excluded; only the two messages remain.
        XCTAssertEqual(out.compactMap { $0.id }, ["bbb222", "aaa111"], "most-recent-first, system kinds dropped")
    }

    func testQueryFiltersByFrom() {
        let out = ReplyAutocomplete.suggestions(from: sampleRecords(), query: "janitor")
        XCTAssertEqual(out.compactMap { $0.id }, ["bbb222"])
    }

    func testQueryFiltersBySubjectAndBody() {
        XCTAssertEqual(ReplyAutocomplete.suggestions(from: sampleRecords(), query: "anti-saga").compactMap { $0.id }, ["bbb222"])
        XCTAssertEqual(ReplyAutocomplete.suggestions(from: sampleRecords(), query: "autocomplete").compactMap { $0.id }, ["aaa111"])
    }

    func testQueryFiltersByIdSubstring() {
        XCTAssertEqual(ReplyAutocomplete.suggestions(from: sampleRecords(), query: "aaa").compactMap { $0.id }, ["aaa111"])
    }

    func testQueryIsCaseInsensitive() {
        XCTAssertEqual(ReplyAutocomplete.suggestions(from: sampleRecords(), query: "JANITOR").compactMap { $0.id }, ["bbb222"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(ReplyAutocomplete.suggestions(from: sampleRecords(), query: "nonexistent-zzz").isEmpty)
    }

    func testDedupByIdKeepsMostRecent() {
        // Same id appearing twice (e.g. backfill + live-stream overlap) → one row.
        let dup = sampleRecords() + [rec(#"{"ts":"2026-07-21T10:00:05Z","ch":"triad","kind":"message","id":"aaa111","from":"operator","subject":"dupe"}"#)]
        let out = ReplyAutocomplete.suggestions(from: dup, query: "aaa")
        XCTAssertEqual(out.count, 1)
    }

    func testLimitHonored() {
        let many = (0..<20).map { i in
            rec("{\"ts\":\"2026-07-21T10:00:00Z\",\"ch\":\"triad\",\"kind\":\"message\",\"id\":\"m\(i)\",\"from\":\"x\"}")
        }
        XCTAssertEqual(ReplyAutocomplete.suggestions(from: many, query: "", limit: 5).count, 5)
    }

    func testLabelIsCompactAndTruncates() {
        let r = rec(#"{"ts":"2026-07-21T10:00:00Z","ch":"triad","kind":"message","id":"abcdefgh12345","from":"operator","subject":"a very long subject line that should get truncated somewhere past forty eight characters for the row"}"#)
        let label = ReplyAutocomplete.label(for: r)
        XCTAssertTrue(label.hasPrefix("#abcdefgh  operator · "), "label: \(label)")
        XCTAssertTrue(label.hasSuffix("…"), "long subject truncated: \(label)")
    }
}
