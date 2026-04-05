import SwiftUI

struct LobbyView: View {
    @Environment(TreadmillStore.self) var store

    private var greetingName: String {
        if let profile = store.activeProfile {
            return profile.firstName
        }
        return store.guestMode ? "Guest" : ""
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "Good morning"
        case 12..<17: timeOfDay = "Good afternoon"
        default: timeOfDay = "Good evening"
        }
        let name = greetingName
        return name.isEmpty ? timeOfDay : "\(timeOfDay), \(name)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold))
                    Text("Ready for a run?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if store.session.active || store.program.running {
                    Button("Return to Workout") {
                        store.navigate(to: .running)
                    }
                    .buttonStyle(LobbyButton(filled: true))

                    if store.program.running, let prog = store.program.program {
                        let idx = store.program.currentInterval
                        let intervalName = prog.intervals.indices.contains(idx)
                            ? prog.intervals[idx].name : ""
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intervalName)
                                    .font(.body.weight(.semibold))
                                Text("\(Fmt.speed(store.status.speedMph)) mph · \(Fmt.pace(store.status.speedMph)) min/mi")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.time(store.session.elapsed))
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { store.navigate(to: .running) }
                    }
                } else {
                    HStack(spacing: 12) {
                        Button("Quick") {
                            Task { await store.quickStart() }
                        }
                        .buttonStyle(LobbyButton(filled: false))

                        Button("Manual") {
                            Task { await store.quickStart(speed: 0.5, incline: 0) }
                        }
                        .buttonStyle(LobbyButton(filled: true))
                    }

                    if store.program.program != nil && !store.program.running {
                        Button("Start Program") {
                            Task { await store.startProgram() }
                        }
                        .buttonStyle(LobbyButton(filled: true))
                    }
                }

                if !store.workouts.isEmpty {
                    sectionHeader("MY WORKOUTS")
                    ForEach(store.workouts) { workout in
                        WorkoutCard(
                            name: workout.name,
                            detail: Fmt.duration(workout.totalDuration) + " · \(workout.program?.intervals.count ?? 0) intervals",
                            subtext: workout.lastRunText
                        ) {
                            Task { await store.loadWorkout(workout.id) }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await store.deleteWorkout(workout.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                if !store.history.isEmpty {
                    sectionHeader("YOUR PROGRAMS")
                    ForEach(store.history) { entry in
                        let canResume = !entry.completed && entry.lastElapsed > 0
                        WorkoutCard(
                            name: (entry.program?.name ?? "Workout") + (entry.completed ? " \u{2713}" : ""),
                            detail: Fmt.duration(Int(entry.totalDuration)) + " · \(entry.program?.intervals.count ?? 0) intervals",
                            subtext: entry.lastRunText
                        ) {
                            Task { await store.loadHistoryEntry(entry.id) }
                        }
                        .overlay(alignment: .trailing) {
                            HStack(spacing: 4) {
                                if canResume {
                                    Button {
                                        Task { await store.resumeHistoryEntry(entry.id) }
                                    } label: {
                                        Text("Resume from \(Fmt.time(Double(entry.lastElapsed)))")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(AppColors.green)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppColors.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    Task { await store.toggleSaveHistory(entry) }
                                } label: {
                                    Image(systemName: entry.saved ? "heart.fill" : "heart")
                                        .font(.title3)
                                        .foregroundStyle(entry.saved ? .pink : .secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.trailing, 8)
                        }
                    }
                }

                if store.workouts.isEmpty && store.history.isEmpty {
                    Text("No workouts yet")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .refreshable { await store.loadData() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

}

struct WorkoutCard: View {
    let name: String
    let detail: String
    let subtext: String
    let action: () -> Void

    var body: some View {
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
        .padding(.trailing, 36) // room for heart overlay
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { action() }
        .accessibilityAddTraits(.isButton)
    }
}

struct LobbyButton: ButtonStyle {
    var filled: Bool = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if filled {
            configuration.label
                .font(.body.weight(.bold))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(AppColors.green)
                .foregroundStyle(.black)
                .clipShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
        } else {
            configuration.label
                .font(.body.weight(.bold))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(AppColors.text)
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
