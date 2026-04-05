# iPad App Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the iOS Treddy app UI to match the Android tablet layout (left nav rail in landscape, bottom tabs in portrait) while feeling iOS-native.

**Architecture:** Orientation-aware shell (NavRail) wraps all views. Setup screen gates first launch. Running view uses proportional scaling with elevation profile canvas and speed/incline chevron controls. All navigation is SF Symbol icon-based.

**Tech Stack:** SwiftUI, iOS 17+, Swift 6.0, Canvas API for elevation chart

**Spec:** `docs/superpowers/specs/2026-04-04-ipad-redesign-design.md`

**Build/deploy:** Source in `ios/`. Generate Xcode project with `python3 ios/gen_xcodeproj.py`. Rsync to Mac: `rsync -avz --exclude='.git' -e "ssh -p 2222" ios/ localhost:~/dev/treddy-ios/`. Build on Mac Terminal: `/tmp/build-treddy.sh`. Install to iPad via SSH: `ssh -p 2222 localhost "xcrun devicectl device install app --device D2F31165-1B5E-57E7-A649-AA5CC9E9B101 ~/Library/Developer/Xcode/DerivedData/Treddy-akyorfmlgoaktcfdnjvqkapgxdjr/Build/Products/Debug-iphoneos/Treddy.app"`. Codesign does NOT work over SSH — the Mac Terminal build step must be run manually by the user.

**What's already done:** Profile models, API endpoints, WebSocket handling, ProfilePickerView, ProfileAvatarButton, profile state in TreadmillStore, decoding tests. All compile.

**Existing patterns to follow:**
- `@Environment(TreadmillStore.self)` for store access
- `@Observable @MainActor` for store
- Postel's Law: `c.val(Type.self, .key, default)` pattern for Codable
- `async/await` with `Task { }` for button actions
- Dark mode only (`.preferredColorScheme(.dark)`)
- SF Symbols for all icons (never emoji in nav)

---

### Task 1: AppRoute + TreadmillStore — Add Setup Route and State

**Files:**
- Modify: `ios/Treddy/App/AppRoute.swift`
- Modify: `ios/Treddy/State/TreadmillStore.swift`

- [ ] **Step 1: Add `.setup` case to AppRoute**

```swift
// ios/Treddy/App/AppRoute.swift
import Foundation

enum AppRoute: String, Hashable {
    case setup
    case profilePicker
    case lobby
    case running
    case debug

    var label: String {
        switch self {
        case .setup: return "Setup"
        case .profilePicker: return "Profiles"
        case .lobby: return "Lobby"
        case .running: return "Running"
        case .debug: return "Debug"
        }
    }
}
```

- [ ] **Step 2: Add setupComplete state and initial route logic to TreadmillStore**

In `TreadmillStore.swift`, add a `setupComplete` property and change the initial route:

Add this observable property alongside the others:
```swift
var setupComplete: Bool = UserDefaults.standard.bool(forKey: "setup_complete") {
    didSet {
        UserDefaults.standard.set(setupComplete, forKey: "setup_complete")
    }
}
```

Change the `currentRoute` initializer from:
```swift
var currentRoute: AppRoute = .lobby
```
to:
```swift
var currentRoute: AppRoute = UserDefaults.standard.bool(forKey: "setup_complete") ? .profilePicker : .setup
```

Add a `completeSetup` method in the Actions section:
```swift
func completeSetup() {
    setupComplete = true
    currentRoute = .profilePicker
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd ios && python3 gen_xcodeproj.py`
Then rsync and build unsigned: `rsync -avz --exclude='.git' -e "ssh -p 2222" ios/ localhost:~/dev/treddy-ios/ && ssh -p 2222 localhost "cd ~/dev/treddy-ios && xcodebuild -project Treddy.xcodeproj -scheme Treddy -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add ios/Treddy/App/AppRoute.swift ios/Treddy/State/TreadmillStore.swift
git commit -m "feat(ios): add setup route and setupComplete state"
```

