import SwiftUI

struct NavRail: View {
    @Environment(TreadmillStore.self) private var store
    var isLandscape: Bool

    var body: some View {
        if isLandscape {
            landscapeRail
        } else {
            portraitBar
        }
    }

    private var landscapeRail: some View {
        VStack(spacing: 24) {
            Spacer()
            profileItem
            navItem("house.fill", route: .lobby)
            runItem
            voiceItem
            navItem("gearshape.fill", route: nil, action: { store.presentSettings() })
            Spacer()
        }
        .frame(width: 60)
        .frame(maxHeight: .infinity)
        .background(AppColors.bg)
        .glassEffect(.regular.interactive(), in: .rect)
    }

    private var portraitBar: some View {
        HStack {
            profileItemLabeled
            Spacer()
            navItemLabeled("house.fill", label: "Home", route: .lobby)
            Spacer()
            runItemLabeled
            Spacer()
            voiceItemLabeled
            Spacer()
            navItemLabeled("gearshape.fill", label: "Settings", route: nil, action: { store.presentSettings() })
        }
        .padding(.horizontal, 24)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(AppColors.bg)
        .glassEffect(.regular.interactive(), in: .rect)
    }

    // MARK: - Landscape items (icon-only)

    private func navItem(_ symbol: String, route: AppRoute?, action: (() -> Void)? = nil) -> some View {
        Button {
            if let route { store.navigate(to: route) }
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(isSelected(route) ? AppColors.text : AppColors.text3)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private var profileItem: some View {
        Button {
            store.navigate(to: .profilePicker)
        } label: {
            Group {
                if let profile = store.activeProfile {
                    AvatarCircle(profile: profile, size: 28)
                } else if store.guestMode {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(AppColors.text3)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text("G")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.text3)
                        }
                } else {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(AppColors.text3)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text("?")
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(AppColors.text3)
                        }
                }
            }
            // Ensure minimum 44pt touch target even though circle is 28pt
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private var runItem: some View {
        Button {
            if store.program.running || store.session.active {
                store.navigate(to: .running)
            } else {
                Task {
                    await store.quickStart(speed: 0.5, incline: 0)
                }
            }
        } label: {
            Image(systemName: "figure.run")
                .font(.system(size: 20))
                .foregroundStyle(store.currentRoute == .running ? AppColors.text : AppColors.text3)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private var voiceItem: some View {
        Button { store.toggleVoice() } label: {
            Image(systemName: voiceIcon)
                .font(.system(size: 20))
                .foregroundStyle(store.voiceState == .idle ? AppColors.text3 : voiceColor)
                .frame(width: 48, height: 48)
                .background(voicePulseBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var voicePulseBackground: some View {
        if store.voiceState == .listening || store.voiceState == .connecting {
            Circle()
                .fill(voiceColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .modifier(PulseModifier(isActive: true, color: voiceColor))
        }
    }

    // MARK: - Portrait items (icon + label)

    private func navItemLabeled(_ symbol: String, label: String, route: AppRoute?, action: (() -> Void)? = nil) -> some View {
        Button {
            if let route { store.navigate(to: route) }
            action?()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isSelected(route) ? AppColors.text : AppColors.text3)
            .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private var runItemLabeled: some View {
        Button {
            if store.program.running || store.session.active {
                store.navigate(to: .running)
            } else {
                Task {
                    await store.quickStart(speed: 0.5, incline: 0)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "figure.run")
                    .font(.system(size: 20))
                Text("Run")
                    .font(.system(size: 10))
            }
            .foregroundStyle(store.currentRoute == .running ? AppColors.text : AppColors.text3)
            .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private var profileItemLabeled: some View {
        Button {
            store.navigate(to: .profilePicker)
        } label: {
            VStack(spacing: 2) {
                if let profile = store.activeProfile {
                    AvatarCircle(profile: profile, size: 24)
                } else if store.guestMode {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.text3)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.text3)
                }
                Text(store.guestMode && store.activeProfile == nil ? "Guest" : (store.activeProfile?.firstName ?? "Profile"))
                    .font(.system(size: 10))
                    .foregroundStyle(store.currentRoute == .profilePicker ? AppColors.text : AppColors.text3)
            }
            .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private var voiceItemLabeled: some View {
        Button { store.toggleVoice() } label: {
            VStack(spacing: 2) {
                Image(systemName: voiceIcon)
                    .font(.system(size: 20))
                    .background(voicePulseBackground)
                Text(voiceLabel)
                    .font(.system(size: 10))
            }
            .foregroundStyle(store.voiceState == .idle ? AppColors.text3 : voiceColor)
            .frame(minWidth: 48, minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func isSelected(_ route: AppRoute?) -> Bool {
        guard let route else { return store.isSettingsPresented }
        return store.currentRoute == route
    }

    private var voiceIcon: String {
        switch store.voiceState {
        case .idle: return "mic.fill"
        case .connecting: return "ellipsis.circle"
        case .listening: return "mic.circle.fill"
        case .speaking: return "speaker.wave.2.circle.fill"
        }
    }

    private var voiceColor: Color {
        switch store.voiceState {
        case .idle: return AppColors.text
        case .connecting: return AppColors.yellow
        case .listening: return AppColors.green
        case .speaking: return AppColors.purple
        }
    }

    private var voiceLabel: String {
        switch store.voiceState {
        case .idle: return "Voice"
        case .connecting: return "..."
        case .listening: return "Listening"
        case .speaking: return "Speaking"
        }
    }
}

private struct PulseModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    Circle()
                        .fill(color.opacity(isPulsing ? 0.3 : 0.1))
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                        .onAppear { isPulsing = true }
                }
            }
    }
}
