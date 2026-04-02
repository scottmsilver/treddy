# iOS Common-Core Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the iOS app to functional parity with Android for the shared treadmill product surface: shell, workout browsing, optimistic running controls, settings/HRM/debug, and working Gemini Live voice.

**Architecture:** Fix the iOS server contract first, then reshape the app around a stronger root shell and `TreadmillStore` that owns routing, optimistic state, settings, HRM, and voice coordination. Keep transport concerns in `TreadmillAPI`/`TreadmillWebSocket`, move product behavior into the store and dedicated voice components, and allow iOS-native presentation as long as the shared contract is preserved.

**Tech Stack:** Swift 6, SwiftUI, Observation, URLSession/URLSessionWebSocketTask, AVFoundation, XCTest/XCUITest, XcodeGen

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `ios/Treddy/Models/TreadmillModels.swift` | Modify | Add missing server/API model fields and response types (`manual`, HRM, config smartass/tool data, voice prompt, generic responses) |
| `ios/Treddy/Services/TreadmillAPI.swift` | Modify | Fix HTTP method bugs, add missing endpoints, make request building testable |
| `ios/Treddy/Services/TreadmillWebSocket.swift` | Modify | Decode all relevant message types (`connection`, `hr`, `scan_result`) and expose callbacks |
| `ios/Treddy/State/TreadmillStore.swift` | Modify | Own routing, optimistic control state, settings/profile, HRM data, auto-navigation, debug unlock |
| `ios/Treddy/App/TreddyApp.swift` | Modify | Install a root app shell instead of the current minimal `TabView` |
| `ios/Treddy/App/AppShellView.swift` | Create | Global shell for navigation, disconnect banner, settings/debug presentation, voice affordance |
| `ios/Treddy/App/AppRoute.swift` | Create | Shared route enum/state helpers for lobby/running/debug |
| `ios/Treddy/Views/LobbyView.swift` | Modify | Resume/start behavior, workout/history parity, running transition hooks |
| `ios/Treddy/Views/RunningView.swift` | Modify | Optimistic controls, HR metric, manual duration editing, voice visibility, connected-state behavior |
| `ios/Treddy/Views/SettingsView.swift` | Modify | Expand to full settings contract (server URL, body profile, smartass, HRM, debug unlock, optional GPX import) |
| `ios/Treddy/Views/DebugView.swift` | Create | Hidden debug surface |
| `ios/Treddy/Views/Components/VoiceButton.swift` | Create | Shared shell/running voice affordance with state-based visuals |
| `ios/Treddy/Views/Components/DisconnectBanner.swift` | Create | Global connection banner component |
| `ios/Treddy/Views/Components/HrmSection.swift` | Create | Reusable HRM settings UI |
| `ios/Treddy/Voice/VoiceCoordinator.swift` | Create | iOS voice state machine equivalent to Android `VoiceViewModel` |
| `ios/Treddy/Voice/GeminiLiveClient.swift` | Create | Gemini Live bidi websocket client for iOS |
| `ios/Treddy/Voice/FunctionBridge.swift` | Create | `/api/tool` bridge used by Gemini Live function calls |
| `ios/Treddy/Voice/AudioCapture.swift` | Create | Microphone capture and speech timing helpers |
| `ios/Treddy/Voice/AudioPlayer.swift` | Create | Streamed Gemini audio playback |
| `ios/TreddyTests/ModelDecodingTests.swift` | Modify | Extend decoding coverage for new server/API shapes |
| `ios/TreddyTests/TreadmillAPITests.swift` | Create | Verify request methods/paths and endpoint coverage |
| `ios/TreddyTests/TreadmillStoreTests.swift` | Create | Verify optimistic control state, routing, HRM/settings behavior |
| `ios/TreddyTests/VoiceCoordinatorTests.swift` | Create | Verify voice state transitions and tool bridge usage |
| `ios/TreddyUITests/TreddyUITests.swift` | Modify | Update shell/settings expectations and add parity checks |
| `ios/project.yml` | Modify if needed | Confirm new folders/files are included if xcodegen source globs need adjustment |

**Reference implementations (read before coding voice/shell behavior):**

- `kotlin/app/src/main/java/com/precor/treadmill/ui/navigation/AppNavigation.kt`
- `kotlin/app/src/main/java/com/precor/treadmill/ui/viewmodel/TreadmillViewModel.kt`
- `kotlin/app/src/main/java/com/precor/treadmill/ui/viewmodel/VoiceViewModel.kt`
- `kotlin/app/src/main/java/com/precor/treadmill/voice/GeminiLiveClient.kt`
- `kotlin/app/src/main/java/com/precor/treadmill/voice/FunctionBridge.kt`
- `web/src/voice/GeminiLiveClient.ts`
- `web/src/voice/functionBridge.ts`