---

### Task 2: SetupView — First-Launch Server URL Entry

**Files:**
- Create: `ios/Treddy/Views/SetupView.swift`

- [ ] **Step 1: Create SetupView**

```swift
// ios/Treddy/Views/SetupView.swift
import SwiftUI

struct SetupView: View {
    @Environment(TreadmillStore.self) private var store
    @State private var urlText = "https://rpi:8000"
    @State private var connecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Treddy")
                .font(.largeTitle.weight(.bold))

            Text("Enter your treadmill server address")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Server URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: 360)
                    .onSubmit(connect)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: connect) {
                    if connecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                .frame(maxWidth: 360)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Pre-fill saved URL if any
            let saved = UserDefaults.standard.string(forKey: "server_url") ?? ""
            if !saved.isEmpty { urlText = saved }
        }
    }

    private func connect() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !connecting else { return }
        connecting = true
        errorMessage = nil

        store.serverURL = trimmed
        // Give WebSocket a moment to connect
        Task {
            try? await Task.sleep(for: .seconds(2))
            if store.isConnected {
                store.completeSetup()
            } else {
                errorMessage = "Could not connect to \(trimmed)"
            }
            connecting = false
        }
    }
}
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Run: `cd ios && python3 gen_xcodeproj.py`
Rsync + unsigned build. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```
git add ios/Treddy/Views/SetupView.swift
git commit -m "feat(ios): add SetupView for first-launch server URL entry"
```

---

### Task 3: NavRail — Orientation-Aware Navigation Component

**Files:**
- Create: `ios/Treddy/Views/Components/NavRail.swift`

- [ ] **Step 1: Create NavRail**

This component renders a left rail in landscape and a bottom tab bar in portrait. It reads orientation from the environment and renders the 5 navigation items (profile avatar, home, run, voice, settings).

```swift
// ios/Treddy/Views/Components/NavRail.swift
import SwiftUI

struct NavRail: View {
    @Environment(TreadmillStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        if isLandscape {
            landscapeRail
        } else {
            portraitBar
        }
    }

    // MARK: - Landscape: left vertical rail

    private var landscapeRail: some View {
        VStack(spacing: 20) {
            Spacer()
            profileItem
            navItem("house.fill", route: .lobby)
            navItem("figure.run", route: .running)
            voiceItem
            navItem("gearshape.fill", route: nil, action: { store.presentSettings() })
            Spacer()
        }
        .frame(width: 56)
        .background(Color(red: 0.071, green: 0.071, blue: 0.063)) // #121210
    }

    // MARK: - Portrait: bottom horizontal bar

    private var portraitBar: some View {
        HStack(spacing: 0) {
            profileItemLabeled
            Spacer()
            navItemLabeled("house.fill", label: "Home", route: .lobby)
            Spacer()
            navItemLabeled("figure.run", label: "Run", route: .running)
            Spacer()
            voiceItemLabeled
            Spacer()
            navItemLabeled("gearshape.fill", label: "Settings", route: nil, action: { store.presentSettings() })
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color(red: 0.071, green: 0.071, blue: 0.063))
    }

    // MARK: - Nav items (landscape, icon-only)

    private func navItem(_ symbol: String, route: AppRoute?, action: (() -> Void)? = nil) -> some View {
        Button {
            if let route { store.navigate(to: route) }
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.primary.opacity(isSelected(route) ? 1.0 : 0.35))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var profileItem: some View {
        Button {
            store.navigate(to: .profilePicker)
        } label: {
            if let profile = store.activeProfile {
                AvatarCircle(profile: profile, size: 28)
            } else {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.primary.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text("?")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.primary.opacity(0.35))
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var voiceItem: some View {
        Button { store.toggleVoice() } label: {
            Image(systemName: voiceIcon)
                .font(.system(size: 20))
                .foregroundStyle(voiceColor.opacity(store.voiceState == .idle ? 0.35 : 1.0))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nav items (portrait, icon + label)

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
            .foregroundStyle(.primary.opacity(isSelected(route) ? 1.0 : 0.35))
            .frame(minWidth: 44)
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
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary.opacity(0.35))
                }
                Text(store.activeProfile?.firstName ?? "Profile")
                    .font(.system(size: 10))
                    .foregroundStyle(.primary.opacity(store.currentRoute == .profilePicker ? 1.0 : 0.35))
            }
            .frame(minWidth: 44)
        }
        .buttonStyle(.plain)
    }

