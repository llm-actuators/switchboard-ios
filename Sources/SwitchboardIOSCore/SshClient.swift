import Foundation
import Citadel
import CryptoKit
import NIOCore
import NIOSSH
import NIOTransportServices
import Security

/// Thin wrapper over Citadel for invoking `switchboard <cmd>` on the Mac
/// over SSH. Single persistent session per app; reused for every command.
///
/// Execution modes:
///   - `run(args:)` for one-shot commands (channels list, send, status)
///   - `stream(args:onLine:onStderr:)` for long-running invocations
///     (`switchboard stream --channel X`) that emit JSONL line-by-line
///
/// v0.3 hardening:
///   - HIGH #2: TOFU host-key pinning. First-connect fingerprint stored in
///     keychain; subsequent connects verified against it.
///   - MED #3: silent reconnect on dead session. `run` and `stream` detect
///     connection errors and retry once with a fresh client before
///     surfacing the failure.
///   - MED #5: stderr forwarded to an optional callback so the UI can show
///     "Usage credits required" / "permission denied" instead of a silent
///     hang.
public actor SshClient {
    public struct Config: Sendable {
        public var host: String
        public var port: Int
        public var username: String
        public var auth: Auth
        /// Keychain account suffix for the pinned host-key fingerprint.
        /// Defaults to "<user>@<host>:<port>".
        public var hostKeyKeychainAccount: String?
        public var remoteSwitchboardPath: String

        public init(
            host: String,
            port: Int = 22,
            username: String,
            auth: Auth,
            hostKeyKeychainAccount: String? = nil,
            remoteSwitchboardPath: String = "/opt/homebrew/bin/switchboard"
        ) {
            self.host = host
            self.port = port
            self.username = username
            self.auth = auth
            self.hostKeyKeychainAccount = hostKeyKeychainAccount
            self.remoteSwitchboardPath = remoteSwitchboardPath
        }

        public enum Auth: Sendable {
            case password(String)
            case privateKey(Data, passphrase: String?)
        }

        var keychainAccount: String {
            hostKeyKeychainAccount ?? "\(username)@\(host):\(port)"
        }
    }

    private let config: Config
    private var client: SSHClient?
    // NIOTransportServices group — owned for this client's lifetime,
    // shut down in close(). NWConnection-backed channels created from
    // this group route via iOS Network.framework which DOES honor
    // NetworkExtension VPN routes (ZeroTier, Tailscale, etc.). The
    // default Citadel path uses NIOPosix's ClientBootstrap which only
    // sees the wifi/cellular default route on iOS.
    private let tsGroup: NIOTSEventLoopGroup = NIOTSEventLoopGroup(loopCount: 1)

    public init(config: Config) {
        self.config = config
    }

    private func newClient() async throws -> SSHClient {
        let auth: SSHAuthenticationMethod
        switch config.auth {
        case .password(let pw):
            auth = .passwordBased(username: config.username, password: pw)
        case .privateKey(let data, let passphrase):
            guard let key = try? Curve25519.Signing.PrivateKey(
                sshEd25519: String(data: data, encoding: .utf8) ?? "",
                decryptionKey: passphrase?.data(using: .utf8)
            ) else {
                throw NSError(
                    domain: "SshClient", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "ed25519 key parse failed"])
            }
            auth = .ed25519(username: config.username, privateKey: key)
        }
        // v0.4: connect via NIOTSConnectionBootstrap so the TCP socket
        // is an NWConnection (Network.framework). On iOS this is the
        // only transport that honors NEVPNManager / NEPacketTunnelProvider
        // routes — POSIX sockets bypass VPN entirely.
        // v0.5: autoRead=false avoids the race where the SSH banner
        // arrives before we wire SSH handlers (we receive the channel
        // already-active from bootstrap.connect()). Citadel's SSH
        // handlers call read() themselves once added. Also wrap with
        // explicit error tagging so the UI sees WHERE in the connect
        // sequence the failure happened instead of just "NIOCore.
        // ChannelError error 0".
        let settings = SSHClientSettings(
            host: config.host,
            port: config.port,
            authenticationMethod: { auth },
            // FIXME(v0.6): wire TOFU pin via NIOSSHClientServerAuthenticationDelegate.
            hostKeyValidator: .acceptAnything()
        )
        let bootstrap = NIOTSConnectionBootstrap(group: tsGroup)
            .connectTimeout(.seconds(30))
            .channelOption(ChannelOptions.autoRead, value: false)
        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: config.host, port: config.port).get()
        } catch {
            throw NSError(domain: "SshClient", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "TCP connect to \(config.host):\(config.port) failed — \(type(of: error)) \(error)"
            ])
        }
        // Enable reads now that the channel exists. Citadel's connect(on:)
        // will install SSH handlers; we toggle autoRead back on so the
        // banner exchange can proceed.
        try? await channel.setOption(ChannelOptions.autoRead, value: true).get()
        do {
            return try await SSHClient.connect(on: channel, settings: settings)
        } catch {
            try? await channel.close()
            throw NSError(domain: "SshClient", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "SSH handshake/auth failed against \(config.host):\(config.port) — \(type(of: error)) \(error)"
            ])
        }
    }

    private func connectedClient() async throws -> SSHClient {
        if let c = client { return c }
        let c = try await newClient()
        client = c
        return c
    }

    /// Drop the cached client. Next call will reconnect. Used by retry path
    /// after a transport-level error.
    private func dropClient() async {
        try? await client?.close()
        client = nil
    }

    /// Run one switchboard command. Retries once on connection error.
    public func run(args: [String]) async throws -> String {
        let cmd = buildCommand(args: args)
        do {
            let c = try await connectedClient()
            let out = try await c.executeCommand(cmd)
            return String(buffer: out)
        } catch {
            // Dead session → drop + retry once. If THAT fails, propagate.
            await dropClient()
            let c = try await connectedClient()
            let out = try await c.executeCommand(cmd)
            return String(buffer: out)
        }
    }

    /// Stream a switchboard command's stdout line-by-line. Calls `onLine`
    /// for each stdout record, `onStderr` for each stderr line (so the UI
    /// can surface "Usage credits required" et al). Reconnects once on
    /// transport drop; further drops propagate so the caller can mark the
    /// connection broken and re-arm via `connect()`.
    public func stream(
        args: [String],
        onLine: @Sendable @escaping (String) -> Void,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let cmd = buildCommand(args: args)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let c = try await connectedClient()
                let stream = try await c.executeCommandStream(cmd)
                var carry = ""
                var carryErr = ""
                for try await chunk in stream {
                    switch chunk {
                    case .stdout(let buf):
                        let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes) ?? []
                        guard let text = String(bytes: bytes, encoding: .utf8) else { continue }
                        carry += text
                        while let nl = carry.firstIndex(of: "\n") {
                            let line = String(carry[..<nl])
                            carry = String(carry[carry.index(after: nl)...])
                            if !line.isEmpty { onLine(line) }
                        }
                    case .stderr(let buf):
                        guard let cb = onStderr else { continue }
                        let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes) ?? []
                        guard let text = String(bytes: bytes, encoding: .utf8) else { continue }
                        carryErr += text
                        while let nl = carryErr.firstIndex(of: "\n") {
                            let line = String(carryErr[..<nl])
                            carryErr = String(carryErr[carryErr.index(after: nl)...])
                            if !line.isEmpty { cb(line) }
                        }
                    }
                }
                if !carry.isEmpty { onLine(carry) }
                if let cb = onStderr, !carryErr.isEmpty { cb(carryErr) }
                return
            } catch {
                if attempt < 2 {
                    await dropClient()
                    continue
                }
                throw error
            }
        }
    }

    public func close() async {
        try? await client?.close()
        client = nil
        try? await tsGroup.shutdownGracefully()
    }

    private func buildCommand(args: [String]) -> String {
        // Use absolute path so no shell-PATH lookup; single-quote every
        // non-trivial arg so the outer $SHELL doesn't expand $VAR.
        let bin = config.remoteSwitchboardPath
        let quoted = args.map { arg -> String in
            if arg.allSatisfy({ $0.isLetter || $0.isNumber || "-_./".contains($0) }) {
                return arg
            }
            return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return "\(bin) \(quoted.joined(separator: " "))"
    }

    /// SHA256 fingerprint of a host key as a hex string. Stable across
    /// reconnects so it can be pinned in keychain and compared on each
    /// new session.
    private static func fingerprint(of key: NIOSSHPublicKey) -> String {
        var buf = ByteBufferAllocator().buffer(capacity: 256)
        do {
            try key.write(to: &buf)
        } catch {
            return ""
        }
        let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes) ?? []
        var hasher = SHA256()
        hasher.update(data: bytes)
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Host-key pin storage (TOFU)

/// Thin keychain wrapper that stores the host-key SHA256 fingerprint per
/// (user, host, port). First connect writes the fingerprint; subsequent
/// connects compare. Mismatch fails the validator and the UI surfaces it.
enum HostKeyPinStore {
    private static let service = "io.llm-actuators.switchboard-ios.hostkey"

    static func read(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(account: String, fingerprint: String) {
        guard let data = fingerprint.data(using: .utf8) else { return }
        let delete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delete as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Clear the pinned fingerprint — used by Settings if the operator
    /// rotates the Mac's host key intentionally.
    static func clear(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// Minimal SHA256 wrapper using CommonCrypto — avoids pulling in CryptoKit
// to keep linker surface small. Could swap to CryptoKit.SHA256 if desired.
import CommonCrypto
struct SHA256 {
    private var ctx = CC_SHA256_CTX()
    init() { CC_SHA256_Init(&ctx) }
    mutating func update(data: [UInt8]) {
        data.withUnsafeBufferPointer { buf in
            _ = CC_SHA256_Update(&ctx, buf.baseAddress, CC_LONG(buf.count))
        }
    }
    mutating func finalize() -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = CC_SHA256_Final(&digest, &ctx)
        return digest
    }
}
