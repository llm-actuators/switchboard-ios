import Foundation

/// Pure suggestion logic for the compose view's `#`-triggered reply
/// autocomplete. Lives in Core (not the App target) so it is unit-testable
/// via `swift test` without a simulator — the App target's ComposeView is
/// only a thin renderer over `suggestions(from:query:)`.
///
/// UX contract: the user types `#` in the compose "reply to" field; the text
/// AFTER the `#` is the `query`. An empty query surfaces the most recent
/// referenceable records; a non-empty query filters them (id / from / subject
/// / body substring, case-insensitive). Selecting one sets the message's
/// `in_reply_to` (wired through `WireSession.send(replyTo:)`).
public enum ReplyAutocomplete {
    /// Kinds that are never useful reply targets — mechanical receipts and
    /// lifecycle/system records. A human replies to a `message` (or an `ack`
    /// / `raise` / `brick` / `hold` / `resume`), never to a `delivered`/`read`.
    static let systemKinds: Set<String> = [
        "delivered", "read", "join", "leave",
        "roster", "ready", "rotated", "status",
    ]

    /// Recent referenceable records matching `query`, most-recent-first,
    /// deduped by id. `query` is the text typed AFTER the leading `#`.
    /// Empty query → most recent referenceable records (up to `limit`).
    public static func suggestions(
        from records: [Record],
        query: String,
        limit: Int = 8
    ) -> [Record] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        var out: [Record] = []
        // records arrive chronological (append-order); most recent = reversed.
        for rec in records.reversed() {
            guard let id = rec.id, !id.isEmpty else { continue }
            guard !systemKinds.contains(rec.kind) else { continue }
            guard !seen.contains(id) else { continue }
            if !q.isEmpty && !matches(rec, id: id, q: q) { continue }
            seen.insert(id)
            out.append(rec)
            if out.count >= limit { break }
        }
        return out
    }

    private static func matches(_ rec: Record, id: String, q: String) -> Bool {
        if id.lowercased().contains(q) { return true }
        if let f = rec.from, f.lowercased().contains(q) { return true }
        if let s = rec.subject, s.lowercased().contains(q) { return true }
        if let b = rec.body, b.lowercased().contains(q) { return true }
        return false
    }

    /// Compact one-line label for a suggestion row: `#<short8>  from · subject`.
    public static func label(for rec: Record) -> String {
        let short = rec.id.map { String($0.prefix(8)) } ?? "?"
        let from = rec.from ?? "?"
        let tailRaw = rec.subject ?? rec.body?.replacingOccurrences(of: "\n", with: " ") ?? ""
        let tail = tailRaw.count > 48 ? String(tailRaw.prefix(48)) + "…" : tailRaw
        return "#\(short)  \(from)\(tail.isEmpty ? "" : " · \(tail)")"
    }
}
