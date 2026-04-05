import SwiftUI

struct AppShellView: View {
    @Environment(TreadmillStore.self) private var store
    @State private var isLandscape = false

    private var showChrome: Bool {
        switch store.currentRoute {
        case .setup, .profilePicker:
            return false
        default:
            return true
        }
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            Group {
                if showChrome {
                    chromeShell(landscape: landscape)
                } else {
                    contentView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.bgGradient.ignoresSafeArea())
            .onChange(of: landscape) { _, newValue in
                isLandscape = newValue
            }
            .onAppear { isLandscape = landscape }
        }
        .sheet(
            isPresented: Binding(
                get: { store.isSettingsPresented },
                set: { store.isSettingsPresented = $0 }
            )
        ) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let msg = store.toastMessage {
                ToastView(message: msg)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: store.toastMessage)
            }
        }
    }

    private func updateOrientation() {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        isLandscape = (scene?.interfaceOrientation.isLandscape ?? false)
    }

    @ViewBuilder
    private func chromeShell(landscape: Bool) -> some View {
        if landscape {
            HStack(spacing: 0) {
                NavRail(isLandscape: landscape)
                VStack(spacing: 0) {
                    if !store.isConnected {
                        DisconnectBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    contentView
                }
                .animation(.easeInOut(duration: 0.3), value: store.isConnected)
            }
        } else {
            VStack(spacing: 0) {
                if !store.isConnected {
                    DisconnectBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                contentView
                    .frame(maxHeight: .infinity)
                NavRail(isLandscape: landscape)
            }
            .animation(.easeInOut(duration: 0.3), value: store.isConnected)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch store.currentRoute {
        case .setup:
            SetupView()
        case .profilePicker:
            ProfilePickerView()
        case .lobby:
            LobbyView()
        case .running:
            RunningView()
        case .debug:
            DebugView()
        }
    }
}
