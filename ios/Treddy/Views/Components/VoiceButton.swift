import SwiftUI

struct VoiceButton: View {
    @Environment(TreadmillStore.self) private var store

    var body: some View {
        Button {
            store.toggleVoice()
        } label: {
            Label("Voice", systemImage: iconName)
                .font(.body.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(Capsule())
        }
        .accessibilityIdentifier("voice-button")
    }

    private var iconName: String {
        switch store.voiceState {
        case .idle: return "waveform.circle"
        case .connecting: return "ellipsis.circle"
        case .listening: return "mic.circle.fill"
        case .speaking: return "speaker.wave.2.circle.fill"
        }
    }

    private var backgroundColor: Color {
        switch store.voiceState {
        case .idle: return .green.opacity(0.15)
        case .connecting: return .yellow.opacity(0.2)
        case .listening: return .green.opacity(0.3)
        case .speaking: return .purple.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch store.voiceState {
        case .idle: return .green
        case .connecting: return .yellow
        case .listening: return .green
        case .speaking: return .purple
        }
    }
}
