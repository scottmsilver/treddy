import SwiftUI

@main
struct TreddyApp: App {
    @State private var store = TreadmillStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.reconnectIfNeeded()
            }
        }
    }
}
