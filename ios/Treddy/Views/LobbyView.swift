import SwiftUI

struct LobbyView: View {
    @Environment(TreadmillStore.self) var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Quick start buttons
                    HStack(spacing: 12) {
                        Button("Quick") {
                            Task { await store.quickStart() }
                        }
                        .buttonStyle(PillButton())

                        Button("Manual") {
                            Task { await store.quickStart(speed: 0, incline: 0) }
                        }
                        .buttonStyle(PillButton(filled: true))
                    }
                    .frame(maxWidth: .infinity)

                    // Saved workouts
                    if !store.workouts.isEmpty {
                        Text("MY WORKOUTS")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(store.workouts) { workout in
                            WorkoutRow(
                                name: workout.name,
                                detail: formatDuration(workout.totalDuration) + " · \(workout.program?.intervals.count ?? 0) intervals",
                                subtext: workout.lastRunText
                            ) {
                                Task { await store.loadWorkout(workout.id) }
                            }
                        }
                    }

                    // History
                    if !store.history.isEmpty {
                        Text("YOUR PROGRAMS")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(store.history) { entry in
                            WorkoutRow(
                                name: entry.program?.name ?? "Workout",
                                detail: formatDuration(Int(entry.totalDuration)) + " · \(entry.program?.intervals.count ?? 0) intervals",
                                subtext: entry.lastRunText
                            ) {
                                Task { await store.loadHistoryEntry(entry.id) }
                            }
                        }
                    }

                    if store.workouts.isEmpty && store.history.isEmpty {
                        Text("No workouts yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Treddy")
            .refreshable {
                await store.loadData()
            }
        }
    }

    func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m):\(String(format: "%02d", s))" : "\(m):00"
    }
}

struct WorkoutRow: View {
    let name: String
    let detail: String
    let subtext: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !subtext.isEmpty {
                    Text(subtext)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(filled ? Color.green.opacity(0.8) : Color(.systemGray5))
            .foregroundStyle(filled ? .black : .primary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
