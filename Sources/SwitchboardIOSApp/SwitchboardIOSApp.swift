import SwiftUI

@main
struct SwitchboardIOSApp: App {
    @StateObject private var session = WireSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}
