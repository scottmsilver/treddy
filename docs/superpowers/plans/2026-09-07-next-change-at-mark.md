# Next-Change “X at Y” Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Ridgeline HUD’s parenthesized next-change clock with the approved single-line `X at Y` hierarchy while preserving clock behavior and explicit accessibility.

**Architecture:** Split `NextChangeDisplay` into two visual values plus one semantic sentence, leaving its clock arithmetic untouched. Render the special row in a dedicated composable so the dominant foreground `X` and smaller green `at Y` use the existing adaptive-legibility system without complicating generic metric rows.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit 4, Gradle, ADB/UIAutomator, FastAPI mock mode, GitHub CLI native attachments.

---

### Task 1: Split the next-change display model

**Files:**
- Modify: `kotlin/app/src/test/java/com/precor/treadmill/ui/screens/running/NextChangeDisplayTest.kt`
- Modify: `kotlin/app/src/main/java/com/precor/treadmill/ui/screens/running/NextChangeDisplay.kt`

- [ ] **Step 1: Write the failing model assertions**

Replace every assertion against `display.text` with assertions against the two separately formatted fields. Preserve every arithmetic and accessibility assertion. The representative first test becomes:

```kotlin
assertEquals("4:43", display.timeUntilText)
assertEquals("16:33", display.timerAtChangeText)
assertEquals(
    "Next change in 4:43; workout elapsed at change 16:33",
    display.accessibilityDescription,
)
```

Add a long-duration case proving the model can supply both ends of the approved one-line phrase without punctuation:

```kotlin
@Test
fun `long clock values remain separate visual fields`() {
    val display = formatNextChange(
        nextChangeProgramPosition = 3_599.0,
        clock = NextChangeClock(
            sessionElapsed = 39_597.0,
            programElapsed = 0.0,
            programDuration = 43_200.0,
        ),
        timeMark = WorkoutTimeMark.ELAPSED,
    )

    assertEquals("59:59", display.timeUntilText)
    assertEquals("11:59:56", display.timerAtChangeText)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd kotlin
./gradlew testDebugUnitTest --tests com.precor.treadmill.ui.screens.running.NextChangeDisplayTest
```

Expected: compile failure because `timeUntilText` and `timerAtChangeText` do not exist. Save the unedited output and real nonzero status in an OS-temporary evidence directory.

- [ ] **Step 3: Implement the minimal model split**

Change the data class to:

```kotlin
internal data class NextChangeDisplay(
    val timeUntilText: String,
    val timerAtChangeText: String,
    val accessibilityDescription: String,
)
```

Return those named fields from `formatNextChange`. Do not change `NextChangeClock`, rounding, clamping, timer-mode selection, or the accessibility sentence.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same Gradle command. Expected: `NextChangeDisplayTest` passes.

- [ ] **Step 5: Commit the model change**

```bash
git add kotlin/app/src/main/java/com/precor/treadmill/ui/screens/running/NextChangeDisplay.kt \
  kotlin/app/src/test/java/com/precor/treadmill/ui/screens/running/NextChangeDisplayTest.kt
git commit -m "refactor: separate next-change clock values"
```

### Task 2: Render the approved foreground/accent hierarchy

**Files:**
- Modify: `kotlin/app/src/test/java/com/precor/treadmill/ui/screens/running/RidgelineNextChangeClockSourceTest.kt`
- Create: `kotlin/app/src/androidTest/java/com/precor/treadmill/ui/screens/running/NextChangeValueRowTest.kt`
- Modify: `kotlin/app/src/main/java/com/precor/treadmill/ui/screens/running/RidgelineHud.kt`

- [ ] **Step 1: Add failing structural presentation tests**

Extend the established source-level guard to require:

```kotlin
assertTrue(source.contains("private fun NextChangeRow("))
assertTrue(source.contains("tightNum(next.timeUntilText)"))
assertTrue(source.contains("text = \"at\""))
assertTrue(source.contains("text = next.timerAtChangeText"))
assertTrue(source.contains("color = RidgelineTheme.accent"))
assertFalse(source.contains("value = next.text"))
```

Also isolate the `NextChangeRow` source block and assert it contains baseline alignment, `12.sp` for `at`, `14.sp` for `Y`, and `clearAndSetSemantics`, and contains neither a literal parenthesis nor visible `remaining`/`elapsed` text. This guard covers presentation intent; the instrumented test in the next step covers actual measurement.

- [ ] **Step 2: Add a failing instrumented one-line measurement test**

Create `NextChangeValueRowTest.kt` using `createComposeRule`. Render `NextChangeValueRow` inside `Box(Modifier.width(180.dp))` for each required pair:

