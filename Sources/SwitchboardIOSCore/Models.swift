import Foundation

/// A switchboard wire record. Mirrors substrate-distro/switchboard/src/record.rs.
/// The wire emits canonical JSONL: one Record per line.
public struct Record: Codable, Identifiable, Hashable {
    public let ts: Date
    public let ch: String
    public let kind: String
    public let id: String?
    public let inReplyTo: String?
    public let from: String?
    public let to: [String]
    public let body: String?
    public let handle: String?
    public let subject: String?
    public let flags: [String]

    enum CodingKeys: String, CodingKey {
        case ts, ch, kind, id, from, to, body, handle, subject, flags
        case inReplyTo = "in_reply_to"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tsString = try c.decode(String.self, forKey: .ts)
        // Wire stamps RFC3339 with fractional seconds; ISO8601DateFormatter
        // tolerates both Z and +HH:MM suffixes.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: tsString) {
            self.ts = d
        } else {
            iso.formatOptions = [.withInternetDateTime]
            self.ts = iso.date(from: tsString) ?? Date()
        }
        self.ch = try c.decode(String.self, forKey: .ch)
        self.kind = try c.decode(String.self, forKey: .kind)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.inReplyTo = try c.decodeIfPresent(String.self, forKey: .inReplyTo)
        self.from = try c.decodeIfPresent(String.self, forKey: .from)
        self.to = (try? c.decode([String].self, forKey: .to)) ?? []
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.handle = try c.decodeIfPresent(String.self, forKey: .handle)
        self.subject = try c.decodeIfPresent(String.self, forKey: .subject)
        self.flags = (try? c.decode([String].self, forKey: .flags)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try c.encode(iso.string(from: ts), forKey: .ts)
        try c.encode(ch, forKey: .ch)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(inReplyTo, forKey: .inReplyTo)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(handle, forKey: .handle)
        try c.encodeIfPresent(subject, forKey: .subject)
        if !flags.isEmpty { try c.encode(flags, forKey: .flags) }
    }
}

/// Channel metadata — one entry per channel directory in the cache.
/// Decoded from `switchboard channels --all` JSONL output.
public struct ChannelMeta: Codable, Identifiable, Hashable {
    public var id: String { ch }
    public let ch: String
    public let peersActive: Int
    public let lastEventTs: Date?
    public let about: String?

    enum CodingKeys: String, CodingKey {
        case ch, about
        case peersActive = "peers_active"
        case lastEventTs = "last_event_ts"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ch = try c.decode(String.self, forKey: .ch)
        self.peersActive = (try? c.decode(Int.self, forKey: .peersActive)) ?? 0
        if let tsString = try? c.decode(String.self, forKey: .lastEventTs) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.lastEventTs = iso.date(from: tsString)
        } else {
            self.lastEventTs = nil
        }
        self.about = try? c.decode(String.self, forKey: .about)
    }
}