---

### Task 1: Fix the iOS API Contract and Add Missing Models

**Files:**
- Modify: `ios/Treddy/Models/TreadmillModels.swift`
- Modify: `ios/Treddy/Services/TreadmillAPI.swift`
- Modify: `ios/TreddyTests/ModelDecodingTests.swift`
- Create: `ios/TreddyTests/TreadmillAPITests.swift`

- [ ] **Step 1: Write failing API request tests**

Create `ios/TreddyTests/TreadmillAPITests.swift` with a custom `URLProtocol` stub and tests for the request contract:

```swift
@MainActor
func testUpdateUserUsesPut() async throws {
    let recorder = RequestRecorder()
    let api = TreadmillAPI(
        baseURL: "https://rpi:8000",
        session: recorder.session
    )

    try await api.updateUser(weightLbs: 180, vestLbs: 20)

    XCTAssertEqual(recorder.lastRequest?.httpMethod, "PUT")
    XCTAssertEqual(recorder.lastRequest?.url?.path, "/api/user")
}
```

Add similar failing tests for:

- `getHrmStatus()` -> `GET /api/hrm`
- `scanHrmDevices()` -> `POST /api/hrm/scan`
- `selectHrmDevice(address:)` -> `POST /api/hrm/select`
- `forgetHrmDevice()` -> `POST /api/hrm/forget`
- `resumeHistory(id:)` -> `POST /api/programs/history/{id}/resume`
- `adjustDuration(deltaSeconds:)` -> `POST /api/program/adjust-duration`

- [ ] **Step 2: Run the API tests to verify they fail**

Run:

```bash
cd ios
xcodegen generate
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TreddyTests/TreadmillAPITests
```

Expected: FAIL because `TreadmillAPI` does not yet expose the missing methods and `updateUser` currently uses the wrong HTTP verb.

- [ ] **Step 3: Extend decoding tests for missing payloads**

Add failing tests to `ios/TreddyTests/ModelDecodingTests.swift` for:

- `Program.manual` decoding
- `AppConfig.smartassAddendum` / `tools`
- `HrmStatusResponse.availableDevices`
- `ScanResultMessage.devices`
- `VoicePromptResponse.prompt`

Example:

```swift
func testAppConfigDecodesSmartassAndTools() throws {
    let data = """
    {
      "gemini_api_key": "k",
      "gemini_model": "m",
      "gemini_live_model": "live",
      "gemini_voice": "Kore",
      "smartass_addendum": "snark",
      "tools": [{"functionDeclarations": []}]
    }
    """.data(using: .utf8)!

    let cfg = try JSONDecoder().decode(AppConfig.self, from: data)
    XCTAssertEqual(cfg.smartassAddendum, "snark")
    XCTAssertNotNil(cfg.tools)
}
```

- [ ] **Step 4: Run the decoding tests to verify they fail**

Run:

```bash
cd ios
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TreddyTests/ModelDecodingTests
```

Expected: FAIL because the model types do not yet expose the missing fields/responses.

- [ ] **Step 5: Implement the minimal API/model changes**

In `ios/Treddy/Models/TreadmillModels.swift`, add the missing types and fields:

```swift
struct HrmDevice: Codable, Equatable, Identifiable {
    var id: String { address }
    var address: String
    var name: String
    var rssi: Int = 0
}

struct HrmStatusResponse: Codable {
    var heartRate: Int = 0
    var connected: Bool = false
    var device: String = ""
    var availableDevices: [HrmDevice] = []
}
```

In `ios/Treddy/Services/TreadmillAPI.swift`:

- change `updateUser` to `PUT`
- add injectable `URLSession` initializer for tests
- add missing endpoint methods

```swift
func updateUser(weightLbs: Int? = nil, vestLbs: Int? = nil) async throws -> UserProfile
func getHrmStatus() async throws -> HrmStatusResponse
func scanHrmDevices() async throws
func selectHrmDevice(address: String) async throws
func forgetHrmDevice() async throws
func resumeHistory(id: String) async throws
func adjustDuration(deltaSeconds: Int) async throws -> ProgramState
```

- [ ] **Step 6: Re-run the targeted tests**