    private var voiceItemLabeled: some View {
        Button { store.toggleVoice() } label: {
            VStack(spacing: 2) {
                Image(systemName: voiceIcon)
                    .font(.system(size: 20))
                Text(voiceLabel)
                    .font(.system(size: 10))
            }
            .foregroundStyle(voiceColor.opacity(store.voiceState == .idle ? 0.35 : 1.0))
            .frame(minWidth: 44)
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
        case .idle: return .primary
        case .connecting: return .yellow
        case .listening: return .green
        case .speaking: return .purple
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
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Run: `cd ios && python3 gen_xcodeproj.py`
Rsync + unsigned build. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```
git add ios/Treddy/Views/Components/NavRail.swift
git commit -m "feat(ios): add orientation-aware NavRail component"
```

---

### Task 4: AppShellView Rewrite — Orientation-Aware Shell

**Files:**
- Modify: `ios/Treddy/App/AppShellView.swift`

- [ ] **Step 1: Rewrite AppShellView**

Replace the entire file. The new shell uses NavRail for navigation, supports landscape (left rail) and portrait (bottom bar), and hides chrome on Setup and Profile Picker screens.

```swift
// ios/Treddy/App/AppShellView.swift
import SwiftUI

struct AppShellView: View {
    @Environment(TreadmillStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var showChrome: Bool {
        switch store.currentRoute {
        case .setup, .profilePicker:
            return false
        default:
            return true
        }
    }

    var body: some View {
        Group {
            if showChrome {
                chromeShell
            } else {
                contentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .sheet(
            isPresented: Binding(
                get: { store.isSettingsPresented },
                set: { store.isSettingsPresented = $0 }
            )
        ) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var chromeShell: some View {
        if isLandscape {
            HStack(spacing: 0) {
                NavRail()
                VStack(spacing: 0) {
                    if !store.isConnected {
                        DisconnectBanner()
                    }
                    contentView
                }
            }
        } else {
            VStack(spacing: 0) {
                if !store.isConnected {
                    DisconnectBanner()
                }
                contentView
                NavRail()
                    .padding(.bottom, safeAreaBottom)
            }
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

    private var safeAreaBottom: CGFloat {
        // Handled by safe area automatically in most cases
        0
    }
}
```

- [ ] **Step 2: Delete ProfileAvatarButton.swift** (now integrated into NavRail)

Remove `ios/Treddy/Views/Components/ProfileAvatarButton.swift` — the profile avatar is now part of NavRail.

- [ ] **Step 3: Regenerate Xcode project and verify build**

Run: `cd ios && python3 gen_xcodeproj.py`
Rsync + unsigned build. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add ios/Treddy/App/AppShellView.swift
git rm ios/Treddy/Views/Components/ProfileAvatarButton.swift
git commit -m "feat(ios): rewrite AppShellView with orientation-aware NavRail layout"
```

---

### Task 5: LobbyView Rewrite — Match Android Tablet Lobby

**Files:**
- Modify: `ios/Treddy/Views/LobbyView.swift`

- [ ] **Step 1: Rewrite LobbyView**

Replace the entire file. Matches the Android lobby: greeting, subtitle, action buttons, mini status card when workout active, scrollable workout/history lists, content width constrained on large screens.

```swift
// ios/Treddy/Views/LobbyView.swift
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
                // Greeting
                VStack(spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold))
                    Text("Ready for a run?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Action buttons
                if store.session.active || store.program.running {
                    Button("Return to Workout") {
                        store.navigate(to: .running)
                    }
                    .buttonStyle(LobbyButton(filled: true))
                } else {
                    HStack(spacing: 12) {
                        Button("Quick") {
                            Task { await store.quickStart() }
                        }
                        .buttonStyle(LobbyButton(filled: false))

                        Button("Manual") {
                            Task { await store.quickStart(speed: 0, incline: 0) }
                        }
                        .buttonStyle(LobbyButton(filled: true))
                    }
                }

                // Mini status card (when workout active)
                if store.program.running, let prog = store.program.program {
                    let intervalName = prog.intervals.indices.contains(store.program.currentInterval)
                        ? prog.intervals[store.program.currentInterval].name
                        : ""
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(intervalName)
                                .font(.body.weight(.semibold))
                            Text("\(formatSpeed(store.status.speedMph)) mph · \(formatPace(store.status.speedMph)) min/mi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatTime(store.session.elapsed))
                            .font(.title2.weight(.bold).monospacedDigit())
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { store.navigate(to: .running) }
                }

                // Saved workouts
                if !store.workouts.isEmpty {
                    sectionHeader("MY WORKOUTS")
                    ForEach(store.workouts) { workout in
                        WorkoutCard(
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
                    sectionHeader("YOUR PROGRAMS")
                    ForEach(store.history) { entry in
                        WorkoutCard(
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

    func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m):\(String(format: "%02d", s))" : "\(m):00"
    }

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    func formatSpeed(_ mph: Double) -> String {
        String(format: "%.1f", mph)
    }

    func formatPace(_ mph: Double) -> String {
        guard mph > 0 else { return "--:--" }
        let minPerMile = 60.0 / mph
        let m = Int(minPerMile)
        let s = Int((minPerMile - Double(m)) * 60)
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Supporting views

struct WorkoutCard: View {
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct LobbyButton: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(filled ? Color.green.opacity(0.8) : Color(.systemGray5))
            .foregroundStyle(filled ? .black : .primary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```
git add ios/Treddy/Views/LobbyView.swift
git commit -m "feat(ios): rewrite LobbyView matching Android tablet lobby layout"
```

---

### Task 6: MetricsRow + SpeedInclineControls Components

**Files:**
- Create: `ios/Treddy/Views/Components/MetricsRow.swift`
- Create: `ios/Treddy/Views/Components/SpeedInclineControls.swift`

- [ ] **Step 1: Create MetricsRow**

Horizontal metrics display with optional heart rate. Values bold, units in smaller muted text.

```swift
// ios/Treddy/Views/Components/MetricsRow.swift
import SwiftUI

struct MetricsRow: View {
    let speedMph: Double
    let distance: Double
    let vertFeet: Double
    let calories: Double
    var heartRate: Int = 0
    var hrmConnected: Bool = false
    var scale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 24 * scale) {
            if hrmConnected && heartRate > 0 {
                metric(value: "\(heartRate)", unit: "bpm", color: .red)
                divider
            }
            metric(value: formatPace(speedMph), unit: "min/mi", color: speedMph > 0 ? .green : .primary)
            divider
            metric(value: String(format: "%.2f", distance), unit: "miles")
            divider
            metric(value: String(format: "%.0f", vertFeet), unit: "vert ft")
            divider
            metric(value: String(format: "%.0f", calories), unit: "cal")
        }
    }

    private func metric(value: String, unit: String, color: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18 * scale, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 12 * scale))
                .foregroundStyle(.secondary)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1, height: 24 * scale)
    }

    private func formatPace(_ mph: Double) -> String {
        guard mph > 0 else { return "--:--" }
        let minPerMile = 60.0 / mph
        let m = Int(minPerMile)
        let s = Int((minPerMile - Double(m)) * 60)
        return String(format: "%d:%02d", m, s)
    }
}
```

- [ ] **Step 2: Create SpeedInclineControls**

Two panels with single and double chevron buttons flanking the value. Supports vertical (landscape) and horizontal (portrait) layout. Hold-to-repeat on buttons.

```swift
// ios/Treddy/Views/Components/SpeedInclineControls.swift
import SwiftUI

struct SpeedInclineControls: View {
    @Environment(TreadmillStore.self) private var store
    var vertical: Bool = true

    var body: some View {
        if vertical {
            VStack(spacing: 8) {
                speedPanel
                inclinePanel
            }
        } else {
            HStack(spacing: 8) {
                speedPanel
                inclinePanel
            }
        }
    }

    private var speedPanel: some View {
        ControlPanel(
            value: String(format: "%.1f", store.status.speedMph),
            unit: "mph",
            valueColor: .green,
            smallUp: { Task { await store.adjustSpeed(delta: 1) } },
            smallDown: { Task { await store.adjustSpeed(delta: -1) } },
            bigUp: { Task { await store.adjustSpeed(delta: 10) } },
            bigDown: { Task { await store.adjustSpeed(delta: -10) } }
        )
    }

    private var inclinePanel: some View {
        ControlPanel(
            value: String(format: "%.1f", store.status.inclinePct),
            unit: "% incline",
            valueColor: .primary,
            smallUp: { Task { await store.adjustIncline(delta: 0.5) } },
            smallDown: { Task { await store.adjustIncline(delta: -0.5) } },
            bigUp: { Task { await store.adjustIncline(delta: 1.0) } },
            bigDown: { Task { await store.adjustIncline(delta: -1.0) } }
        )
    }
}

struct ControlPanel: View {
    let value: String
    let unit: String
    var valueColor: Color = .primary
    let smallUp: () -> Void
    let smallDown: () -> Void
    let bigUp: () -> Void
    let bigDown: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Single chevrons (small delta)
            VStack(spacing: 6) {
                RepeatButton(action: smallUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 16, weight: .semibold))
                }
                RepeatButton(action: smallDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                }
            }

            // Center value
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Double chevrons (big delta)
            VStack(spacing: 6) {
                RepeatButton(action: bigUp) {
                    VStack(spacing: -4) {
                        Image(systemName: "chevron.up")
                        Image(systemName: "chevron.up")
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                RepeatButton(action: bigDown) {
                    VStack(spacing: -4) {
                        Image(systemName: "chevron.down")
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Button that repeats its action while held down.
struct RepeatButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var timer: Timer?
    @State private var repeatCount = 0

    var body: some View {
        label()
            .frame(width: 44, height: 44)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                if pressing {
                    action()
                    repeatCount = 0
                    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        Task { @MainActor in
                            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                                Task { @MainActor in
                                    action()
                                    repeatCount += 1
                                    // Accelerate after 5 repeats
                                    if repeatCount == 5 {
                                        timer?.invalidate()
                                        timer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { _ in
                                            Task { @MainActor in action() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    timer?.invalidate()
                    timer = nil
                }
            }, perform: {})
    }
}
```

- [ ] **Step 3: Regenerate Xcode project and verify build**

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add ios/Treddy/Views/Components/MetricsRow.swift ios/Treddy/Views/Components/SpeedInclineControls.swift
git commit -m "feat(ios): add MetricsRow and SpeedInclineControls with hold-to-repeat"
```

---

### Task 7: ElevationProfile — Canvas Chart Component

**Files:**
- Create: `ios/Treddy/Views/Components/ElevationProfile.swift`

- [ ] **Step 1: Create ElevationProfile**

Canvas-based staircase elevation chart showing incline over time, with completed fill, progress dot, grid lines, and axis labels.

```swift
// ios/Treddy/Views/Components/ElevationProfile.swift
import SwiftUI

struct ElevationProfile: View {
    let intervals: [Interval]
    let currentInterval: Int
    let intervalElapsed: Int
    let totalDuration: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                drawChart(context: context, size: size)
            }

            // Interval counter
            if !intervals.isEmpty {
                Text("\(currentInterval + 1) of \(intervals.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func drawChart(context: GraphicsContext, size: CGSize) {
        guard !intervals.isEmpty else { return }

        let margin = EdgeInsets(top: 12, leading: 32, bottom: 24, trailing: 12)
        let chartW = size.width - margin.leading - margin.trailing
        let chartH = size.height - margin.top - margin.bottom

        let maxIncline = max(intervals.map(\.incline).max() ?? 1, 1)
        let totalDur = Double(totalDuration > 0 ? totalDuration : intervals.reduce(0) { $0 + Int($1.duration) })

        // Compute elapsed time up to current position
        var elapsedToCurrentStart: Double = 0
        for i in 0..<min(currentInterval, intervals.count) {
            elapsedToCurrentStart += intervals[i].duration
        }
        let currentElapsed = elapsedToCurrentStart + Double(intervalElapsed)
        let progressFraction = totalDur > 0 ? currentElapsed / totalDur : 0

        // Grid lines
        let gridColor = Color.primary.opacity(0.08)
        for i in 0...4 {
            let y = margin.top + chartH * CGFloat(i) / 4.0
            var path = Path()
            path.move(to: CGPoint(x: margin.leading, y: y))
            path.addLine(to: CGPoint(x: size.width - margin.trailing, y: y))
            context.stroke(path, with: .color(gridColor), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
        }

        // Y-axis labels
        for i in 0...4 {
            let pct = maxIncline * Double(4 - i) / 4.0
            let y = margin.top + chartH * CGFloat(i) / 4.0
            let text = Text(String(format: "%.0f%%", pct))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            context.draw(context.resolve(text), at: CGPoint(x: margin.leading - 4, y: y), anchor: .trailing)
        }

        // Build staircase path
        var staircasePath = Path()
        var fillPath = Path()
        var x: CGFloat = margin.leading
        let baseline = margin.top + chartH

        fillPath.move(to: CGPoint(x: margin.leading, y: baseline))

        for (i, interval) in intervals.enumerated() {
            let w = chartW * CGFloat(interval.duration / totalDur)
            let y = margin.top + chartH * (1.0 - CGFloat(interval.incline / maxIncline))

            if i == 0 {
                staircasePath.move(to: CGPoint(x: x, y: y))
            } else {
                staircasePath.addLine(to: CGPoint(x: x, y: y))
            }
            staircasePath.addLine(to: CGPoint(x: x + w, y: y))

            fillPath.addLine(to: CGPoint(x: x, y: y))
            fillPath.addLine(to: CGPoint(x: x + w, y: y))

            x += w
        }

        fillPath.addLine(to: CGPoint(x: x, y: baseline))
        fillPath.closeSubpath()

        // Completed fill
        let progressX = margin.leading + chartW * CGFloat(progressFraction)
        var clipRect = CGRect(x: 0, y: 0, width: progressX, height: size.height)
        var completedContext = context
        completedContext.clip(to: Path(clipRect))
        completedContext.fill(fillPath, with: .color(.green.opacity(0.15)))

        // Full outline (future = dimmer)
        context.stroke(staircasePath, with: .color(.green.opacity(0.3)), lineWidth: 1.5)

        // Completed outline (brighter)
        var completedStrokeCtx = context
        completedStrokeCtx.clip(to: Path(clipRect))
        completedStrokeCtx.stroke(staircasePath, with: .color(.green.opacity(0.8)), lineWidth: 2.5)

        // Progress dot
        if let ci = intervals.indices.contains(currentInterval) ? currentInterval : nil {
            let interval = intervals[ci]
            let fracInInterval = interval.duration > 0 ? Double(intervalElapsed) / interval.duration : 0
            var dotX: CGFloat = margin.leading
            for i in 0..<ci { dotX += chartW * CGFloat(intervals[i].duration / totalDur) }
            dotX += chartW * CGFloat(interval.duration / totalDur) * CGFloat(fracInInterval)
            let dotY = margin.top + chartH * (1.0 - CGFloat(interval.incline / maxIncline))

            // Glow
            let glowRect = CGRect(x: dotX - 10, y: dotY - 10, width: 20, height: 20)
            context.fill(Path(ellipseIn: glowRect), with: .color(.green.opacity(0.2)))
            // Dot
            let dotRect = CGRect(x: dotX - 5, y: dotY - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dotRect), with: .color(.green))
        }

        // X-axis time labels
        let timeSteps = niceTimeSteps(totalDuration: totalDur)
        for t in timeSteps {
            let tx = margin.leading + chartW * CGFloat(t / totalDur)
            let label = formatTime(Int(t))
            let text = Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
            context.draw(context.resolve(text), at: CGPoint(x: tx, y: baseline + 12), anchor: .top)
        }
    }

    private func niceTimeSteps(totalDuration: Double) -> [Double] {
        let stepSec: Double
        if totalDuration <= 300 { stepSec = 60 }
        else if totalDuration <= 600 { stepSec = 120 }
        else if totalDuration <= 1800 { stepSec = 300 }
        else { stepSec = 600 }
        var steps: [Double] = []
        var t = stepSec
        while t < totalDuration {
            steps.append(t)
            t += stepSec
        }
        return steps
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        return "\(m)"
    }
}
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```
git add ios/Treddy/Views/Components/ElevationProfile.swift
git commit -m "feat(ios): add Canvas-based ElevationProfile chart component"
```

---

### Task 8: RunningView Rewrite — Full Running Screen

**Files:**
- Modify: `ios/Treddy/Views/RunningView.swift`

- [ ] **Step 1: Rewrite RunningView**

Replace the entire file. Landscape: timer top-center, metrics row, elevation profile + speed/incline controls side by side, full-width stop bar. Portrait: same elements stacked vertically. Remove old `SpeedControl`, `InclineControl`, `ChevronButton`, `ActionButton`, `MetricLabel` types (replaced by new components).

```swift
// ios/Treddy/Views/RunningView.swift
import SwiftUI

struct RunningView: View {
    @Environment(TreadmillStore.self) var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        if isLandscape {
            landscapeLayout
        } else {
            portraitLayout
        }
    }

    // MARK: - Landscape

    private var landscapeLayout: some View {
        VStack(spacing: 0) {
            // Encouragement
            encouragementText
                .padding(.top, 4)

            // Timer
            timerText
                .padding(.top, 2)

            // Metrics
            MetricsRow(
                speedMph: store.status.speedMph,
                distance: store.session.distance,
                vertFeet: store.session.vertFeet,
                calories: store.session.calories,
                heartRate: store.status.heartRate,
                hrmConnected: store.status.hrmConnected
            )
            .padding(.vertical, 6)

            // Elevation + Controls
            HStack(spacing: 8) {
                elevationCard
                SpeedInclineControls(vertical: true)
                    .frame(width: 240)
            }
            .padding(.horizontal, 12)

            // Stop bar
            stopBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Portrait

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            // Encouragement
            encouragementText
                .padding(.top, 8)

            // Timer
            timerText
                .padding(.top, 4)

            // Metrics
            MetricsRow(
                speedMph: store.status.speedMph,
                distance: store.session.distance,
                vertFeet: store.session.vertFeet,
                calories: store.session.calories,
                heartRate: store.status.heartRate,
                hrmConnected: store.status.hrmConnected
            )
            .padding(.vertical, 8)

            // Elevation
            elevationCard
                .padding(.horizontal, 12)

            // Controls
            SpeedInclineControls(vertical: false)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Spacer(minLength: 0)

            // Stop bar
            stopBar
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared elements

    private var timerText: some View {
        Text(formatTime(store.session.elapsed))
            .font(.system(size: isLandscape ? 72 : 64, weight: .bold).monospacedDigit())
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private var encouragementText: some View {
        if let msg = store.program.encouragement, !msg.isEmpty {
            Text(msg)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .transition(.opacity)
                .animation(.easeInOut, value: store.program.encouragement)
        }
    }

    private var elevationCard: some View {
        Group {
            if let prog = store.program.program, !prog.intervals.isEmpty {
                ElevationProfile(
                    intervals: prog.intervals,
                    currentInterval: store.program.currentInterval,
                    intervalElapsed: store.program.intervalElapsed,
                    totalDuration: store.program.totalDuration
                )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isLandscape ? 120 : 160)
    }

    @ViewBuilder
    private var stopBar: some View {
        if store.program.paused {
            HStack(spacing: 12) {
                Button("Resume") {
                    Task { await store.pause() }
                }
                .buttonStyle(StopBarStyle(color: .green))

                Button("Reset") {
                    Task { await store.resetSession() }
                }
                .buttonStyle(StopBarStyle(color: Color(.systemGray3)))
            }
        } else {
            Button("Stop") {
                Task { await store.stop() }
            }
            .buttonStyle(StopBarStyle(color: .red))
        }
    }

    // MARK: - Formatting

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct StopBarStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.6 : 0.85), in: RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 2: Regenerate Xcode project and verify build**

Run: `cd ios && python3 gen_xcodeproj.py`
Rsync + unsigned build. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```
git add ios/Treddy/Views/RunningView.swift
git commit -m "feat(ios): rewrite RunningView with orientation-aware landscape/portrait layouts"
```

---

### Task 9: Update Tests + Final Build Verification

**Files:**
- Modify: `ios/TreddyTests/TreadmillStoreTests.swift`

- [ ] **Step 1: Update test for initial route**

The store now starts on `.setup` if not setup complete, or `.profilePicker` if setup is done. Update the existing test:

In `TreadmillStoreTests.swift`, find the test `testProgramRunningRoutesToRunning` and update the initial assertion. Since the mock store passes `serverURL` directly, `setup_complete` won't be set in UserDefaults. The store will default to `.setup`. Set it up:

```swift
func testProgramRunningRoutesToRunning() {
    let api = MockAPIClient()
    let socket = MockWebSocketClient()
    UserDefaults.standard.set(true, forKey: "setup_complete")
    let store = TreadmillStore(api: api, webSocket: socket, serverURL: "https://rpi:8000")

    // Initial route is profilePicker when setup complete
    XCTAssertEqual(store.currentRoute, .profilePicker)

    var running = ProgramState()
    running.running = true
    socket.onProgram?(running)

    XCTAssertEqual(store.currentRoute, .running)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "setup_complete")
}
```

- [ ] **Step 2: Regenerate Xcode project, rsync, full build**

Run: `cd ios && python3 gen_xcodeproj.py`
Rsync + unsigned build. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```
git add ios/TreddyTests/TreadmillStoreTests.swift
git commit -m "test(ios): update store tests for setup route behavior"
```

- [ ] **Step 4: Deploy to iPad for manual testing**

Ask the user to run `/tmp/build-treddy.sh` on the Mac, then install:
```
ssh -p 2222 localhost "xcrun devicectl device install app --device D2F31165-1B5E-57E7-A649-AA5CC9E9B101 ~/Library/Developer/Xcode/DerivedData/Treddy-akyorfmlgoaktcfdnjvqkapgxdjr/Build/Products/Debug-iphoneos/Treddy.app"
ssh -p 2222 localhost "xcrun devicectl device process launch --device D2F31165-1B5E-57E7-A649-AA5CC9E9B101 com.treddy.app"
```
