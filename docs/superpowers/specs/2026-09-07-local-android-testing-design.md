# Local Android testing

User approved: one warm local tablet emulator, parallel builds, serialized device
access, mock-only networking, smaller fast display and full-resolution visual gates.

## Interface and boundaries

Provide `python3 scripts/android_local.py start`, `test`, and `view`. Start owns
a foreground emulator process; leave that terminal running between jobs. Test and
view acquire one user-global device lock (shared across worktrees), verify the
dedicated AVD and hardware renderer, and use only the exact emulator serial.
Builds happen independently before acquiring the device. No physical-device
autodiscovery, adb-server restarts, process-wide kills, or system driver changes.

Use an explicitly created `treddy_local_test` AVD (API 35 Google APIs x86_64), not
an existing personal AVD. Fast display: 1280x800 at 160dpi; full display:
2560x1600 at 320dpi. Both retain the same logical tablet canvas. Four virtual
cores and 4096MB RAM; KVM; no snapshots initially. Warm reuse is the primary
speed improvement. Changing display profile requires stopping/restarting start.

Linux NVIDIA path verified here: extracted VirtualGL 3.1.5, EGL device `egl0`,
direct SDK headless QEMU binary, `ANDROID_EGL_ON_EGL=1`,
`ANDROID_EMU_HEADLESS=1`, `ANDROID_EMULATOR_LAUNCHER_DIR` set to SDK emulator.
VirtualGL library path includes its extracted usr/lib and SDK emulator/lib64.
Do not silently fall back to software rendering: verify guest SurfaceFlinger
reports NVIDIA and reject llvmpipe/SwiftShader. Renderer check does not prove
performance; report timings from real tests separately.

Each test/view job owns a new mock server process and temporary working
directory/database. Bind HTTP only to 127.0.0.1 using a parent-reserved socket
passed to uvicorn (`--fd`), avoiding free-port races. Force TREADMILL_MOCK=1 and
isolate the server working directory so real DB, JSON migration files, TLS keys,
and API keys are not picked up. Health checks must not accept an unrelated
process. Install explicit APKs, force-stop the app, write dedicated test-profile
DataStore preferences directly (server_url to emulator host alias, voice off,
microphone prompt already handled), and verify readback before launching.
Never tap Setup discovery. Test runs instrumentation; view launches MainActivity
and holds the job lock/server until interrupted. Cleanup force-stops the app
before stopping its mock backend. Cleanup only processes created by that job.

Use the existing unminified uiTest APK and test APK; no Android production source
changes. Test results must detect instrumentation failures even when adb exits 0.
All subprocesses, boot polling, lock waits, and health checks have deadlines.
Interrupts terminate/reap only owned children and release locks.

## Evidence and delivery

Standard-library unit tests cover argument validation, exact targeting,
cross-process lock exclusion, child lifecycle, mock isolation, preferences,
timeouts and instrumentation result parsing. Root agent alone performs actual
emulator operations. Run real layout tests twice through the finished wrapper,
exercise the view path against the mock, verify full-resolution profile, and
record timings without claiming broad performance wins from two small tests.
Screenshots/logs remain outside git. Document dependency installation, commands,
limits and recovery; push reviewed changes. Physical-tablet acceptance remains
a separate task.
