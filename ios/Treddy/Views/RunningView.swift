import SwiftUI

struct RunningView: View {
    @Environment(TreadmillStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            // Timer
            Text(formatTime(store.session.elapsed))
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .padding(.top, 20)

            // Metrics row
            HStack(spacing: 20) {
                MetricLabel(value: formatPace(store.status.speedMph), label: "min/mi")
                MetricLabel(value: String(format: "%.2f", store.session.distance), label: "miles")
                MetricLabel(value: String(format: "%.0f", store.session.vertFeet), label: "vert ft")
                MetricLabel(value: String(format: "%.0f", store.session.calories), label: "cal")
            }
            .padding(.vertical, 12)

            // Encouragement
            if let msg = store.program.encouragement, !msg.isEmpty {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(.horizontal)
                    .transition(.opacity)
            }

            Spacer()

            // Speed / Incline controls
            HStack(spacing: 12) {
                SpeedControl(store: store)
                InclineControl(store: store)
            }
            .padding(.horizontal)

            // Stop / Pause buttons
            HStack(spacing: 12) {
                if store.program.running {
                    Button(store.program.paused ? "Resume" : "Pause") {
                        Task { await store.pause() }
                    }
                    .buttonStyle(ActionButton(color: .orange))
                }

                Button("Stop") {
                    Task { await store.stop() }
                }
                .buttonStyle(ActionButton(color: .red))
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    func formatPace(_ mph: Double) -> String {
        guard mph > 0 else { return "--:--" }
        let minPerMile = 60.0 / mph
        let m = Int(minPerMile)
        let s = Int((minPerMile - Double(m)) * 60)
        return String(format: "%d:%02d", m, s)
    }
}

struct MetricLabel: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct SpeedControl: View {
    let store: TreadmillStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { Task { await store.adjustSpeed(delta: -1) } } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(ChevronButton())

                VStack {
                    Text(String(format: "%.1f", store.status.speedMph))
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.green)
                    Text("mph")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 60)

                Button { Task { await store.adjustSpeed(delta: 1) } } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(ChevronButton())
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct InclineControl: View {
    let store: TreadmillStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { Task { await store.adjustIncline(delta: -0.5) } } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(ChevronButton())

                VStack {
                    Text(String(format: "%.1f", store.status.inclinePct))
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                    Text("% incline")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 60)

                Button { Task { await store.adjustIncline(delta: 0.5) } } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(ChevronButton())
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ChevronButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct ActionButton: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.6 : 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