Run both commands from Steps 2 and 4.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/Treddy/Models/TreadmillModels.swift ios/Treddy/Services/TreadmillAPI.swift ios/TreddyTests/ModelDecodingTests.swift ios/TreddyTests/TreadmillAPITests.swift
git commit -m "feat: align ios api contract with server"
```

---

### Task 2: Add a Real iOS App Shell and Route Model

**Files:**
- Modify: `ios/Treddy/App/TreddyApp.swift`
- Create: `ios/Treddy/App/AppRoute.swift`
- Create: `ios/Treddy/App/AppShellView.swift`
- Create: `ios/Treddy/Views/Components/DisconnectBanner.swift`
- Create: `ios/Treddy/Views/Components/VoiceButton.swift`
- Modify: `ios/TreddyUITests/TreddyUITests.swift`

- [ ] **Step 1: Write a failing shell UI test**

Add a test asserting that the app shell exposes home/run voice/settings affordances and keeps the disconnect banner global:

```swift
func testShellShowsGlobalVoiceAndSettings() {
    XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Run"].exists)
    XCTAssertTrue(app.buttons["Voice"].exists)
    XCTAssertTrue(app.buttons["Settings"].exists)
}
```

Also update the existing settings test to stop assuming the app uses the old dedicated settings tab screen.

- [ ] **Step 2: Run the UI test to verify it fails**

Run:

```bash
cd ios
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TreddyUITests/TreddyUITests/testShellShowsGlobalVoiceAndSettings
```

Expected: FAIL because the current app shell is still a minimal `TabView` without voice/global presentation.

- [ ] **Step 3: Implement the shell**

Create `ios/Treddy/App/AppRoute.swift`:

```swift
enum AppRoute: Hashable {
    case lobby
    case running
    case debug
}
```

Create `ios/Treddy/App/AppShellView.swift` with a root layout that:

- shows a global `DisconnectBanner`
- hosts lobby/running/debug content
- owns settings presentation as a sheet
- exposes `VoiceButton` in chrome

Representative structure:

```swift
struct AppShellView: View {
    @Environment(TreadmillStore.self) var store

    var body: some View {
        VStack(spacing: 0) {
            DisconnectBanner(isVisible: !store.isConnected)
            content
            shellBar
        }
        .sheet(isPresented: $store.isSettingsPresented) {
            SettingsView()
        }
    }
}
```

Update `ios/Treddy/App/TreddyApp.swift` to use `AppShellView()` instead of the current inline `ContentView`.

- [ ] **Step 4: Re-run the targeted UI test**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Treddy/App/TreddyApp.swift ios/Treddy/App/AppRoute.swift ios/Treddy/App/AppShellView.swift ios/Treddy/Views/Components/DisconnectBanner.swift ios/Treddy/Views/Components/VoiceButton.swift ios/TreddyUITests/TreddyUITests.swift
git commit -m "feat: add ios app shell and global chrome"
```

---

### Task 3: Reshape `TreadmillStore` Around Routing, Settings, HRM, and Optimistic Controls

**Files:**
- Modify: `ios/Treddy/State/TreadmillStore.swift`
- Modify: `ios/Treddy/Services/TreadmillWebSocket.swift`
- Create: `ios/TreddyTests/TreadmillStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `ios/TreddyTests/TreadmillStoreTests.swift` covering:

- optimistic speed update sets local state immediately
- optimistic incline update sets local state immediately
- websocket reconciliation does not clobber fresh local edits
- loading/starting routes to `.running`
- settings/profile load hydrates store state
- HRM scan results update the visible device list

Example:

```swift
@MainActor
func testAdjustSpeedUpdatesOptimisticStateImmediately() async {
    let api = MockAPI()
    let socket = MockSocket()
    let store = TreadmillStore(api: api, webSocket: socket)

    store.status.emuSpeed = 30
    await store.adjustSpeed(delta: 1)

    XCTAssertEqual(store.status.emuSpeed, 31)
    XCTAssertEqual(api.lastSpeedValue, 3.1, accuracy: 0.001)
}
```

- [ ] **Step 2: Run the store tests to verify they fail**

Run:

```bash
cd ios
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TreddyTests/TreadmillStoreTests
```

Expected: FAIL because the current store has no injection seams, route state, HRM state, or reconciliation guards.

- [ ] **Step 3: Add test seams to the store/websocket**

Introduce lightweight protocols:

```swift
protocol TreadmillAPIClient: Sendable { ... }
protocol TreadmillWebSocketClient: AnyObject { ... }
```

Expose websocket callbacks for:

- `status`
- `program`
- `session`
- `connection`
- `hr`
- `scan_result`

and let `TreadmillStore` accept injected API/socket instances in its initializer.

- [ ] **Step 4: Implement optimistic control/reconciliation**

In `ios/Treddy/State/TreadmillStore.swift`, add:

- `currentRoute`
- `isSettingsPresented`
- `debugUnlocked`
- `smartassEnabled`
- `userProfile`
- `hrmDevices`
- `voiceState`
- `dirtySpeedAt`
- `dirtyInclineAt`

Representative reconciliation pattern:

```swift
private let reconcileWindow: TimeInterval = 0.75

