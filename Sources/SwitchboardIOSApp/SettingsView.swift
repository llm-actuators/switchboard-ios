import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: WireSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("ssh transport") {
                    TextField("host", text: $session.sshHost)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Stepper("port: \(session.sshPort)", value: $session.sshPort, in: 1...65535)
                    TextField("user", text: $session.sshUser)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("password (v0.2; v0.3 = ed25519 key)", text: $session.sshPassword)
                }

                Section("wire identity") {
                    TextField("handle", text: $session.wireHandle)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("primary channel", text: $session.primaryChannel)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section {
                    Button("save & connect") {
                        Task {
                            await session.disconnect()
                            await session.connect()
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Button("disconnect", role: .destructive) {
                        Task { await session.disconnect() }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
    }
}
