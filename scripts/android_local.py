#!/usr/bin/env python3
"""Own a dedicated local Android emulator without touching physical devices."""
from __future__ import annotations

import argparse
import fcntl
import math
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from contextlib import ExitStack, contextmanager
from dataclasses import dataclass
from pathlib import Path

AVD = "treddy_local_test"
PACKAGE = "com.precor.treadmill"
TEST_RUNNER = "com.precor.treadmill.test/androidx.test.runner.AndroidJUnitRunner"
CACHE = Path.home() / ".cache" / "treddy-android"
TIMEOUT = 90.0
PROFILES = {"fast": ("1280x800", "160"), "full": ("2560x1600", "320")}


@dataclass(frozen=True)
class Config:
    sdk_root: Path
    vgl_root: Path
    port: int
    profile: str = "fast"


@dataclass
class MockServer:
    host: str
    port: int
    database: Path
    child: subprocess.Popen
    tempdir: tempfile.TemporaryDirectory
    listener: socket.socket
    log: object

    @property
    def url(self):
        return f"http://10.0.2.2:{self.port}"


def config_from_env(port: int, profile: str = "fast") -> Config:
    if port < 5554 or port > 5682 or port % 2:
        raise ValueError("port must be even and between 5554 and 5682")
    if profile not in PROFILES:
        raise ValueError("profile must be fast or full")
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    vgl = os.environ.get("TREDDY_VIRTUALGL_ROOT")
    return Config(Path(sdk) if sdk else Path.home() / "Android" / "Sdk",
                  Path(vgl) if vgl else Path.home() / ".local/share/treddy/virtualgl-3.1.5",
                  port, profile)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def adb_path(config: Config) -> Path:
    return config.sdk_root / "platform-tools" / "adb"


def serial(port: int) -> str:
    return f"emulator-{port}"


def emulator_command(config: Config) -> tuple[dict[str, str], list[str]]:
    display, _density = PROFILES[config.profile]
    emulator = config.sdk_root / "emulator"
    env = {"ANDROID_EGL_ON_EGL": "1", "ANDROID_EMU_HEADLESS": "1",
           "ANDROID_EMULATOR_LAUNCHER_DIR": str(emulator)}
    return env, [str(config.vgl_root / "opt/VirtualGL/bin/vglrun"), "-ld",
                 f"{config.vgl_root}/usr/lib:{emulator}/lib64", "-d", "egl0",
                 str(emulator / "qemu/linux-x86_64/qemu-system-x86_64-headless"),
                 "-avd", AVD, "-no-window", "-no-audio", "-no-snapshot", "-gpu", "host",
                 "-port", str(config.port), "-cores", "4", "-memory", "4096", "-accel", "on",
                 "-skin", display]


