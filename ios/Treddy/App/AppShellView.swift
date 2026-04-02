import SwiftUI

struct AppShellView: View {
    @Environment(TreadmillStore.self) private var store

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if !store.isConnected {
                        DisconnectBanner()
                    }

                    shellChrome
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { store.isSettingsPresented },
                    set: { store.isSettingsPresented = $0 }
                )
            ) {
                settingsSheet
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch store.currentRoute {
        case .lobby:
            LobbyView()
        case .running:
            RunningView()
        case .debug:
            DebugView()
        }
    }

    private var shellChrome: some View {
        HStack(spacing: 12) {
            RouteButton(
                title: "Home",
                systemImage: "house.fill",
                isSelected: store.currentRoute == .lobby,
                action: { store.navigate(to: .lobby) }
            )

            RouteButton(
                title: "Run",
                systemImage: "figure.run",
                isSelected: store.currentRoute == .running,
                action: { store.navigate(to: .running) }
            )

            if store.debugUnlocked {
                RouteButton(
                    title: "Debug",
                    systemImage: "ladybug.fill",
                    isSelected: store.currentRoute == .debug,
                    action: { store.navigate(to: .debug) }
                )
            }

            Spacer(minLength: 0)

            VoiceButton()

            Button("Settings") {
                store.presentSettings()
            }
            .buttonStyle(ChromeButtonStyle(systemImage: "gearshape.fill", isSelected: store.isSettingsPresented))
            .accessibilityIdentifier("settings-button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var settingsSheet: some View {
        SettingsView()
            .presentationDragIndicator(.visible)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !store.isConnected {
                    DisconnectBanner()
                }
            }
    }
}

private struct RouteButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ChromeButtonStyle(systemImage: systemImage, isSelected: isSelected))
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    let systemImage: String
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.green.opacity(0.22) : Color(.systemGray6))
            .foregroundStyle(isSelected ? .green : .primary)
            .overlay(alignment: .leading) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .opacity(0)
            }
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
