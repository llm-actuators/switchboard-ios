import Foundation

/// High-level switchboard operations. Composed over SshClient: every
/// method maps to a `switchboard <subcommand>` invocation on the Mac.
/// Stateless on its own — caller-owned handle + channel are passed in.
public actor SwitchboardClient {
    private let ssh: SshClient
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public init(ssh: SshClient) {
        self.ssh = ssh
    }

    // MARK: - Channels

    /// `switchboard channels --all` → list of channels with metadata.
    public func channels() async throws -> [ChannelMeta] {
        let out = try await ssh.run(args: ["channels", "--all"])
        return out
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(ChannelMeta.self, from: data)
            }
    }

    // MARK: - Log + Stream

    /// `switchboard log --last N --channel X` → backfill records.
    public func log(channel: String, last: Int = 100) async throws -> [Record] {
        let out = try await ssh.run(args: [
            "log", "--last", "\(last)", "--channel", channel,
        ])
        return parse(jsonl: out)
    }

    /// `switchboard stream --channel X --from-cursor --full --handle <h>`
    /// — long-running. Calls onRecord for each parsed Record; onStderr for
    /// any error chatter the CLI emits ("Usage credits required", etc.).
    public func stream(
        channel: String,
        handle: String,
        onRecord: @Sendable @escaping (Record) -> Void,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws {
        try await ssh.stream(
            args: [
                "--handle", handle, "--channel", channel,
                "stream", "--from-cursor", "--full",
            ],
            onLine: { line in
                guard let data = line.data(using: .utf8) else { return }
                if let rec = try? JSONDecoder().decode(Record.self, from: data) {
                    onRecord(rec)
                }
            },
            onStderr: onStderr
        )
    }

    // MARK: - Send / Ack

    /// `switchboard send --handle h --channel ch [--to ...] [--subject ...] [--reply-to ...] body`
    /// Returns the id printed on stdout.
    public func send(
        channel: String,
        handle: String,
        to: [String] = [],
        subject: String? = nil,
        replyTo: String? = nil,
        body: String
    ) async throws -> String {
        var args = ["--handle", handle, "--channel", channel, "send"]
        if !to.isEmpty {
            args += ["--to", to.joined(separator: ",")]
        }
        if let s = subject, !s.isEmpty {
            args += ["--subject", s]
        }
        if let r = replyTo, !r.isEmpty {
            args += ["--reply-to", r]
        }
        args.append(body)
        let out = try await ssh.run(args: args)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func ack(channel: String, handle: String, id: String) async throws {
        _ = try await ssh.run(args: [
            "--handle", handle, "--channel", channel, "ack", id,
        ])
    }

    // MARK: - Status

    /// `switchboard status <flags>` — flags=[] means clear (idle).
    public func setStatus(channel: String, handle: String, flags: [String]) async throws {
        let arg = flags.isEmpty ? "clear" : flags.joined(separator: ",")
        _ = try await ssh.run(args: [
            "--handle", handle, "--channel", channel, "status", arg,
        ])
    }

    // MARK: - Helpers

    private func parse(jsonl: String) -> [Record] {
        jsonl
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(Record.self, from: data)
            }
    }
}
