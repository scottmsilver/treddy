#!/usr/bin/env python3
"""
Mock TreadmillClient for UI development without a Pi.

Provides the same interface as TreadmillClient but simulates all treadmill
behavior in-process. Set TREADMILL_MOCK=1 to activate.

Behavior:
- connect() succeeds immediately
- set_speed/set_incline update internal state and fire on_message callbacks
- Periodic 1Hz status broadcasts (like real daemon)
- Starts in proxy mode, auto-switches to emulate on first command
"""

import json
import logging
import threading
import time

from treadmill_client import MAX_INCLINE, MAX_SPEED_TENTHS

log = logging.getLogger("mock_treadmill")


class MockTreadmillClient:
    def __init__(self, sock_path=None):
        self.sock_path = sock_path  # unused, for interface compat
        self._connected = False
        self._running = False
        self._lock = threading.Lock()
        self._broadcast_thread = None
        self._heartbeat_thread = None
        self._heartbeat_running = False

        # Internal treadmill state
        self._proxy = True
        self._emulate = False
        self._emu_speed = 0  # tenths of mph
        self._emu_incline = 0  # half-percent units
        self._bus_speed = 0  # tenths of mph (simulated motor readback)
        self._bus_incline = 0  # half-percent units

        # Callbacks (same as TreadmillClient)
        self.on_message = None
        self.on_disconnect = None
        self.on_reconnect = None

    @property
    def connected(self):
        return self._connected

    def connect(self):
        """Simulate successful connection."""
        self._running = True
        self._connected = True
        log.info("Mock treadmill connected")
        # Start 1Hz status broadcasts
        self._broadcast_thread = threading.Thread(target=self._broadcast_loop, daemon=True)
        self._broadcast_thread.start()

    def start_heartbeat(self, interval=1.0):
        """No-op for mock — no watchdog to keep alive."""
        self._heartbeat_running = True

    def stop_heartbeat(self):
        """No-op for mock."""
        self._heartbeat_running = False

    def close(self):
        """Stop mock broadcasts."""
        self._running = False
        self._heartbeat_running = False
        self._connected = False
        if self._broadcast_thread:
            self._broadcast_thread.join(timeout=2.0)

    def heartbeat(self):
        """No-op for mock."""
        pass

    def set_proxy(self, enabled):
        with self._lock:
            self._proxy = enabled
            if enabled:
                self._emulate = False
        self._fire_status()

    def set_emulate(self, enabled):
        with self._lock:
            self._emulate = enabled
            if enabled:
                self._proxy = False
                # Zero speed on emulate start (matches real C++ behavior)
                self._emu_speed = 0
                self._emu_incline = 0
        self._fire_status()

    def set_speed(self, mph):
        """Set emulation speed in mph (float)."""
        tenths = max(0, min(int(round(mph * 10)), MAX_SPEED_TENTHS))
        with self._lock:
            if not self._emulate:
                # Auto-switch to emulate on first command
                self._proxy = False
                self._emulate = True
            self._emu_speed = tenths
            # Simulate motor catching up instantly in mock
            self._bus_speed = tenths
        self._fire_status()

    def set_incline(self, value):
        """Set emulation incline (float, 0.5 steps)."""
        half_pct = max(0, min(int(round(value * 2)), MAX_INCLINE * 2))
        with self._lock:
            if not self._emulate:
                self._proxy = False
                self._emulate = True
            self._emu_incline = half_pct
            self._bus_incline = half_pct
        self._fire_status()

    def request_status(self):
        """Fire a status event immediately."""
        self._fire_status()

    def quit_server(self):
        """No-op for mock."""
        pass

    def _fire_status(self):
        """Send a status event to on_message callback."""
        if not self.on_message:
            return
        with self._lock:
            msg = {
                "type": "status",
                "proxy": self._proxy,
                "emulate": self._emulate,
                "emu_speed": self._emu_speed,
                "emu_incline": self._emu_incline,
                "bus_speed": self._bus_speed if self._proxy else -1,
                "bus_incline": self._bus_incline if self._proxy else -1,
            }
        try:
            self.on_message(msg)
        except Exception:
            pass

    def _broadcast_loop(self):
        """1Hz status broadcasts (matches real daemon behavior)."""
        while self._running:
            time.sleep(1.0)
            if self._running and self._connected:
                self._fire_status()