private func shouldAcceptSpeedEcho(now: Date = .now) -> Bool {
    guard let dirtySpeedAt else { return true }
    return now.timeIntervalSince(dirtySpeedAt) > reconcileWindow
}
```

Use that guard before replacing optimistic values from websocket messages.

- [ ] **Step 5: Implement route transitions and settings/HRM loading**

Add store methods:

- `loadAll()`
- `presentSettings()`
- `navigate(to:)`
- `unlockDebug()`
- `refreshUserProfile()`
- `scanHrmDevices()`
- `selectHrmDevice(_:)`
- `forgetHrmDevice()`

Auto-route to `.running` when:

- quick/manual start succeeds
- workout/history resume starts a running program
- websocket/program state changes to running while the current route is `.lobby`

- [ ] **Step 6: Re-run the store tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/Treddy/State/TreadmillStore.swift ios/Treddy/Services/TreadmillWebSocket.swift ios/TreddyTests/TreadmillStoreTests.swift
git commit -m "feat: expand ios store for parity behavior"
```

---

### Task 4: Bring Lobby, Running, Settings, and Debug to the Common Contract

**Files:**
- Modify: `ios/Treddy/Views/LobbyView.swift`
- Modify: `ios/Treddy/Views/RunningView.swift`
- Modify: `ios/Treddy/Views/SettingsView.swift`
- Create: `ios/Treddy/Views/DebugView.swift`
- Create: `ios/Treddy/Views/Components/HrmSection.swift`
- Modify: `ios/TreddyUITests/TreddyUITests.swift`

- [ ] **Step 1: Write failing UI tests for the shared contract**

Add or update tests for:

- workout resume/start navigating into running
- running screen exposes pause/stop/skip and manual duration editing when applicable
- settings screen shows server/body/smart-ass/HRM/debug affordances
- hidden debug unlock works

Example:

```swift
func testSettingsShowsSmartassAndHrmSection() {
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.staticTexts["Smart-ass Mode"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Heart Rate Monitor"].exists)
}
```

- [ ] **Step 2: Run the targeted UI tests to verify they fail**

Run:

```bash
cd ios
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TreddyUITests/TreddyUITests/testSettingsShowsSmartassAndHrmSection
```

Expected: FAIL because the existing views do not yet implement the common contract.

- [ ] **Step 3: Upgrade `LobbyView`**

Implement:

- explicit active-workout resume affordance
- workout/history loading with running transition
- parity with Android’s workout/history browsing semantics

Keep the view native; do not port Android layout literally.

- [ ] **Step 4: Upgrade `RunningView`**

Implement:

- optimistic speed/incline display from the store
- disabled/alpha state when disconnected
- skip button
- manual duration editing surface
- HR metric when HRM is connected
- visible voice button/state

Minimal structure:

```swift
if store.status.hrmConnected {
    MetricLabel(value: "\(store.status.heartRate)", label: "bpm")
}
```

- [ ] **Step 5: Expand `SettingsView` and add `DebugView`**

Implement:

- server URL editing
- weight / vest editing
- smart-ass toggle
- connection status
- HRM section (scan/select/forget)
- hidden triple-tap debug unlock
- `DebugView` presentation

Triple-tap sketch:

```swift
@State private var debugTapTimes: [Date] = []

func registerDebugTap() {
    let now = Date()
    debugTapTimes = (debugTapTimes + [now]).filter { now.timeIntervalSince($0) < 0.5 }
    if debugTapTimes.count >= 3 { store.unlockDebug() }
}
```

- [ ] **Step 6: Re-run the updated UI tests**

