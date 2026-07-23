import SwiftUI

struct ComposeView: View {
    @EnvironmentObject private var session: WireSession
    @Environment(\.dismiss) private var dismiss
    @State private var to: String = ""
    @State private var subject: String = ""
    @State private var messageBody: String = ""
    @State private var replyToId: String? = nil
    @State private var replyQuery: String = ""
    @State private var sending = false

    /// `#`-triggered: suggestions appear only once the field starts with `#`;
    /// the text after `#` filters recent referenceable records.
    private var replySuggestions: [Record] {
        guard replyQuery.hasPrefix("#") else { return [] }
        return ReplyAutocomplete.suggestions(from: session.records, query: String(replyQuery.dropFirst()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("to") {
                    TextField("comma-separated handles (or 'everyone')", text: $to)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section("reply to (optional)") {
                    if let rid = replyToId {
                        HStack {
                            Text(session.records.last(where: { $0.id == rid }).map(ReplyAutocomplete.label(for:)) ?? "#\(rid)")
                                .font(.footnote.monospaced())
                                .lineLimit(1)
                            Spacer()
                            Button {
                                replyToId = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("type # to reply to a message", text: $replyQuery)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.body.monospaced())
                        ForEach(replySuggestions) { rec in
                            Button {
                                replyToId = rec.id
                                replyQuery = ""
                            } label: {
                                Text(ReplyAutocomplete.label(for: rec))
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                Section("subject (optional)") {
                    TextField("", text: $subject)
                }
                Section("body") {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 120)
                        .font(.body.monospaced())
                }
            }
            .navigationTitle(session.selectedChannel ?? "compose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: send) {
                        if sending {
                            ProgressView()
                        } else {
                            Text("send").bold()
                        }
                    }
                    .disabled(messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            }
        }
    }

    private func send() {
        sending = true
        let recipients = to
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Task {
            await session.send(
                to: recipients,
                subject: subject.isEmpty ? nil : subject,
                replyTo: replyToId,
                body: messageBody
            )
            sending = false
            dismiss()
        }
    }
}
