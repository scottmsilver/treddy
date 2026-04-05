# iPad App Redesign — Match Android Tablet Layout

**Date:** 2026-04-04
**Scope:** Rewrite the iOS/iPad Treddy app UI to match the Android tablet design language while feeling iOS-native.

## Summary

The current iOS app uses a phone-first layout (top chrome bar, stacked views) that looks wrong on iPad. Redesign to match the proven Android tablet layout: left nav rail, orientation-aware layouts, large touch targets — but using native SwiftUI idioms (SF Symbols, system materials, safe area insets).

## Design Decisions

- **Layout pattern:** Match Android tablet — left nav rail in landscape, bottom tab bar in portrait
- **First launch:** Setup screen for server URL (like Android SETUP route), shown once
- **Route flow:** Setup → Profile Picker → Lobby → Running (same as Android)
- **Running view:** Timer top-center, metrics row below, elevation profile + speed/incline controls below that, full-width stop bar at bottom
- **iOS-native:** SF Symbols (not emoji), system materials for cards, SwiftUI conventions throughout
- **Both orientations:** Landscape-primary but portrait must work (stacked layout)

## Screens

### 1. Navigation Shell

**Landscape (primary for iPad on treadmill):**
- Left nav rail, ~56pt wide, dark background
- 5 items vertically centered: Profile avatar, Home (`house.fill`), Run (`figure.run`), Voice (`mic.fill`), Settings (`gearshape.fill`)
- Icon-only, no labels
- Selected state: full opacity. Unselected: 35% opacity
- Content fills remaining width to the right

**Portrait:**
- Bottom tab bar, ~56pt tall
- Same 5 items horizontally spaced
- Icons with labels below
- Content fills above

**Shared:**
- Disconnect banner above content when not connected
- Nav shell hidden on Setup and Profile Picker screens
- Profile avatar shows initials + color circle (28pt in rail, with profile color background)

### 2. Setup Screen (first launch only)

- Centered card with server URL text field
- "Connect" button
- Shown when `UserDefaults` has no saved `server_url`
- On successful connect, saves URL and navigates to Profile Picker
- No nav chrome visible

### 3. Profile Picker

- Full-screen, centered vertically
- "Who's running today?" title
- Horizontal scroll of profile avatars (80pt circles)
- Each profile: color circle with initials (or async avatar image), name below
- Guest button: gradient circle with 👋, "Guest" label, "Jump right in" subtitle
- Add button: dashed circle with "+", "Add" label
- Create form: card with name field, color picker (5 swatches), Cancel/Create buttons
- No nav chrome visible
- Matches Android profile picker layout exactly

### 4. Lobby

- Personalized greeting: "Good evening, Scott" / "Good evening, Guest"
- "Ready for a run?" subtitle
- Action buttons: "Quick" (secondary) + "Manual" (primary, green)
- If workout active: "Return to Workout" button + mini status card showing current interval + elapsed time
- "MY WORKOUTS" section — vertical list of saved workout cards
- "YOUR PROGRAMS" section — vertical list of history cards
- Each card: name (bold), duration + interval count, last run stats, heart icon or X button
- Content constrained to max ~640pt width on iPad (centered)

### 5. Running View

**Landscape layout (top to bottom):**

1. **Timer** — top center, very large (~72pt+), bold, tabular-nums. Dominant element.
2. **Metrics row** — horizontal, centered below timer. Values bold, units in smaller muted text. Items: pace (green when active), distance, vert ft, calories. Heart rate when HRM connected (red).
3. **Middle section** — flex row:
   - **Elevation profile card** (takes majority width): Canvas-drawn staircase chart with grid lines, axis labels (incline % on Y, time on X), completed fill (green), progress dot with glow, interval counter "X of Y" top-right. Tap to show/hide play/pause overlay. Double-tap sides to skip.
   - **Speed/Incline controls** (~240pt fixed width): Two panels stacked vertically. Each panel has single chevron (±0.1 mph / ±0.5%) and double chevron (±1.0 mph / ±1.0%) buttons flanking the centered value. Speed value in green, incline value in primary text color. Units below value ("mph", "% incline"). Hold-to-repeat on buttons.