Run the command from Step 2 plus any new running/debug tests you added.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ios/Treddy/Views/LobbyView.swift ios/Treddy/Views/RunningView.swift ios/Treddy/Views/SettingsView.swift ios/Treddy/Views/DebugView.swift ios/Treddy/Views/Components/HrmSection.swift ios/TreddyUITests/TreddyUITests.swift
git commit -m "feat: bring ios screens to common product contract"
```

---

### Task 5: Implement Working Gemini Live Voice on iOS

**Files:**
- Create: `ios/Treddy/Voice/VoiceCoordinator.swift`
- Create: `ios/Treddy/Voice/GeminiLiveClient.swift`
- Create: `ios/Treddy/Voice/FunctionBridge.swift`
- Create: `ios/Treddy/Voice/AudioCapture.swift`
- Create: `ios/Treddy/Voice/AudioPlayer.swift`
- Modify: `ios/Treddy/State/TreadmillStore.swift`
- Create: `ios/TreddyTests/VoiceCoordinatorTests.swift`

- [ ] **Step 1: Write failing voice state-machine tests**

Create `ios/TreddyTests/VoiceCoordinatorTests.swift` covering:

- toggle from idle -> connecting/listening when config is available
- speaking transition on first response audio
- return to listening after playback ends
- disconnect tears down the session
- tool calls use `/api/tool`

Example:

```swift
@MainActor
func testToolCallUsesFunctionBridge() async {
    let bridge = MockFunctionBridge()
    let coordinator = VoiceCoordinator(
        configProvider: { mockConfig },
        functionBridge: bridge,
        liveClientFactory: { _ in MockGeminiLiveClient() }
    )

    await coordinator.handleToolCall(name: "set_speed", args: ["value": .double(3.5)])

    XCTAssertEqual(bridge.lastName, "set_speed")
}
```

- [ ] **Step 2: Run the voice tests to verify they fail**

Run:

```bash
cd ios
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TreddyTests/VoiceCoordinatorTests
```

Expected: FAIL because no voice coordinator/client stack exists yet.

- [ ] **Step 3: Implement `FunctionBridge` first**

Mirror Android’s shape:

```swift
struct FunctionResult {
    let name: String
    let response: String
}

actor FunctionBridge {
    let api: TreadmillAPIClient
    func execute(name: String, args: [String: Any], context: String?) async -> FunctionResult { ... }
}
```

The bridge must call `/api/tool`, not duplicate treadmill business logic locally.

- [ ] **Step 4: Implement audio capture and playback**

Create:

- `AudioCapture.swift` for mic capture and speech-end timing
- `AudioPlayer.swift` for streamed Gemini PCM playback

Use Android/Web implementations as behavioral reference, not API-for-API duplication.

- [ ] **Step 5: Implement `GeminiLiveClient`**

Port the essential behavior from:

- `kotlin/.../voice/GeminiLiveClient.kt`
- `web/src/voice/GeminiLiveClient.ts`

Required responsibilities:

- connect websocket
- send setup payload using `/api/config` values
- stream mic audio
- receive audio responses
- handle tool calls via `FunctionBridge`
- emit `connected/listening/speaking/error` callbacks
- update Gemini with treadmill state context

- [ ] **Step 6: Implement `VoiceCoordinator` and wire it into the store**

`VoiceCoordinator` should own:

- current voice state
- background/live connection lifecycle
- mic activation
- playback lifecycle
- disconnect/background teardown

`TreadmillStore` should:

- create/own the coordinator
- expose `voiceState`
- provide current treadmill context updates to the coordinator
- surface shell/running button actions (`toggleVoice()`)

- [ ] **Step 7: Re-run the voice tests**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add ios/Treddy/Voice ios/Treddy/State/TreadmillStore.swift ios/TreddyTests/VoiceCoordinatorTests.swift
git commit -m "feat: add ios gemini live voice stack"
```

---

### Task 6: End-to-End Verification and UI Test Cleanup

**Files:**
- Modify: `ios/TreddyUITests/TreddyUITests.swift`
- Modify: any touched iOS files as needed from bugfix fallout

- [ ] **Step 1: Run the full iOS test suite**

Run:

```bash
cd ios
xcodegen generate
xcodebuild test -project Treddy.xcodeproj -scheme Treddy -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS for all unit and UI tests.

- [ ] **Step 2: Fix any final parity regressions with TDD**

For each failing test:

- write or update the smallest failing reproduction
- rerun just that test to confirm red
- apply the smallest fix
- rerun targeted test
- rerun the full suite before proceeding

- [ ] **Step 3: Run manual simulator validation against the Pi**

Use the real server:

- confirm iOS defaults to `https://rpi:8000`
- verify lobby loads workouts/history
- start or resume a workout and confirm auto-navigation
- change speed/incline and confirm optimistic behavior
- verify settings changes persist
- verify HRM controls populate and operate
- verify voice connects, listens, speaks, and executes tool calls

- [ ] **Step 4: Commit final integration fixes**

```bash
git add ios
git commit -m "test: verify ios parity flow end to end"
```

---

## Local Review Notes

This plan intentionally starts with transport/contract correctness because the current iOS client is still missing real server capabilities and already has at least one concrete protocol bug (`POST /api/user` vs `PUT /api/user`). Do not start by restyling views.

The highest-risk area is Task 5. Read the Android and web voice implementations completely before coding the iOS version.
