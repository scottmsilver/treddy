# Local Android testing

Use one warm emulator for device work and build in parallel in separate
worktrees. This workflow targets **only** the dedicated `treddy_local_test` AVD;
it is not a physical-tablet deployment tool.

## One-time setup (Linux x86_64 / NVIDIA)

Requirements: working `/dev/kvm`, Android SDK emulator and API 35 Google APIs
x86_64 image, Python with the project's server dependencies, and a usable X
display (the NVIDIA EGL route works through this machine's VNC display).
No cloud subscription or system driver changes are required.

VirtualGL is extracted into a user-owned directory, not installed system-wide.
The verified release is [VirtualGL 3.1.5](https://github.com/VirtualGL/virtualgl/releases/tag/3.1.5).
Download `virtualgl_3.1.5_amd64.deb` from that release into a temporary directory.
Verify its SHA256 before extracting:

```text
df3f7788ce41b182a47c0d298e5cd6d2d63579522cb41825970b7726e825485e
```

```bash
sha256sum /absolute/path/virtualgl_3.1.5_amd64.deb
# Choose a NEW destination; don't overwrite an existing installation.
dpkg-deb -x /absolute/path/virtualgl_3.1.5_amd64.deb \
  "$HOME/.local/share/treddy/virtualgl-3.1.5"

"$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
  -n treddy_local_test -k 'system-images;android-35;google_apis;x86_64' \
  -d pixel_tablet
```

Do not use `--force` to overwrite another AVD. On sukkot both the dependency and
dedicated AVD have already been set up. SDK discovery defaults to `~/Android/Sdk`;
`ANDROID_SDK_ROOT` or `ANDROID_HOME` can override it. VirtualGL's extracted root
can be set with `TREDDY_VIRTUALGL_ROOT`.

## Normal development loop

From the repository root, leave the emulator owner running in one terminal:

```bash
python3 scripts/android_local.py start
```

Build in any worktree, without acquiring the device lock:

```bash
cd kotlin
./gradlew :app:testDebugUnitTest :app:assembleUiTest :app:assembleUiTestAndroidTest
cd ..
```

Then run the device tests from that same worktree:

```bash
python3 scripts/android_local.py test

# Or a focused class:
python3 scripts/android_local.py test \
  --class com.precor.treadmill.ui.screens.running.NextChangeValueRowTest
```

`test` uses that checkout's unminified `uiTest` and Android-test APKs, installs
them on the exact emulator serial, configures a private mock backend, and checks
the instrumentation result rather than trusting adb's exit status alone. Use
`--app-apk` and `--test-apk` for explicitly selected artifacts. Normal production
build settings are unchanged.

For interactive UI inspection:

```bash
python3 scripts/android_local.py view
```

Keep `view` running while taking screenshots or exercising the mock UI. It owns
the emulator job lock and mock server until Ctrl-C. Store evidence under `/tmp`
or another directory outside git, and upload relevant images directly to GitHub
issues. Never use the Setup screen to discover or connect to a real treadmill.

## Profiles and ownership

The fast profile is 1280x800 at 160dpi. For final visual checks, stop the emulator
owner with Ctrl-C and restart at full resolution:

```bash
python3 scripts/android_local.py start --profile full
```

Full is 2560x1600 at 320dpi: the same logical tablet canvas, with more physical
pixels. Full-resolution emulator screenshots supplement, not replace, acceptance
on the actual tablet. Both profiles use four virtual cores and 4GB RAM.

The default console port is 5582 (`emulator-5582`). If overridden, use the same
`--port` for every command. User-global lockfiles live under
`~/.cache/treddy-android`, not in a worktree. Leave the lockfiles on disk: removing
a locked file can create two independent lock domains.

Only one `start` may own the dedicated AVD, and only one `test` or `view` may
control a device at a time across worktrees. Subagents may compile and run JVM
tests concurrently; they must use this runner for emulator jobs. Arbitrary raw
adb commands can bypass cooperative locks, so do not issue them from another
agent while a job owns the device. Do not restart adb or kill other emulators.

Each job creates its own mock server with `TREADMILL_MOCK=1`, a reserved loopback
socket and disposable working directory/database. The app gets only the emulator
host alias URL, with voice disabled. The runner bypasses Setup discovery, verifies
preference readback, and force-stops the app before removing its mock server.
An invalid placeholder overrides Gemini credentials so neither inherited keys
nor home-directory fallback keys are used. Cloud/voice features are not supported
by this mock-only workflow.
This is a controlled testing workflow, not an OS-level network sandbox.

## Recovery and verification

Ctrl-C the job first, then the emulator owner if needed. The runner terminates
and reaps only its own children. A timed-out test is a failure, not permission to
restart a shared adb server. After a crash, retry `start`; investigate occupied
ports rather than killing an unknown process. Startup checks must confirm
NVIDIA in Android's SurfaceFlinger output, not merely host Vulkan enumeration.
Software fallback is intentionally rejected.

The GPU route uses VirtualGL's EGL backend and the SDK's direct headless QEMU
binary with `ANDROID_EGL_ON_EGL=1` and `ANDROID_EMU_HEADLESS=1`. Ordinary
`emulator -gpu host` under VNC selected llvmpipe on this machine. This workaround
is version-sensitive: reverify after SDK/driver/VirtualGL upgrades.

Run the runner's host-side tests without an emulator:

```bash
python3 -m unittest discover -s scripts/tests -v
```

The initial GPU proof (SDK emulator 36.4.9, NVIDIA 580.173.02) booted in 68.7s;
two Compose layout tests passed in 10.434s initially and 6.03s on a warm rerun.
Those are small-test measurements, not a claim about full-app frame rate or a
controlled software-versus-GPU benchmark. Warm reuse avoids paying boot cost
for each edit/test cycle.

During runner validation on sukkot, the dedicated fast AVD booted in 29.628s
after its initial setup. The focused two-test class passed in 4.664s and 4.687s;
the latter job took **16.70s end to end**, including installs and mock setup.
The mock UI reached the lobby with HTTP/WebSocket traffic to the owned local
server. A simultaneous test request timed out on the job lock, as intended.
SIGTERM of the view job reaped its server and force-stopped the app. The Android
build and all 163 JVM tests also passed. These timings vary with host load.

The full profile subsequently booted in 25.811s and passed both layout tests in
7.687s. A job submitted during startup correctly waited for configuration to
finish (35.00s total, including the startup wait). A deliberately nonexistent
test class returned runner exit status 2 despite Android reporting completion
code -1, and its mock backend was cleaned up. That is a runner failure-path
check, not a failing reproduction of an application bug.