```kotlin
private val cases = listOf(
    "59:59" to "1:00:00",
    "1:00:00" to "12:34:56",
)
```

For each case, fetch the unmerged semantics bounds of `X`, literal `at`, and `Y`, plus the root bounds. Require:

```kotlin
assertTrue(xBounds.right <= atBounds.left)
assertTrue(atBounds.right <= yBounds.left)
assertTrue(yBounds.right <= rootBounds.right)
assertTrue(xBounds.top < yBounds.bottom && yBounds.top < xBounds.bottom)
```

Use the exact full text selectors and `assertIsDisplayed()` before measuring. For each of the three text nodes, invoke `SemanticsActions.GetTextLayoutResult`, require exactly one result, and assert:

```kotlin
assertEquals(1, layoutResult.lineCount)
assertFalse(layoutResult.hasVisualOverflow)
```

The layout-result checks prove the actual glyph layout is neither wrapped, clipped, nor ellipsized; semantics text alone is not accepted as evidence of this. Together with the bounds assertions, the test proves left-to-right order, one-row vertical overlap, and containment at a width narrower than the target tablet’s available map space.

- [ ] **Step 3: Run the structural and instrumented tests and verify RED**

```bash
cd kotlin
./gradlew testDebugUnitTest --tests com.precor.treadmill.ui.screens.running.RidgelineNextChangeClockSourceTest
ANDROID_SERIAL='adb-R9ZY90P5LZP-WMXOYu._adb-tls-connect._tcp' \
  ./gradlew connectedUiTestAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.precor.treadmill.ui.screens.running.NextChangeValueRowTest
```

Expected: the unit guard fails and the instrumented test does not compile because `NextChangeRow`/`NextChangeValueRow` and the split rendering do not exist.

- [ ] **Step 4: Implement `NextChangeRow` and its measurable value row**

In `MetricsPill`, change the panel accents to:

```kotlin
accents = listOf(RidgelineTheme.fg, RidgelineTheme.accent)
```

Replace the special `MetricRow` call with `NextChangeRow(next)`. Implement a private semantic/label wrapper plus an internal `NextChangeValueRow(next)` containing:

- the existing `NEXT IN` label styling;
- one non-wrapping Compose `Row`, with the exact text nodes left visible when `NextChangeValueRow` is tested directly;
- `tightNum(next.timeUntilText)` in `RidgelineTheme.fg`, `RidgelineMonoFamily`, 17sp, medium weight;
- literal `at` in `RidgelineTheme.accent`, `RidgelineLabelFamily`, 12sp, medium weight, with 4dp start padding;
- `next.timerAtChangeText` in `RidgelineTheme.accent`, `RidgelineMonoFamily`, 14sp, medium weight, with 3dp start padding;
- `alignByBaseline()` on all three pieces;
- `clearAndSetSemantics { contentDescription = next.accessibilityDescription }` on the containing `NextChangeRow` column, outside `NextChangeValueRow`.

Use `Color.legibleOn` for the raw `Text` values that require `AnnotatedString`; use `LegibleText` for the literal `at` and any plain string. Do not add a new design token or modify the generic `MetricRow`.

- [ ] **Step 5: Run the focused model, presentation, and measured-layout tests**

```bash
cd kotlin
./gradlew testDebugUnitTest \
  --tests com.precor.treadmill.ui.screens.running.NextChangeDisplayTest \
  --tests com.precor.treadmill.ui.screens.running.RidgelineNextChangeClockSourceTest
ANDROID_SERIAL='adb-R9ZY90P5LZP-WMXOYu._adb-tls-connect._tcp' \
  ./gradlew connectedUiTestAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.precor.treadmill.ui.screens.running.NextChangeValueRowTest
```

Expected: both JVM classes and the instrumented measurement class pass for both long-value pairs at 180dp.

- [ ] **Step 6: Commit the UI change**

```bash
git add kotlin/app/src/main/java/com/precor/treadmill/ui/screens/running/RidgelineHud.kt \
  kotlin/app/src/test/java/com/precor/treadmill/ui/screens/running/RidgelineNextChangeClockSourceTest.kt \
  kotlin/app/src/androidTest/java/com/precor/treadmill/ui/screens/running/NextChangeValueRowTest.kt
git commit -m "feat: polish next-change clock hierarchy"
```

### Task 3: Verify, review, and land the code

**Files:**
- Verify only: entire Android project

- [ ] **Step 1: Run the full Android gate**

```bash
cd kotlin
./gradlew testDebugUnitTest assembleDebug
```

Expected: all unit tests and debug APK assembly succeed.

- [ ] **Step 2: Verify scope and repository hygiene**

```bash
git diff --check origin/main...HEAD
git diff --name-only origin/main...HEAD
git status --short
```

