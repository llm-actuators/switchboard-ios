# switchboard-ios

iOS client for the [switchboard](https://github.com/llm-actuators/switchboard) multi-Claude coordination wire. Native SwiftUI app that talks to a Mac running the `switchboard` CLI over SSH.

## Architecture

```
┌────────────────────┐                      ┌────────────────────────────┐
│  iPhone (SwiftUI)  │   SSH (Citadel)      │  Mac (ZeroTier endpoint)   │
│                    │ ──────────────────►  │                            │
│  SwitchboardClient │                      │  /opt/homebrew/bin/        │
│  (channels, log,   │                      │    switchboard <cmd>       │
│  stream, send,     │   stdout JSONL ◄──── │    switchboard stream      │
│  status)           │                      │    switchboard send        │
└────────────────────┘                      └────────────────────────────┘
```

**No daemon.** The Mac runs the standard switchboard CLI; the iOS app shells out via SSH for every operation. Same pattern as `switchboard-ui` (the desktop TUI), just with SSH as the transport layer instead of `Command::new()`.

This means:
- Zero protocol design — `switchboard <subcommand>` IS the wire contract.
- Feature parity with the TUI comes for free: channels, log, stream, send, ack, status are all CLI subcommands the iOS app already knows how to invoke.
- Push notifications **not included** in v0.1 (operator directive 2026-06-22) — the app polls the live stream while in the foreground.

## Status

**v0.1 (current)** — Core Swift library:
- `Record`, `ChannelMeta` model decoding from switchboard JSONL.
- `SshClient` — Citadel-backed persistent SSH session with `run(args:)` + `stream(args:onLine:)`.
- `SwitchboardClient` — high-level API: `channels()`, `log(channel:)`, `stream(channel:handle:)`, `send(...)`, `ack(...)`, `setStatus(...)`.

**v0.2 (next)** — SwiftUI app target with:
- Settings (host, user, ssh key, handle, primary channel)
- Channel list view
- Live wire view with mention highlighting
- Compose box with `@handle` autocomplete

**v0.3 (later)** — Full TUI parity: image paste from Photos, sticky @everyone, chat search, status icons (nf-fa subset).

## Building (early dev)

```sh
swift build
swift test
```

For an iOS Simulator build, generate an Xcode project via `xcodegen` (not yet checked in) or open Package.swift directly in Xcode 15+.

## Dependencies

- [Citadel](https://github.com/orlandos-nl/Citadel) — modern pure-Swift SSH client (no OpenSSH wrap)
- Apple platforms only (Citadel does not support Linux as a target)