@contextmanager
def file_lock(path: Path, timeout: float):
    """Take an on-disk flock; never unlink lockfiles, as that splits domains."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+")
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"timed out waiting for lock {path}")
                time.sleep(min(.05, max(0, deadline - time.monotonic())))
        yield
    finally:
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


def lifecycle_lock(port: int) -> Path:
    return CACHE / f"emulator-{port}.lock"


def avd_owner_lock() -> Path:
    return CACHE / "avd-owner.lock"


def job_lock() -> Path:
    return CACHE / "job.lock"


def stop_owned(child: subprocess.Popen, timeout: float = 10.0) -> None:
    if child.poll() is not None:
        child.wait(timeout=0)
        return
    child.terminate()
    try:
        child.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=timeout)


def check_port_free(port: int) -> None:
    with socket.socket() as probe:
        probe.settimeout(.2)
        if probe.connect_ex(("127.0.0.1", port)) == 0:
            raise RuntimeError(f"emulator port {port} already has an owner")


def check_emulator_ports_free(port: int) -> None:
    check_port_free(port)
    check_port_free(port + 1)


def run(argv: list[str], timeout: float = TIMEOUT, **kwargs) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(argv, check=True, timeout=timeout, **kwargs)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError(f"timed out: {' '.join(argv[:4])}") from error


def adb(adb_executable: str | Path, port: int, *args: str, timeout: float = TIMEOUT,
        input: bytes | None = None) -> subprocess.CompletedProcess:
    return run([str(adb_executable), "-s", serial(port), *args], timeout=timeout,
               input=input, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def avd_name_from_output(output: bytes) -> str:
    lines = [line.strip() for line in output.decode(errors="replace").splitlines() if line.strip()]
    return "\n".join(line for line in lines if line != "OK")


def verify_device(adb_executable: str | Path, port: int, timeout: float = TIMEOUT,
                  owner: subprocess.Popen | None = None) -> None:
    deadline = time.monotonic() + timeout
    while True:
        try:
            name = avd_name_from_output(adb(adb_executable, port, "emu", "avd", "name",
                                             timeout=min(10, max(.1, deadline - time.monotonic()))).stdout)
            break
        except subprocess.CalledProcessError:
            if owner is not None and owner.poll() is not None:
                raise RuntimeError("owned emulator exited before adb became ready")
            if time.monotonic() >= deadline:
                raise TimeoutError("adb did not become ready before deadline")
            time.sleep(.5)
    if name != AVD:
        raise RuntimeError(f"refusing {serial(port)}: expected AVD {AVD!r}, got {name!r}")
    while True:
        if owner is not None and owner.poll() is not None:
            raise RuntimeError("owned emulator exited before boot completed")
        try:
            boot = adb(adb_executable, port, "shell", "getprop", "sys.boot_completed",
                       timeout=min(10, max(.1, deadline - time.monotonic()))).stdout.strip()
        except subprocess.CalledProcessError:
            boot = b""
        if boot == b"1":
            break
        if time.monotonic() >= deadline:
            raise TimeoutError("emulator did not boot before deadline")
        time.sleep(1)
    renderer = adb(adb_executable, port, "shell", "dumpsys", "SurfaceFlinger", timeout=timeout).stdout.decode(errors="replace")
    lowered = renderer.lower()
    if "nvidia" not in lowered or any(bad in lowered for bad in ("llvmpipe", "swiftshader", "software renderer")):
        raise RuntimeError("SurfaceFlinger did not report NVIDIA hardware rendering")


def require_lifecycle_owner(port: int) -> None:
    try:
        with file_lock(lifecycle_lock(port), 0):
            pass
    except TimeoutError:
        return
    raise RuntimeError("no managed start process owns this emulator; refusing external device")


def wait_for_health(server: MockServer, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    url = f"http://{server.host}:{server.port}/api/status"
    while time.monotonic() < deadline:
        if server.child.poll() is not None:
            raise RuntimeError("mock server exited before health check")
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except OSError:
            time.sleep(.1)
    raise TimeoutError("mock server health check timed out")


@contextmanager
def mock_server(root: Path, timeout: float = TIMEOUT):
    temporary = tempfile.TemporaryDirectory(prefix="treddy-android-")
    workdir = Path(temporary.name)
    database = (workdir / "mock.sqlite3").resolve()
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(16)
    port = listener.getsockname()[1]
    env = os.environ.copy()
    env.update({"TREADMILL_MOCK": "1", "TREADMILL_DB": str(database),
                "GEMINI_API_KEY": "local-test-disabled"})
    argv = [sys.executable, "-m", "uvicorn", "server:app", "--fd", str(listener.fileno()),
            "--app-dir", str((root / "python").resolve())]
    log = (workdir / "uvicorn.log").open("wb")
    child = subprocess.Popen(argv, cwd=workdir, env=env, pass_fds=(listener.fileno(),),
                             stdout=log, stderr=subprocess.STDOUT)
    server = MockServer("127.0.0.1", port, database, child, temporary, listener, log)
    try:
        wait_for_health(server, timeout)
        yield server
    finally:
        stop_owned(child)
        listener.close()
        log.close()
        temporary.cleanup()


def varint(value: int) -> bytes:
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def field(tag: int, payload: bytes) -> bytes:
    return varint(tag) + varint(len(payload)) + payload


def preference_entry(key: str, value: str | bool) -> bytes:
    key_bytes = key.encode()
    encoded_value = field(42, value.encode()) if isinstance(value, str) else varint(8) + varint(int(value))
    return field(10, key_bytes) + field(18, encoded_value)


def preferences_bytes(server_url: str) -> bytes:
    values = (("server_url", server_url), ("voice_input_enabled", False),
              ("microphone_permission_requested", True))
    return b"".join(field(10, preference_entry(key, value)) for key, value in values)


def set_preferences(adb_executable: str | Path, port: int, payload: bytes, timeout: float = TIMEOUT) -> None:
    target = "files/datastore/server_prefs.preferences_pb"
    write = f"mkdir -p files/datastore && cat > {target}"
    command = f"run-as {PACKAGE} sh -c {shlex.quote(write)}"
    adb(adb_executable, port, "shell", command, timeout=timeout, input=payload)
    readback = adb(adb_executable, port, "exec-out", "run-as", PACKAGE, "cat", target, timeout=timeout).stdout
    if readback != payload:
        raise RuntimeError("DataStore preferences readback did not match bytes written")


def install_and_prepare(adb_executable: str | Path, port: int, app: Path, test: Path | None,
                        server: MockServer, timeout: float) -> None:
    for apk in (app, test):
        if apk is not None:
            if not apk.is_file():
                raise FileNotFoundError(f"APK not found: {apk}")
            adb(adb_executable, port, "install", "-r", str(apk), timeout=timeout)
    adb(adb_executable, port, "shell", "am", "force-stop", PACKAGE, timeout=timeout)
    set_preferences(adb_executable, port, preferences_bytes(server.url), timeout)


def parse_instrumentation(output: str) -> int:
    failure_summary = (r"^(?:FAILURES!!!|INSTRUMENTATION_(?:STATUS|RESULT): "
                       r"(?:Error|shortMsg|longMsg|stack)=|INSTRUMENTATION_ABORTED|Process crashed)")
    if re.search(failure_summary, output, re.IGNORECASE | re.MULTILINE):
        raise RuntimeError("instrumentation reported failure")
    match = re.search(r"^OK \((\d+) tests?\)$", output, re.MULTILINE)
    if not match or int(match.group(1)) == 0 or not re.search(r"^INSTRUMENTATION_CODE: -1$", output, re.MULTILINE):
        raise RuntimeError("instrumentation did not report successful test completion")
    return int(match.group(1))


def force_stop(adb_executable: str | Path, port: int, timeout: float) -> None:
    adb(adb_executable, port, "shell", "am", "force-stop", PACKAGE, timeout=timeout)


def apply_display_profile(adb_executable: str | Path, config: Config, timeout: float) -> None:
    """Clear persistent geometry overrides, then set and prove the requested density."""
    display, density = PROFILES[config.profile]
    adb(adb_executable, config.port, "shell", "wm", "size", "reset", timeout=timeout)
    adb(adb_executable, config.port, "shell", "wm", "density", density, timeout=timeout)
    size = adb(adb_executable, config.port, "shell", "wm", "size", timeout=timeout).stdout.decode(errors="replace").lower()
    actual_density = adb(adb_executable, config.port, "shell", "wm", "density", timeout=timeout).stdout.decode(errors="replace").lower()
    override = re.search(r"override density:\s*(\d+)", actual_density)
    physical = re.search(r"physical density:\s*(\d+)", actual_density)
    effective_density = override.group(1) if override else physical.group(1) if physical else None
    if "override size" in size or f"physical size: {display}" not in size or effective_density != density:
        raise RuntimeError(f"display profile {config.profile} did not apply cleanly")


def defaults() -> tuple[Path, Path]:
    build = repo_root() / "kotlin/app/build/outputs/apk"
    return build / "uiTest/app-uiTest.apk", build / "androidTest/uiTest/app-uiTest-androidTest.apk"


def execute_test(config: Config, app: Path, test: Path, test_class: str | None, timeout: float) -> int:
    adb_executable = adb_path(config)
    with file_lock(job_lock(), timeout):
        require_lifecycle_owner(config.port)
        verify_device(adb_executable, config.port, timeout)
        with mock_server(repo_root(), timeout) as server:
            try:
                install_and_prepare(adb_executable, config.port, app, test, server, timeout)
                command = ["shell", "am", "instrument", "-w", "-r"]
                if test_class:
                    command += ["-e", "class", test_class]
                result = adb(adb_executable, config.port, *command, TEST_RUNNER, timeout=timeout)
                output = result.stdout.decode(errors="replace")
                print(output, end="" if output.endswith("\n") else "\n")
                return parse_instrumentation(output)
            finally:
                force_stop(adb_executable, config.port, timeout)


def execute_view(config: Config, app: Path, timeout: float) -> None:
    adb_executable = adb_path(config)
    with file_lock(job_lock(), timeout):
        require_lifecycle_owner(config.port)
        verify_device(adb_executable, config.port, timeout)
        with mock_server(repo_root(), timeout) as server:
            try:
                install_and_prepare(adb_executable, config.port, app, None, server, timeout)
                adb(adb_executable, config.port, "shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity", timeout=timeout)
                print(f"view ready: {serial(config.port)} mock={server.url} log={server.log.name}")
                while True:
                    if server.child.poll() is not None:
                        raise RuntimeError("owned mock server exited while view was active")
                    adb(adb_executable, config.port, "get-state", timeout=min(10, timeout))
                    time.sleep(1)
            finally:
                force_stop(adb_executable, config.port, timeout)


def execute_start(config: Config, timeout: float) -> None:
    with file_lock(avd_owner_lock(), timeout), ExitStack() as lifetime:
        child = None
        try:
            with file_lock(job_lock(), timeout):
                lifetime.enter_context(file_lock(lifecycle_lock(config.port), timeout))
                check_emulator_ports_free(config.port)
                env, command = emulator_command(config)
                child = subprocess.Popen(command, env=os.environ | env)
                verify_device(adb_path(config), config.port, timeout, owner=child)
                apply_display_profile(adb_path(config), config, timeout)
                print(f"emulator ready: {serial(config.port)} profile={config.profile}")
            while child.poll() is None:
                time.sleep(.5)
        finally:
            if child is not None:
                stop_owned(child)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    start = sub.add_parser("start")
    start.add_argument("--port", type=int, default=5582)
    start.add_argument("--profile", choices=PROFILES, default="fast")
    for name in ("test", "view"):
        command = sub.add_parser(name)
        command.add_argument("--port", type=int, default=5582)
        command.add_argument("--app-apk", type=Path)
        command.add_argument("--timeout", type=float, default=TIMEOUT)
        if name == "test":
            command.add_argument("--test-apk", type=Path)
            command.add_argument("--class", dest="test_class")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    old_term = signal.getsignal(signal.SIGTERM)
    def interrupt(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    try:
        if hasattr(args, "timeout") and (not math.isfinite(args.timeout) or args.timeout <= 0):
            parser().error("--timeout must be a positive finite number")
        config = config_from_env(args.port, getattr(args, "profile", "fast"))
        if args.command == "start":
            execute_start(config, TIMEOUT)
            return 0
        default_app, default_test = defaults()
        if args.command == "test":
            count = execute_test(config, args.app_apk or default_app, args.test_apk or default_test,
                                 args.test_class, args.timeout)
            print(f"instrumentation passed: {count} tests")
        else:
            execute_view(config, args.app_apk or default_app, args.timeout)
        return 0
    except KeyboardInterrupt:
        return 130
    finally:
        signal.signal(signal.SIGTERM, old_term)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, TimeoutError, FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"android_local: {error}", file=sys.stderr)
        raise SystemExit(2)