Expected: only the approved spec/plan and five Kotlin source/test files differ; no image is tracked or staged.

- [ ] **Step 3: Request code review and address only verified findings**

Use `superpowers:requesting-code-review`. Review against `docs/superpowers/specs/2026-09-05-next-change-at-mark-design.md`, including accessibility, adaptive legibility, long values, and scope. Re-run focused and full gates after any code change.

- [ ] **Step 4: Push and merge the PR**

```bash
git pull --rebase origin main
git push -u origin codex/next-change-at-mark
gh pr create --base main --head codex/next-change-at-mark \
  --title "Polish next-change workout clock" \
  --body "Renders the next-change clocks as a dominant X with quieter inline 'at Y', preserving explicit accessibility and clock behavior."
```

Merge after checks pass, fetch `origin/main`, and pin the full merged SHA. If main advances later, rebuild and redeploy before posting evidence.

### Task 4: Deploy and capture safe tablet evidence

**Files:**
- Build output: `kotlin/app/build/outputs/apk/debug/app-debug.apk` from a clean detached final-main worktree
- Evidence: OS-temporary files only

- [ ] **Step 1: Build authoritative merged main and record provenance**

Create a clean detached worktree at `origin/main`. Run `./gradlew testDebugUnitTest assembleDebug`, record the full Git SHA plus APK SHA-256, and pull the currently installed APK for rollback. Capture the tablet’s DataStore file, microphone permission signature, current activity, and screen timeout before mutation.

- [ ] **Step 2: Prove the real treadmill is stationary before mutation**

Read the saved server URL from the DataStore and query `/api/status`, `/api/session`, and `/api/program`. Require real motor feedback `.motor.belt == "0"`, `.motor.mph == "0"`, `.emu_speed_mph == 0`, inactive session, and inactive program. Treat top-level configured speed as non-authoritative. Send no real treadmill movement command.

- [ ] **Step 3: Install and checksum-verify the final APK**

Use only the exact tablet serial and `adb install -r`. Launch with `am start -W`, condition-poll either Android `ResumedActivity` field variant, pull the installed base APK, and require byte identity with the built artifact. On any mismatch, reinstall the saved APK and restore the immutable DataStore/permission state.

- [ ] **Step 4: Start a hard-interlocked mock backend**

Start final-main `python/server.py` in a persistent PTY with a temporary database, unique port, and `TREADMILL_MOCK=1`. Seed a two-interval history program at an elapsed position in its final interval, so countdown mode ends with `X at 0:00`. Require the server process environment contains `TREADMILL_MOCK=1`.

Force-stop the app and create an internal backup of its DataStore. Generate a temporary AndroidX Preferences protobuf whose encoder first reproduces the immutable original byte-for-byte, then changes only `server_url` to the mock URL. Install it while the app is stopped, read it back, and require exact byte identity and decoded URL equality before launching. Do not use the mDNS Setup UI.

- [ ] **Step 5: Validate both visual states and accessibility**

Resume the seeded mock program. In countdown mode, dump accessibility and require the explicit sentence ends with `workout remaining at change 0:00`. Capture a screenshot and visually verify it shows `X at 0:00` on one line with no parentheses or visible mode word.

Tap the hero timer to count-up mode. Require accessibility now says `workout elapsed at change Y`; capture a second screenshot and visually verify the same hierarchy. Confirm the mock process environment again before every program API call.

- [ ] **Step 6: Restore device state unconditionally**

Stop only the mock program through the mock API. Force-stop the app, restore the exact backed-up DataStore and microphone permission signature, restore the original screen timeout, launch, and compare the restored DataStore byte-for-byte. Stop the mock server and require its port is closed. Leave the verified new APK installed. Re-query the real server and require the belt, session, and program remain stationary/inactive.

- [ ] **Step 7: Attach evidence to GitHub issue #64**

Use a checksum-verified GitHub CLI with `issue comment --attach`. Post a comment containing `Problem`, `Root cause / gap`, `RED`, `GREEN`, `Device validation`, and `Delivery`, naming the final SHA, PR, APK checksum, mock interlock, accessibility result, and real stationary belt result. Attach the new PNGs as native GitHub issue attachments; do not store them in the repository. Read the comment back through the API and verify issue ownership, headings, SHA, PR URL, and downloadable image payloads.

- [ ] **Step 8: Close tracking and complete session protocol**

Close `precor-9_3x-t3e`, run `bd dolt push`, then run `git pull --rebase`, `git push`, and `git status` on the development branch. Fast-forward the primary worktree only if its existing `.beads`/`static/` changes can remain untouched. Remove temporary worktrees and move the OS evidence directory to trash only after attachment verification and exact device-state restoration.
