import SwiftUI

@main
struct TreddyApp: App {
    @State private var store = TreadmillStore()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}
