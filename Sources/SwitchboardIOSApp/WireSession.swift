import Foundation
import SwiftUI


/// App-level state holder. Owns the SwitchboardClient and exposes
/// observable record/channel arrays to SwiftUI views. One persistent
/// SSH session for the app's lifetime; long-running `stream` runs in
/// a Task whose lifecycle follows the selected channel.
@MainActor
final class WireSession: ObservableObject {
    // Connection settings — operator-configurable via Settings view.
    @AppStorage("sshHost") var sshHost: String = ""
    @AppStorage("sshPort") var sshPort: Int = 22
    @AppStorage("sshUser") var sshUser: String = ""
    @AppStorage("sshPassword") var sshPassword: String = "" // v0.2 only; v0.3 → key auth
    @AppStorage("wireHandle") var wireHandle: String = ""
    @AppStorage("primaryChannel") var primaryChannel: String = "global"

    @Published var channels: [ChannelMeta] = []
    @Published var records: [Record] = []
    @Published var selectedChannel: String? = nil
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastError: String? = nil

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case streaming(channel: String)
    }

    private var client: SwitchboardClient?
    private var ssh: SshClient?
    private var streamTask: Task<Void, Never>?

    func connect() async {
        guard !sshHost.isEmpty, !sshUser.isEmpty, !wireHandle.isEmpty else {
            lastError = "host / user / handle required in Settings"
            return
        }
        connectionState = .connecting
        let config = SshClient.Config(
            host: sshHost,
            port: sshPort,
            username: sshUser,
            auth: .password(sshPassword) // v0.3 will swap to .privateKey
        )
        let s = SshClient(config: config)
        let c = SwitchboardClient(ssh: s)
        ssh = s
        client = c
        do {
            let chs = try await c.channels()
            channels = chs
            connectionState = .connected
            lastError = nil
            // Auto-open primary channel.
            if let target = chs.first(where: { $0.ch == primaryChannel }) ?? chs.first {
                await openChannel(target.ch)
            }
        } catch {
            lastError = "connect failed: \(error.localizedDescription)"
            connectionState = .disconnected
        }
    }

    func openChannel(_ channel: String) async {
        guard let c = client else { return }
        // Cancel previous stream.
        streamTask?.cancel()
        streamTask = nil
        records = []
        selectedChannel = channel
        do {
            let backfill = try await c.log(channel: channel, last: 100)
            records = backfill
        } catch {
            lastError = "log fetch failed: \(error.localizedDescription)"
        }
        // Launch a long-running stream task. Captured weak so it can be
        // canceled cleanly on channel switch.
        let handle = wireHandle
        connectionState = .streaming(channel: channel)
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await c.stream(
                    channel: channel,
                    handle: handle,
                    onRecord: { [weak self] rec in
                        Task { @MainActor in
                            self?.records.append(rec)
                        }
                    },
                    onStderr: { [weak self] line in
                        Task { @MainActor in
                            self?.lastError = "stream stderr: \(line)"
                        }
                    }
                )
            } catch is CancellationError {
                // graceful
            } catch {
                await MainActor.run {
                    self.lastError = "stream ended: \(error.localizedDescription)"
                    self.connectionState = .connected
                }
            }
        }
    }

    func send(to: [String], subject: String?, replyTo: String? = nil, body: String) async {
        guard let c = client, let channel = selectedChannel else { return }
        do {
            _ = try await c.send(
                channel: channel,
                handle: wireHandle,
                to: to,
                subject: subject,
                replyTo: replyTo,
                body: body
            )
        } catch {
            lastError = "send failed: \(error.localizedDescription)"
        }
    }

    func ack(_ id: String) async {
        guard let c = client, let channel = selectedChannel else { return }
        try? await c.ack(channel: channel, handle: wireHandle, id: id)
    }

    func setStatus(_ flags: [String]) async {
        guard let c = client, let channel = selectedChannel else { return }
        try? await c.setStatus(channel: channel, handle: wireHandle, flags: flags)
    }

    func disconnect() async {
        streamTask?.cancel()
        streamTask = nil
        await ssh?.close()
        ssh = nil
        client = nil
        records = []
        channels = []
        selectedChannel = nil
        connectionState = .disconnected
    }
}
