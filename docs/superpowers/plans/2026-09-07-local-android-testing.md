# Local Android Testing Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development. Track status
> in bead precor-9_3x-6de, not Markdown checklists (repository instruction).

**Goal:** Repeatable warm, GPU-backed, mock-only Android testing on local Linux.

**Architecture:** A foreground emulator owner and mutually exclusive test/view
jobs. Per-job mock servers and disposable app preferences keep real hardware out
of scope. Builds run outside the lock.

**Tech stack:** Python standard library, flock, Android SDK API35, VirtualGL3.1.5,
existing FastAPI/uvicorn backend and Compose instrumentation tests.

## Task 1: Runner and automated tests

Create `scripts/android_local.py` and `scripts/tests/test_android_local.py`.
Implement the complete approved specification in the sibling specs document.
CLI global settings: SDK from ANDROID_SDK_ROOT/ANDROID_HOME or ~/Android/Sdk;
VirtualGL root from TREDDY_VIRTUALGL_ROOT or ~/.local/share/treddy/virtualgl-3.1.5;
AVD fixed treddy_local_test; emulator console port default 5582 (validated even
5554..5682); lock root user-global ~/.cache/treddy-android (never per worktree).
Expose --port and --profile fast/full for start; test/view use the same --port.
Allow --app-apk/--test-apk; default to current script checkout's uiTest outputs.
Allow optional --class for a focused test, otherwise run the whole test APK.

First write behavioral tests and record a genuine failing run. Then implement
the smallest runner satisfying them. Use separate functions for configuration,
command construction, locks, child ownership, mock server, preference encoding,
device verification and instrumentation parsing. Avoid generic plugin frameworks
or daemon managers. If substantially more than roughly 400 implementation lines
are needed, report the complexity before continuing.

Use subprocess argv arrays, not shell interpolation, for host commands. Explicit
adb -s on every device command. Validate AVD via `emu avd name` and boot/hardware
via getprop/dumpsys before mutating it. Reject occupied ports and duplicate AVD
owners on start. Hold startup/lifecycle lock until emulator exits; job lock is
separate and shared across all ports to keep access sequential. Keep lockfiles
on disk so unlinking cannot split the lock domain.

Generate minimal DataStore protobuf bytes for server_url (Value string field5),
voice_input_enabled false and microphone_permission_requested true (Value bool
field1), as Preferences map field1 entries with key field1/value field2. Test
encoding against an independently decoded expected field structure. Force-stop
before writing files/datastore/server_prefs.preferences_pb under run-as
com.precor.treadmill; verify exact bytes read back. Disposable dedicated AVD only.

Run `python3 -m unittest discover -s scripts/tests -v`; expect all GREEN. Include
real subprocess tests for lock contention and child reaping, mocks only for SDK
and device boundaries. Self-review and commit only assigned files. No actual adb,
emulator, system configuration or treadmill operations by implementer.

## Task 2: Installation, documentation and real validation

Root handles this alongside implementation. Verify VirtualGL release SHA256
df3f7788ce41b182a47c0d298e5cd6d2d63579522cb41825970b7726e825485e,
extract into user-owned ~/.local/share/treddy/virtualgl-3.1.5 without overwriting
any existing installation. Create a fresh AVD via SDK avdmanager without --force.
No paid services, global LD_PRELOAD, system drivers or desktop service changes.

Create `docs/local-android-testing.md` with exact setup/build/start/test/view
commands, ownership rules, external evidence location, full-profile visual gate,
safe Ctrl-C recovery and honest benchmark scope. Link it from CLAUDE.md local
development section. Do not edit unrelated documentation or application code.

Validate fresh wrapper start, two successful instrumentation jobs, job locking,
mock-only view, clean job failure behavior and full-profile restart. Capture
commands/results outside git and put measured summary in docs. Verify no physical
device targeted and no repository DB modified. Run unit suite and syntax checks.

## Review and delivery

Review plan/spec before implementation. Review completed runner against spec,
then independently review code quality/lifecycle safety. Fix Important/Critical
findings and rerun affected tests. Commit documentation and push branch; integrate
through normal repository PR workflow. Update the bead with evidence and preserve
unrelated dirty main-worktree files. Do not close until required validation and
delivery complete.
