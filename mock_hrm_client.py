#!/usr/bin/env python3
"""
Mock HrmClient for UI development without a Bluetooth HRM.

Provides the same interface as HrmClient but simulates heart rate data.
HR scales with treadmill speed when available.

Set TREADMILL_MOCK=1 to activate (used alongside MockTreadmillClient).
"""

import logging
import random
import threading
import time

log = logging.getLogger("mock_hrm")


class MockHrmClient:
    def __init__(self, sock_path=None):
        self.sock_path = sock_path  # unused, for interface compat
        self._connected = False
        self._running = False
        self._broadcast_thread = None
        self._device_connected = False
        self._device_name = ""
        self._device_address = ""
        self._base_hr = 70  # resting HR

        # Callbacks (same as HrmClient)
        self.on_message = None
        self.on_disconnect = None
        self.on_reconnect = None

    @property
    def connected(self):
        return self._connected

    def connect(self):
        """Simulate successful daemon connection."""
        self._running = True
        self._connected = True
        log.info("Mock HRM client connected")
        self._broadcast_thread = threading.Thread(target=self._broadcast_loop, daemon=True)
        self._broadcast_thread.start()

    def ensure_connecting(self):
        """Start connection (mock always succeeds)."""
        self.connect()

    def close(self):
        """Stop mock broadcasts."""
        self._running = False
        self._connected = False
        if self._broadcast_thread:
            self._broadcast_thread.join(timeout=2.0)

    def select_device(self, address):
        """Simulate connecting to a HRM device."""
        self._device_connected = True
        self._device_address = address
        self._device_name = "Mock HRM"
        log.info(f"Mock HRM: selected device {address}")

    def forget_device(self):
        """Simulate forgetting saved device."""
        self._device_connected = False
        self._device_name = ""
        self._device_address = ""

    def scan(self):
        """Simulate BLE scan with fake devices."""
        if self.on_message:
            try:
                self.on_message(
                    {
                        "type": "scan_result",
                        "devices": [
                            {"address": "AA:BB:CC:DD:EE:01", "name": "Mock HRM Band"},
                            {"address": "AA:BB:CC:DD:EE:02", "name": "Mock Chest Strap"},
                        ],
                    }
                )
            except Exception:
                pass

    def disconnect_device(self):
        """Simulate disconnecting device."""
        self._device_connected = False

    def _broadcast_loop(self):
        """1Hz heart rate broadcasts."""
        while self._running:
            time.sleep(1.0)
            if not self._running or not self._connected:
                continue
            if not self.on_message:
                continue

            # Simulate HR with some noise
            hr = self._base_hr + random.randint(-2, 2)
            hr = max(50, min(200, hr))

            try:
                self.on_message(
                    {
                        "type": "hr",
                        "bpm": hr,
                        "connected": self._device_connected,
                        "device": self._device_name,
                    }
                )
            except Exception:
                pass
