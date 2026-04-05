import SwiftUI

struct SettingsView: View {
    @Environment(TreadmillStore.self) private var store

    @State private var urlText = ""
    @State private var weightText = ""
    @State private var vestText = ""
    @State private var debugTapTimes: [Date] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $urlText)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            store.serverURL = urlText
                        }
                }

                Section {
                    Toggle(isOn: smartassBinding) {
                        Text("Smart-ass Mode")
                            .accessibilityIdentifier("smartass-label")
                    }
                } footer: {
                    Text(store.smartassEnabled ? "Sarcastic prompts enabled." : "Sarcastic prompts disabled.")
                }

                if store.debugUnlocked {
                    Section {
                        Text("Debug tools unlocked")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("debug-unlocked-label")
                    }
                }

                Section("Body") {
                    bodyRow(
                        title: "Weight",
                        text: $weightText,
                        placeholder: "154",
                        isEditable: true
                    ) {
                        guard let lbs = Int(weightText), (50...500).contains(lbs) else { return }
                        Task {
                            guard let user = try? await store.api.updateUser(weightLbs: lbs, vestLbs: nil) else { return }
                            store.userProfile = user
                            weightText = "\(user.weightLbs)"
                        }
                    }

                    bodyRow(
                        title: "Weight Vest",
                        text: $vestText,
                        placeholder: "0",
                        isEditable: false
                    )
                }

                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(store.isConnected ? "Connected" : "Disconnected")
                            .foregroundStyle(store.isConnected ? .green : .red)
                            .accessibilityIdentifier("connection-status-value")
                    }
                    .accessibilityIdentifier("connection-status-row")

                    HStack {
                        Text("Workout Route")
                        Spacer()
                        Text(store.currentRoute.label)
                            .foregroundStyle(.secondary)
                    }

                    if store.status.hrmConnected {
                        HStack {
                            Text("Heart Rate")
                            Spacer()
                            Text("\(store.status.heartRate) bpm")
                                .foregroundStyle(.red)
                        }
                    }
                }

                HrmSection()

                if store.debugUnlocked {
                    Section("Debug") {
                        Button("Debug Tools") {
                            store.isSettingsPresented = false
                            store.navigate(to: .debug)
                        }
                        .accessibilityIdentifier("debug-tools-button")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button("Settings") {
                        registerDebugTap()
                    }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .accessibilityIdentifier("settings-debug-unlock")
                }
            }
            .onAppear {
                urlText = store.serverURL
                syncBodyFields()
                Task {
                    await store.refreshUserProfile()
                    syncBodyFields()
                }
            }
        }
    }

    private var smartassBinding: Binding<Bool> {
        Binding(
            get: { store.smartassEnabled },
            set: { store.smartassEnabled = $0 }
        )
    }

    private func syncBodyFields() {
        weightText = "\(store.userProfile.weightLbs)"
        vestText = store.activeProfile.map { $0.vestLbs > 0 ? String(format: "%.0f", $0.vestLbs) : "" } ?? ""
    }

    private func registerDebugTap() {
        let now = Date()
        debugTapTimes = (debugTapTimes + [now]).filter { now.timeIntervalSince($0) < 0.6 }
        if debugTapTimes.count >= 3 {
            debugTapTimes.removeAll()
            store.unlockDebug()
        }
    }


    @ViewBuilder
    private func bodyRow(
        title: String,
        text: Binding<String>,
        placeholder: String,
        isEditable: Bool,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .disabled(!isEditable)
                .onSubmit {
                    onSubmit?()
                }
            Text("lbs")
                .foregroundStyle(.secondary)
        }
    }
}
