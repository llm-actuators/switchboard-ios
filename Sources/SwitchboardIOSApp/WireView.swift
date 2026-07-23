import SwiftUI


struct WireView: View {
    @EnvironmentObject private var session: WireSession
    @State private var composeShown = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                List(session.records) { rec in
                    RecordRow(record: rec, myHandle: session.wireHandle)
                        .id(rec.id ?? "\(rec.ts.timeIntervalSince1970)")
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .onChange(of: session.records.count) { _, _ in
                    if let last = session.records.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id ?? "\(last.ts.timeIntervalSince1970)", anchor: .bottom)
                        }
                    }
                }
            }

            Button(action: { composeShown = true }) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.blue, in: Circle())
                    .shadow(radius: 4)
            }
            .padding(20)
        }
        .navigationTitle(session.selectedChannel ?? "wire")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $composeShown) {
            ComposeView()
        }
    }
}

struct RecordRow: View {
    let record: Record
    let myHandle: String

    private var ts: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: record.ts)
    }

    private var isMention: Bool {
        record.to.contains(myHandle) || record.to.contains("everyone")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("[\(ts)]").font(.caption).foregroundStyle(.secondary).monospaced()
                Text(record.from ?? record.handle ?? record.kind)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.from == myHandle ? .blue : .primary)
                if let to = record.to.first, !record.to.isEmpty {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(record.to.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let id = record.id {
                    Text(String(id.prefix(6)))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            if let subject = record.subject, !subject.isEmpty {
                Text(subject).font(.callout.weight(.semibold)).foregroundStyle(.orange)
            }
            if let body = record.body, !body.isEmpty {
                Text(body).font(.callout)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isMention ? Color.yellow.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }
}
