import SwiftUI

struct DebugView: View {
    @Environment(TreadmillStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Debug Tools", systemImage: "ladybug.fill")
                        .font(.title2.weight(.semibold))
                    Text("Native iOS debug surface for connection and runtime state.")
                        .foregroundStyle(.secondary)
                }

                debugCard("Connection") {
                    debugRow("Server", store.serverURL)
                    debugRow("Connected", store.isConnected ? "Yes" : "No")
                    debugRow("Route", store.currentRoute.label)
                }

                debugCard("Workout") {
                    debugRow("Program Loaded", store.program.program == nil ? "No" : "Yes")
                    debugRow("Running", store.program.running ? "Yes" : "No")
                    debugRow("Paused", store.program.paused ? "Yes" : "No")
                    debugRow("Elapsed", "\(Int(store.session.elapsed))s")
                    debugRow("Heart Rate", store.status.heartRate > 0 ? "\(store.status.heartRate) bpm" : "--")
                }

                HStack(spacing: 12) {
                    Button("Open Lobby") {
                        store.navigate(to: .lobby)
                    }
                    .buttonStyle(DebugButtonStyle(accent: .green))

                    Button("Open Run") {
                        store.navigate(to: .running)
                    }
                    .buttonStyle(DebugButtonStyle(accent: .orange))
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

}

private struct DebugButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accent.opacity(0.16))
            .foregroundStyle(accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private func debugCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.headline)
        content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 18))
}

private func debugRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .fontWeight(.medium)
    }
}