4. **Stop bar** — full width, red, rounded corners, large touch target. When paused: Resume + Reset buttons instead.
5. **Encouragement text** — overlaid above timer, green tint, fades in/out

**Portrait layout:**
- Same elements but stacked vertically:
  - Timer + metrics at top
  - Elevation profile full-width
  - Speed/incline controls horizontal (side by side)
  - Stop bar at bottom

### 6. Settings

- Sheet presentation (existing pattern works)
- Server URL input
- Smart-ass mode toggle
- Body section (weight, vest)
- Connection status
- HRM device management
- Debug unlock (triple-tap)

### 7. Debug

- Same as current — connection info, workout state, nav buttons

## Architecture

### File Structure

```
ios/Treddy/
  App/
    TreddyApp.swift          (unchanged)
    AppRoute.swift            (add .setup case)
    AppShellView.swift        (rewrite: orientation-aware nav rail/tab bar)
  Models/
    TreadmillModels.swift     (already has Profile, ProfileChangedMessage — done)
  Services/
    TreadmillAPI.swift        (already has profile endpoints — done)
    TreadmillWebSocket.swift  (already has profile_changed — done)
    TrustAllDelegate.swift    (unchanged)
  State/
    TreadmillStore.swift      (already has profile state — done. Add setupComplete flag)
  Views/
    SetupView.swift           (NEW — server URL input)
    ProfilePickerView.swift   (exists — keep, minor tweaks)
    LobbyView.swift           (rewrite for tablet layout)
    RunningView.swift         (rewrite — landscape/portrait running layouts)
    SettingsView.swift        (minor tweaks)
    DebugView.swift           (unchanged)
    Components/
      NavRail.swift           (NEW — orientation-aware nav rail/tab bar)
      ProfileAvatarButton.swift (exists — integrated into NavRail)
      ElevationProfile.swift  (NEW — Canvas-based chart)
      SpeedInclineControls.swift (NEW — chevron button panels)
      MetricsRow.swift        (NEW — horizontal metrics display)
      VoiceButton.swift       (unchanged, integrated into NavRail)
      HrmSection.swift        (unchanged)
      DisconnectBanner.swift  (unchanged)
  Voice/
    (all unchanged)
```

### Orientation Detection

```swift
// In NavRail / AppShellView
let isLandscape = horizontalSizeClass == .regular ||
                  UIDevice.current.orientation.isLandscape
```

Use SwiftUI `@Environment(\.horizontalSizeClass)` as primary signal, with device orientation as fallback. iPad in landscape → `.regular` → left rail. Portrait → bottom bar.

### State Changes

- Add `setupComplete: Bool` to TreadmillStore (backed by UserDefaults)
- Initial route: `.setup` if not setupComplete, else `.profilePicker`
- After setup completes: `setupComplete = true`, navigate to `.profilePicker`

## What's Already Done

The profile feature work from this session is complete and compiles:
- `Profile`, `ProfileChangedMessage`, `ActiveProfileResponse` models with Postel's Law decoding
- Profile API endpoints in TreadmillAPI
- `profile_changed` WebSocket handling
- Profile state in TreadmillStore (activeProfile, guestMode, profiles)
- ProfilePickerView with avatar circles, guest mode, create form
- ProfileAvatarButton component
- Decoding tests (9 new tests)

## What Needs Building

1. **NavRail** — new orientation-aware component replacing the current top chrome bar
2. **SetupView** — one-time server URL entry
3. **AppShellView rewrite** — use NavRail, orientation-aware layout
4. **LobbyView rewrite** — match Android lobby (greeting, buttons, workout cards, content width constraint)
5. **RunningView rewrite** — the big one. Timer, metrics, elevation profile, speed/incline controls, stop bar
6. **ElevationProfile** — Canvas/Path-based chart component
7. **SpeedInclineControls** — chevron buttons with hold-to-repeat
8. **MetricsRow** — horizontal metrics with HR support

## Non-Goals

- No iPad multitasking / Split View support
- iPhone uses portrait layout naturally (bottom tab bar, stacked content) — same code path, no phone-specific branches needed
- No custom fonts (system font is fine for iPad — Quicksand is in the Android/web apps but not critical for v1)
- No avatar upload from iPad (can view avatars, but upload is desktop/web)
