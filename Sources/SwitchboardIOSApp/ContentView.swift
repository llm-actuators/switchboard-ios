import SwiftUI


struct ContentView: View {
    @EnvironmentObject private var session: WireSession
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                switch session.connectionState {
                case .disconnected:
                    DisconnectedView(showSettings: $showSettings)
                case .connecting:
                    ProgressView("connecting…")
                case .connected, .streaming:
                    WireView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(session.channels) { ch in
                            Button(action: {
                                Task { await session.openChannel(ch.ch) }
                            }) {
                                HStack {
                                    Text(ch.ch)
                                    Spacer()
                                    Text("\(ch.peersActive)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        Label(session.selectedChannel ?? "channels", systemImage: "list.bullet")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

struct DisconnectedView: View {
    @EnvironmentObject private var session: WireSession
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("switchboard").font(.largeTitle.weight(.semibold))
            if let err = session.lastError {
                Text(err).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if session.sshHost.isEmpty || session.sshUser.isEmpty || session.wireHandle.isEmpty {
                Button("configure connection") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("connect") {
                    Task { await session.connect() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView().environmentObject(WireSession())
}
