# iOS Common-Core Parity Design

Date: 2026-04-02
Repo: `precor-9.3x`
Scope: Bring the iOS app to functional parity with the Android app while allowing iOS-native UI and implementation details.

## Goal

Define and implement a common product surface across Android and iOS so both clients expose the same treadmill functionality:

- navigation shell
- workout browsing and history
- running controls with optimistic updates
- settings and profile management
- HRM visibility and management
- hidden debug access
- end-to-end voice with Gemini Live and tool execution

The requirement is parity of behavior, not literal UI cloning. iOS may use native presentation patterns and simplified layouts as long as capabilities and state transitions are preserved.

## Non-Goals

- Pixel-matching Android visuals on iOS
- Rewriting the server contract
- Replacing the existing Android implementation
- Shipping a voice placeholder or partial voice flow

## Common Product Contract

### Navigation

Both platforms must expose these functional destinations:

- `Lobby`
- `Running`
- `Settings`
- `Voice`
- `Debug`

`Debug` is intentionally hidden behind the same class of affordance as Android and is not a top-level destination.

### Lobby

Both clients must support:

- quick start
- manual start
- resume active workout when one exists
- browsing saved workouts
- browsing recent/generated programs
- loading a workout or history entry
- transitioning into the running experience when a workout starts or resumes

### Running

Both clients must support:

- timer / elapsed workout display
- session metrics
- encouragement display
- speed and incline controls
- pause / resume
- stop
- skip interval
- manual-workout duration adjustment
- connection-aware control enablement
- HR display when HRM is connected
- visible voice availability/state

### Settings

Both clients must support:

- server URL editing and persistence
- body profile update (`weight_lbs`, `vest_lbs`)
- smart-ass mode toggle
- connection status display
- HRM state/device visibility
- HRM scanning / selection / forget flow
- hidden debug unlock

If GPX import is already feasible on iOS in this pass, it should be included. If it is deferred for a platform-specific reason, the deferral must be explicit and documented rather than silently omitted.

### Voice

Both clients must support the same logical voice lifecycle:

- idle
- connecting
- listening
- speaking

Both clients must use the same server-owned tool surface:

- fetch runtime/config bootstrap from `/api/config`
- execute functions through `/api/tool`
- let server-side logic remain the single source of truth for treadmill actions

Voice is part of the required common core. UI-only parity without working Gemini Live integration is not acceptable for this pass.

### State and Reconciliation

Both clients must follow the same behavior rules:

- local speed and incline changes are optimistic
- writes are debounced or coalesced before transport
- websocket state remains the source of truth after local optimistic updates
- reconciliation must avoid websocket echoes instantly stomping recent local control changes
- disconnected state must be surfaced globally and degrade controls and voice safely
- program start/load events should auto-transition the user into the running experience where appropriate

## Recommended iOS Architecture

### App Shell

Replace the current minimal `TabView` app structure with a root shell that owns:

- global disconnect banner
- top-level navigation state
- settings presentation
- hidden debug presentation
- voice entry point and voice-state visibility

iOS does not need to copy Android's nav rail literally. Native shell choices are acceptable, including:

- adaptive tab shell in compact layouts
- split/navigation structures in larger layouts
- sheets for settings/debug

The important constraint is functional reachability and consistent state behavior, not identical chrome.

### Store Layer

Expand `TreadmillStore` from a thin transport wrapper into the iOS product-state coordinator. It should own:

- connection state
- websocket-fed status/session/program state
- workouts and history collections
- optimistic speed/incline state and reconciliation guards
- settings/profile state
- HRM device list/state
- route transitions such as auto-navigation into running
- debug unlock state

`TreadmillAPI` and `TreadmillWebSocket` should remain transport/service layers, not application-state layers.

### Optimistic Control Model

iOS should mirror Android's conceptual control behavior:

- update speed/incline locally immediately
- mark the local write as dirty
- debounce outbound network writes
- ignore or delay stale websocket reconciliation for a short window after local changes

This does not have to match Android line-for-line, but the user-visible behavior should.

### Voice Coordinator

iOS needs a dedicated voice coordinator equivalent in responsibility to Android's `VoiceViewModel`, covering:

- Gemini Live session lifecycle
- microphone capture
- end-of-speech handling
- audio playback
- tool-call bridging
- state transitions among `idle`, `connecting`, `listening`, `speaking`
- teardown on disconnect/backgrounding/error

This should not be embedded ad hoc into a view.

### Screen Responsibilities

#### Lobby

Add:

- richer active-workout resume behavior
- workout/history loading flows aligned to Android behavior
- transition into running after start/load where applicable

#### Running

Add:

- optimistic speed/incline behavior
- connected/disabled control states
- manual duration editing
- HR metric visibility when connected
- voice affordance and state visibility

#### Settings

Expand from the current minimal form to the full common contract. A settings sheet is acceptable on iOS even if Android uses a bottom sheet and different styling.

#### Debug

Add a separate debug surface reachable through the hidden unlock path in settings.

## Implementation Strategy

Recommended order:

1. Define the parity checklist and missing-iOS surface from Android and server behavior.
2. Rework the iOS shell and store so global state, routing, and settings/voice ownership are correct.
3. Upgrade lobby, running, settings, and debug to the common contract.
4. Add optimistic/debounced control behavior.
5. Integrate working Gemini Live voice end to end.
6. Tighten tests and run simulator validation against `https://rpi:8000`.

This order reduces churn because voice, shell, and control semantics all depend on a stronger app-level state model than the current iOS client has.

## Verification Plan

### Automated Tests

Keep and extend model decoding tests.

Add store-level tests for:

- optimistic speed update
- optimistic incline update
- reconciliation after websocket updates
- route transitions into running
- settings persistence / reload behavior

Add voice-focused tests where practical for:

- state transitions
- tool bridge request shaping
- teardown behavior

Expand UI tests to verify:

- global shell/navigation
- settings contents and connection display
- running controls and connected/disabled behavior
- voice affordance visibility/state
- hidden debug unlock flow

### Manual Validation

Validate on simulator/device against the real Pi endpoint:

- workout browsing and start/load flows
- run-state transitions
- speed/incline behavior under websocket updates
- connection banner behavior
- settings changes persisting and applying
- HRM visibility
- voice connect/listen/speak/tool-call loop

## Risks

- Voice is the highest-risk item because Android already contains significant lifecycle logic and iOS currently does not.
- The existing iOS app is structurally underpowered relative to Android, so trying to patch features one by one without a shell/store redesign will likely miss behavior again.
- UI tests tied to the old `TabView`/settings structure may need to be updated once the native iOS shell is corrected.

## Decision

Proceed with a common behavior contract and a native iOS implementation, not a literal Android UI port.
