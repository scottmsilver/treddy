import os
import select
import contextlib
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import android_local as runner


class AndroidLocalTests(unittest.TestCase):
    def test_configuration_uses_environment_then_home_fallback(self):
        with mock.patch.dict(os.environ, {"ANDROID_SDK_ROOT": "/sdk", "TREDDY_VIRTUALGL_ROOT": "/vgl"}, clear=True):
            config = runner.config_from_env(5582)
        self.assertEqual(Path("/sdk"), config.sdk_root)
        self.assertEqual(Path("/vgl"), config.vgl_root)
        with self.assertRaisesRegex(ValueError, "even.*5554.*5682"):
            runner.config_from_env(5555)

    def test_verified_emulator_argv_is_exact_and_has_selected_profile(self):
        config = runner.Config(Path("/sdk"), Path("/vgl"), 5582, "fast")
        env, argv = runner.emulator_command(config)
        self.assertEqual(env["ANDROID_EGL_ON_EGL"], "1")
        self.assertEqual(env["ANDROID_EMU_HEADLESS"], "1")
        self.assertEqual(env["ANDROID_EMULATOR_LAUNCHER_DIR"], "/sdk/emulator")
        self.assertEqual(argv[:7], [
            "/vgl/opt/VirtualGL/bin/vglrun", "-ld", "/vgl/usr/lib:/sdk/emulator/lib64",
            "-d", "egl0", "/sdk/emulator/qemu/linux-x86_64/qemu-system-x86_64-headless",
            "-avd",
        ])
        self.assertEqual(argv[7:], ["treddy_local_test", "-no-window", "-no-audio", "-no-snapshot",
                                   "-gpu", "host", "-port", "5582", "-cores", "4", "-memory", "4096",
                                   "-accel", "on", "-skin", "1280x800"])

    def test_full_profile_command_uses_full_display(self):
        _, argv = runner.emulator_command(runner.Config(Path("/sdk"), Path("/vgl"), 5582, "full"))
        self.assertEqual(argv[-2:], ["-skin", "2560x1600"])

    def test_cross_process_lock_excludes_second_holder(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "lock"
            code = ("import sys,time;sys.path.insert(0, sys.argv[1]);import android_local as r\n"
                    "with r.file_lock(r.Path(sys.argv[2]), 2):\n print('ready', flush=True); time.sleep(.8)\n")
            child = subprocess.Popen([sys.executable, "-c", code, str(SCRIPTS), str(path)],
                                     stdout=subprocess.PIPE, text=True)
            ready, _, _ = select.select([child.stdout], [], [], 2)
            self.assertTrue(ready, "child did not acquire lock before deadline")
            self.assertEqual(child.stdout.readline().strip(), "ready")
            with self.assertRaisesRegex(TimeoutError, "lock"):
                with runner.file_lock(path, .1):
                    pass
            child.wait(timeout=3)
            child.stdout.close()
            with runner.file_lock(path, .1):
                pass

    def test_owned_child_is_terminated_and_reaped(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        runner.stop_owned(child, timeout=1)
        self.assertIsNotNone(child.returncode)

    def test_mock_server_reserves_socket_and_cleans_child(self):
        created = []

        class FakeChild:
            returncode = None
            def poll(self): return None
            def terminate(self): self.returncode = 0
            def wait(self, timeout=None): return 0

        def fake_popen(argv, **kwargs):
            created.append((argv, kwargs))
            return FakeChild()

        with tempfile.TemporaryDirectory() as directory, mock.patch.object(runner.subprocess, "Popen", fake_popen), \
                mock.patch.object(runner, "wait_for_health"):
            with runner.mock_server(Path(directory), timeout=1) as server:
                self.assertEqual(server.host, "127.0.0.1")
            self.assertTrue(server.database.is_absolute())
            self.assertTrue(created[0][1]["pass_fds"])
            self.assertIn("--fd", created[0][0])
            self.assertNotEqual(Path(created[0][1]["cwd"]).parent, Path(directory))
            self.assertEqual(created[0][1]["stderr"], subprocess.STDOUT)
            self.assertEqual(created[0][1]["env"]["TREADMILL_MOCK"], "1")
            self.assertEqual(created[0][1]["env"]["GEMINI_API_KEY"], "local-test-disabled")

    def test_preferences_are_independently_decodable(self):
        encoded = runner.preferences_bytes("http://10.0.2.2:4567")
        self.assertEqual(decode_preferences(encoded), {
            "server_url": "http://10.0.2.2:4567",
            "voice_input_enabled": False,
            "microphone_permission_requested": True,
        })

    def test_instrumentation_requires_ok_count_and_minus_one_code(self):
        good = "INSTRUMENTATION_STATUS: numtests=2\nOK (2 tests)\nINSTRUMENTATION_CODE: -1\n"
        self.assertEqual(runner.parse_instrumentation(good), 2)
        for bad in ("OK (2 tests)\nINSTRUMENTATION_CODE: 0", "FAILURES!!!\nINSTRUMENTATION_CODE: -1",
                    "INSTRUMENTATION_CODE: -1", "OK (0 tests)\nINSTRUMENTATION_CODE: -1"):
            with self.assertRaisesRegex(RuntimeError, "instrumentation"):
                runner.parse_instrumentation(bad)

    def test_start_checks_console_and_adb_ports_before_launch(self):
        with mock.patch.object(runner, "check_port_free") as check:
            runner.check_emulator_ports_free(5582)
        self.assertEqual([call.args[0] for call in check.call_args_list], [5582, 5583])

    def test_start_holds_job_lock_before_boot_verification_and_profile_mutation(self):
        active = []
        @contextlib.contextmanager
        def lock(path, _timeout):
            active.append(path)
            try:
                yield
            finally:
                active.pop()
        child = mock.Mock()
        child.poll.return_value = 0
        config = runner.Config(Path("/sdk"), Path("/vgl"), 5582)
        def verify(*_args, **_kwargs):
            self.assertIn(runner.job_lock(), active)
        with mock.patch.object(runner, "file_lock", side_effect=lock), \
                mock.patch.object(runner, "check_emulator_ports_free"), \
                mock.patch.object(runner, "emulator_command", return_value=({}, ["qemu"])), \
                mock.patch.object(runner.subprocess, "Popen", return_value=child), \
                mock.patch.object(runner, "verify_device", side_effect=verify), \
                mock.patch.object(runner, "apply_display_profile"), \
                mock.patch.object(runner, "stop_owned"):
            runner.execute_start(config, 1)

    def test_start_releases_job_lock_while_owned_emulator_stays_warm(self):
        active = []
        @contextlib.contextmanager
        def lock(path, _timeout):
            active.append(path)
            try:
                yield
            finally:
                active.pop()
        child = mock.Mock()
        child.poll.side_effect = [None, 0]
        config = runner.Config(Path("/sdk"), Path("/vgl"), 5582)
        def warm_sleep(_seconds):
            self.assertNotIn(runner.job_lock(), active)
        with mock.patch.object(runner, "file_lock", side_effect=lock), \
                mock.patch.object(runner, "check_emulator_ports_free"), \
                mock.patch.object(runner, "emulator_command", return_value=({}, ["qemu"])), \
                mock.patch.object(runner.subprocess, "Popen", return_value=child), \
                mock.patch.object(runner, "verify_device"), \
                mock.patch.object(runner, "apply_display_profile"), \
                mock.patch.object(runner, "stop_owned"), \
                mock.patch.object(runner.time, "sleep", side_effect=warm_sleep):
            runner.execute_start(config, 1)

    def test_successful_test_still_force_stops_and_reaps_mock_server(self):
        server = mock.Mock()
        server.url = "http://10.0.2.2:1234"
        server.child = mock.Mock()
        result = mock.Mock(stdout=b"OK (2 tests)\nINSTRUMENTATION_CODE: -1\n")
        @contextlib.contextmanager
        def owned_server(*_args):
            try:
                yield server
            finally:
                runner.stop_owned(server.child)
        with tempfile.TemporaryDirectory() as directory:
            app, test = Path(directory) / "app.apk", Path(directory) / "test.apk"
            app.touch()
            test.touch()
            with mock.patch.object(runner, "file_lock", return_value=contextlib.nullcontext()), \
                    mock.patch.object(runner, "require_lifecycle_owner"), \
                    mock.patch.object(runner, "verify_device"), \
                    mock.patch.object(runner, "mock_server", side_effect=owned_server), \
                    mock.patch.object(runner, "install_and_prepare"), \
                    mock.patch.object(runner, "adb", return_value=result) as adb, \
                    mock.patch.object(runner, "stop_owned") as stop:
                count = runner.execute_test(runner.Config(Path("/sdk"), Path("/vgl"), 5582), app, test, None, 1)
        self.assertEqual(count, 2)
        self.assertTrue(stop.called)
        self.assertTrue(any(call.args[2:5] == ("shell", "am", "force-stop") for call in adb.call_args_list))

    def test_test_timeout_force_stops_before_owned_server_context_reaps(self):
        events = []
        server = mock.Mock(url="http://10.0.2.2:1234")
        server.child = mock.Mock()
        @contextlib.contextmanager
        def owned_server(*_args):
            try:
                yield server
            finally:
                events.append("reap-server")
        def fake_adb(_adb, _port, *args, **_kwargs):
            if args[:3] == ("shell", "am", "force-stop"):
                events.append("force-stop")
                return mock.Mock(stdout=b"")
            raise TimeoutError("instrumentation timed out")
        with tempfile.TemporaryDirectory() as directory:
            app, test = Path(directory) / "app.apk", Path(directory) / "test.apk"
            app.touch(); test.touch()
            with mock.patch.object(runner, "file_lock", return_value=contextlib.nullcontext()), \
                    mock.patch.object(runner, "require_lifecycle_owner"), \
                    mock.patch.object(runner, "verify_device"), \
                    mock.patch.object(runner, "mock_server", side_effect=owned_server), \
                    mock.patch.object(runner, "install_and_prepare"), \
                    mock.patch.object(runner, "adb", side_effect=fake_adb):
                with self.assertRaisesRegex(TimeoutError, "instrumentation"):
                    runner.execute_test(runner.Config(Path("/sdk"), Path("/vgl"), 5582), app, test, None, 1)
        self.assertEqual(events, ["force-stop", "reap-server"])

    def test_view_device_timeout_force_stops_before_owned_server_context_reaps(self):
        events = []
        server = mock.Mock(url="http://10.0.2.2:1234")
        server.child.poll.return_value = None
        server.log.name = "/tmp/uvicorn.log"
        @contextlib.contextmanager
        def owned_server(*_args):
            try:
                yield server
            finally:
                events.append("reap-server")
        def fake_adb(_adb, _port, *args, **_kwargs):
            if args[:3] == ("shell", "am", "force-stop"):
                events.append("force-stop")
                return mock.Mock(stdout=b"")
            if args == ("get-state",):
                raise TimeoutError("device died")
            return mock.Mock(stdout=b"")
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "app.apk"; app.touch()
            with mock.patch.object(runner, "file_lock", return_value=contextlib.nullcontext()), \
                    mock.patch.object(runner, "require_lifecycle_owner"), \
                    mock.patch.object(runner, "verify_device"), \
                    mock.patch.object(runner, "mock_server", side_effect=owned_server), \
                    mock.patch.object(runner, "install_and_prepare"), \
                    mock.patch.object(runner, "adb", side_effect=fake_adb):
                with self.assertRaisesRegex(TimeoutError, "device died"):
                    runner.execute_view(runner.Config(Path("/sdk"), Path("/vgl"), 5582), app, 1)
        self.assertEqual(events, ["force-stop", "reap-server"])

    def test_avd_protocol_trailer_is_not_part_of_the_avd_name(self):
        self.assertEqual(runner.avd_name_from_output(b"treddy_local_test\nOK\r\n"), "treddy_local_test")

    def test_global_avd_owner_lock_is_shared_across_ports(self):
        self.assertEqual(runner.avd_owner_lock(), runner.CACHE / "avd-owner.lock")
        self.assertNotEqual(runner.lifecycle_lock(5582), runner.lifecycle_lock(5584))

    def test_preferences_write_uses_one_quoted_remote_shell_command(self):
        payload = b"prefs"
        readback = mock.Mock(stdout=payload)
        with mock.patch.object(runner, "adb", return_value=readback) as adb:
            runner.set_preferences("adb", 5582, payload)
        write = adb.call_args_list[0].args
        self.assertEqual(write[2], "shell")
        self.assertEqual(len(write[3:]), 1)
        self.assertIn("run-as com.precor.treadmill sh -c", write[3])
        self.assertIn("cat > files/datastore/server_prefs.preferences_pb", write[3])

    def test_preferences_readback_mismatch_is_rejected(self):
        with mock.patch.object(runner, "adb", side_effect=[mock.Mock(stdout=b""), mock.Mock(stdout=b"wrong")]):
            with self.assertRaisesRegex(RuntimeError, "readback"):
                runner.set_preferences("adb", 5582, b"expected")

    def test_adb_always_uses_exact_emulator_serial_argv(self):
        completed = mock.Mock()
        with mock.patch.object(runner.subprocess, "run", return_value=completed) as run:
            self.assertIs(runner.adb("/sdk/adb", 5582, "shell", "getprop", "x"), completed)
        self.assertEqual(run.call_args.args[0], ["/sdk/adb", "-s", "emulator-5582", "shell", "getprop", "x"])

    def test_verify_device_rejects_wrong_avd_and_software_renderer(self):
        with mock.patch.object(runner, "adb", return_value=mock.Mock(stdout=b"someone_else\nOK\n")):
            with self.assertRaisesRegex(RuntimeError, "expected AVD"):
                runner.verify_device("adb", 5582, .1)
        responses = [mock.Mock(stdout=b"treddy_local_test\nOK\n"), mock.Mock(stdout=b"1"),
                     mock.Mock(stdout=b"GLES: llvmpipe")]
        with mock.patch.object(runner, "adb", side_effect=responses):
            with self.assertRaisesRegex(RuntimeError, "hardware rendering"):
                runner.verify_device("adb", 5582, .1)

    def test_main_converts_sigterm_interrupt_to_clean_exit_after_job_finally(self):
        with mock.patch.object(runner, "execute_test", side_effect=KeyboardInterrupt), \
                mock.patch.object(runner.signal, "signal", return_value=runner.signal.SIG_DFL) as signal:
            self.assertEqual(runner.main(["test", "--app-apk", "/tmp/app.apk", "--test-apk", "/tmp/test.apk"]), 130)
        self.assertEqual(signal.call_args_list[0].args[0], runner.signal.SIGTERM)
        self.assertEqual(signal.call_args_list[-1].args, (runner.signal.SIGTERM, runner.signal.SIG_DFL))

    def test_display_profile_resets_size_sets_density_and_verifies_readback(self):
        responses = [mock.Mock(stdout=b""), mock.Mock(stdout=b""),
                     mock.Mock(stdout=b"Physical size: 1280x800\n"),
                     mock.Mock(stdout=b"Physical density: 320\nOverride density: 160\n")]
        with mock.patch.object(runner, "adb", side_effect=responses) as adb:
            runner.apply_display_profile("adb", runner.Config(Path("/sdk"), Path("/vgl"), 5582, "fast"), 1)
        self.assertEqual([call.args[2:] for call in adb.call_args_list], [
            ("shell", "wm", "size", "reset"), ("shell", "wm", "density", "160"),
            ("shell", "wm", "size"), ("shell", "wm", "density"),
        ])

    def test_full_display_profile_accepts_matching_physical_density_without_override(self):
        responses = [mock.Mock(stdout=b""), mock.Mock(stdout=b""),
                     mock.Mock(stdout=b"Physical size: 2560x1600\n"),
                     mock.Mock(stdout=b"Physical density: 320\n")]
        with mock.patch.object(runner, "adb", side_effect=responses):
            runner.apply_display_profile("adb", runner.Config(Path("/sdk"), Path("/vgl"), 5582, "full"), 1)

    def test_display_profile_rejects_wrong_physical_size(self):
        responses = [mock.Mock(stdout=b""), mock.Mock(stdout=b""),
                     mock.Mock(stdout=b"Physical size: 1920x1080\n"),
                     mock.Mock(stdout=b"Physical density: 320\nOverride density: 160\n")]
        with mock.patch.object(runner, "adb", side_effect=responses):
            with self.assertRaisesRegex(RuntimeError, "display profile"):
                runner.apply_display_profile("adb", runner.Config(Path("/sdk"), Path("/vgl"), 5582, "fast"), 1)


def read_varint(data, index):
    value = shift = 0
    while True:
        byte = data[index]
        index += 1
        value |= (byte & 127) << shift
        if not byte & 128:
            return value, index
        shift += 7


def decode_preferences(data):
    result, index = {}, 0
    while index < len(data):
        self_field, index = read_varint(data, index)
        assert self_field == 10
        length, index = read_varint(data, index)
        entry, index = data[index:index + length], index + length
        key_len = entry[1]
        key = entry[2:2 + key_len].decode()
        value_index = 2 + key_len
        assert entry[value_index] == 18
        value_len = entry[value_index + 1]
        value = entry[value_index + 2:value_index + 2 + value_len]
        if value[0] == 42:
            result[key] = value[2:].decode()
        else:
            assert value[:2] in (b"\x08\x00", b"\x08\x01")
            result[key] = bool(value[1])
    return result


if __name__ == "__main__":
    unittest.main()
