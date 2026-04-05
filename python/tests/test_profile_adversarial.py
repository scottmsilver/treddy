"""Adversarial tests for multi-user profile isolation and edge cases."""

from unittest.mock import MagicMock

import pytest
from starlette.testclient import TestClient


def _prog(name="Test", intervals=None):
    if intervals is None:
        intervals = [{"name": "Warmup", "duration": 60, "speed": 3.0, "incline": 0}]
    return {"name": name, "intervals": intervals}


@pytest.fixture
def mock_client():
    client = MagicMock()
    client.set_speed = MagicMock()
    client.set_incline = MagicMock()
    client.set_emulate = MagicMock()
    client.set_proxy = MagicMock()
    client.connect = MagicMock()
    client.close = MagicMock()
    client.on_message = None
    return client


@pytest.fixture
def test_app(mock_client):
    """Create test app with two profiles for adversarial testing."""
    import server
    from db import TreadmillDB
    from workout_db import WorkoutDB
    from workout_session import WorkoutSession

    orig_client = getattr(server, "client", None)
    orig_sess = getattr(server, "sess", None)
    orig_loop = getattr(server, "loop", None)
    orig_queue = getattr(server, "msg_queue", None)
    orig_db = getattr(server, "db", None)
    orig_workout_db = getattr(server, "workout_db", None)
    orig_guest_mode = getattr(server, "_guest_mode", False)

    test_db = TreadmillDB(":memory:")
    alice = test_db.create_profile("Alice", weight_lbs=140)
    bob = test_db.create_profile("Bob", weight_lbs=180)
    test_db.set_active_profile_id(alice["id"])

    server.db = test_db
    server._guest_mode = False
    server.client = mock_client
    server.sess = WorkoutSession()
    server.loop = MagicMock()
    server.msg_queue = MagicMock()
    server.msg_queue.put_nowait = MagicMock()

    server.workout_db = WorkoutDB(
        history_loader=lambda: test_db.get_program_history(server._active_profile_id()),
        workouts_loader=lambda: test_db.get_saved_workouts(server._active_profile_id()),
        runs_loader=lambda: test_db.get_runs(server._active_profile_id()),
        fingerprint_fn=server._program_fingerprint,
    )

    server.state["proxy"] = True
    server.state["emulate"] = False
    server.state["emu_speed"] = 0
    server.state["emu_incline"] = 0
    server.state["treadmill_connected"] = True
    server.latest["last_motor"] = {}
    server.latest["last_console"] = {}

    server.app.router.lifespan_context = None
    tc = TestClient(server.app, raise_server_exceptions=True)
    yield tc, server, mock_client, alice, bob

    test_db.close()
    server.client = orig_client
    server.sess = orig_sess
    server.loop = orig_loop
    server.msg_queue = orig_queue
    server.db = orig_db
    server.workout_db = orig_workout_db
    server._guest_mode = orig_guest_mode


class TestCrossProfileBlocked:
    """Cross-profile access must be blocked."""

    def test_cross_profile_history_load_blocked(self, test_app):
        """Cannot load history entries from another profile."""
        client, server, _, alice, bob = test_app
        # Add history as Bob
        server.db.set_active_profile_id(bob["id"])
        entry = server.db.add_to_history(bob["id"], _prog("Bob Workout"))
        # Switch back to Alice
        server.db.set_active_profile_id(alice["id"])
        resp = client.post(f"/api/programs/history/{entry['id']}/load")
        assert resp.status_code == 404

    def test_cross_profile_history_resume_blocked(self, test_app):
        """Cannot resume history entries from another profile."""
        client, server, _, alice, bob = test_app
        entry = server.db.add_to_history(bob["id"], _prog("Bob Workout"))
        resp = client.post(f"/api/programs/history/{entry['id']}/resume")
        assert resp.status_code == 404

    def test_cross_profile_save_from_history_blocked(self, test_app):
        """Cannot save a workout from another profile's history."""
        client, server, _, alice, bob = test_app
        entry = server.db.add_to_history(bob["id"], _prog("Bob Workout"))
        resp = client.post("/api/workouts", json={"history_id": entry["id"]})
        assert resp.status_code == 404

    def test_cross_profile_workout_rename_blocked(self, test_app):
        """Cannot rename a workout belonging to another profile."""
        client, server, _, alice, bob = test_app
        w = server.db.save_workout(bob["id"], _prog("Bob Fav"))
        resp = client.put(f"/api/workouts/{w['id']}", json={"name": "Stolen"})
        assert resp.status_code == 404

    def test_cross_profile_workout_delete_blocked(self, test_app):
        """Cannot delete a workout belonging to another profile."""
        client, server, _, alice, bob = test_app
        w = server.db.save_workout(bob["id"], _prog("Bob Fav"))
        resp = client.delete(f"/api/workouts/{w['id']}")
        assert resp.status_code == 404
        # Verify it still exists
        assert server.db.get_saved_workout(w["id"]) is not None


class TestGuestMode:
    """Guest mode behavior."""

    def test_guest_cannot_save_favorites(self, test_app):
        """In guest mode, saving a workout returns an error."""
        client, server, _, alice, bob = test_app
        server._guest_mode = True
        resp = client.post(
            "/api/workouts",
            json={"program": _prog("Guest Workout"), "source": "generated"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is False
        assert "profile" in data["error"].lower() or "create" in data["error"].lower()

    def test_guest_convert_transfers_workouts(self, test_app):
        """Converting guest transfers saved workouts to the new profile."""
        client, server, _, alice, bob = test_app
        from db import GUEST_PROFILE_ID

        # Add data as guest
        server.db.save_workout(GUEST_PROFILE_ID, _prog("Guest Fav"))
        server.db.add_to_history(GUEST_PROFILE_ID, _prog("Guest Hist"))
        # Convert
        server.db.set_active_profile_id(alice["id"])
        resp = client.post("/api/profile/guest/convert")
        assert resp.status_code == 200
        assert resp.json()["ok"] is True
        # Alice now has the data
        assert len(server.db.get_saved_workouts(alice["id"])) == 1
        assert len(server.db.get_program_history(alice["id"])) == 1
        # Guest has nothing
        assert len(server.db.get_saved_workouts(GUEST_PROFILE_ID)) == 0


class TestValidation:
    """Input validation edge cases."""

    def test_blank_name_rejected(self, test_app):
        """Creating a profile with blank name is rejected."""
        client, server, _, alice, bob = test_app
        resp = client.post("/api/profiles", json={"name": ""})
        assert resp.status_code == 422

    def test_negative_weight_rejected(self, test_app):
        """Creating a profile with negative weight is rejected."""
        client, server, _, alice, bob = test_app
        resp = client.post("/api/profiles", json={"name": "Test", "weight_lbs": -10})
        assert resp.status_code == 422

    def test_cascade_deletes_program_history(self, test_app):
        """Deleting a profile cascades to its program history."""
        client, server, _, alice, bob = test_app
        server.db.add_to_history(bob["id"], _prog("Bob Prog"))
        assert len(server.db.get_program_history(bob["id"])) == 1
        server.db.delete_profile(bob["id"])
        assert len(server.db.get_program_history(bob["id"])) == 0


class TestProfileAPI:
    """Profile management API endpoints."""

    def test_list_profiles(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.get("/api/profiles")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2
        names = {p["name"] for p in data}
        assert "Alice" in names
        assert "Bob" in names

    def test_create_profile(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.post("/api/profiles", json={"name": "Charlie", "weight_lbs": 170})
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["profile"]["name"] == "Charlie"
        assert data["profile"]["weight_lbs"] == 170

    def test_select_profile(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.post("/api/profile/select", json={"id": bob["id"]})
        assert resp.status_code == 200
        assert resp.json()["ok"] is True
        assert server._active_profile_id() == bob["id"]

    def test_select_profile_blocked_during_session(self, test_app):
        client, server, _, alice, bob = test_app
        server.sess.start()
        resp = client.post("/api/profile/select", json={"id": bob["id"]})
        assert resp.status_code == 409

    def test_guest_mode_blocked_during_session(self, test_app):
        client, server, _, alice, bob = test_app
        server.sess.start()
        resp = client.post("/api/profile/guest")
        assert resp.status_code == 409

    def test_status_includes_active_profile(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.get("/api/status")
        assert resp.status_code == 200
        data = resp.json()
        assert "active_profile" in data
        assert data["active_profile"]["name"] == "Alice"
        assert "guest_mode" in data

    def test_data_isolation_after_switch(self, test_app):
        """After switching profiles, data should reflect the new profile."""
        client, server, _, alice, bob = test_app
        # Add history to Alice
        server._add_to_history(_prog("Alice Workout"))
        resp = client.get("/api/programs/history")
        assert len(resp.json()) == 1

        # Switch to Bob
        client.post("/api/profile/select", json={"id": bob["id"]})
        resp = client.get("/api/programs/history")
        assert len(resp.json()) == 0  # Bob has no history

    def test_api_user_proxies_to_active_profile(self, test_app):
        """GET/PUT /api/user should proxy to the active profile."""
        client, server, _, alice, bob = test_app
        resp = client.get("/api/user")
        assert resp.json()["weight_lbs"] == 140  # Alice's weight
        resp = client.put("/api/user", json={"weight_lbs": 145})
        assert resp.json()["weight_lbs"] == 145
        # Verify it persisted in db
        p = server.db.get_profile(alice["id"])
        assert p["weight_lbs"] == 145

    def test_delete_active_profile_blocked(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.delete(f"/api/profiles/{alice['id']}")
        assert resp.status_code == 409

    def test_delete_non_active_profile(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.delete(f"/api/profiles/{bob['id']}")
        assert resp.status_code == 200
        assert resp.json()["ok"] is True

    def test_active_profile_endpoint(self, test_app):
        client, server, _, alice, bob = test_app
        resp = client.get("/api/profile/active")
        assert resp.status_code == 200
        data = resp.json()
        assert data["profile"]["name"] == "Alice"
        assert data["guest_mode"] is False

    def test_update_profile_name(self, test_app):
        """PUT /api/profiles/{id} with name should rename and update initials."""
        client, server, _, alice, bob = test_app
        resp = client.put(f"/api/profiles/{alice['id']}", json={"name": "Alice M"})
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["profile"]["name"] == "Alice M"
        assert data["profile"]["initials"] == "A"
        # Verify persisted
        p = server.db.get_profile(alice["id"])
        assert p["name"] == "Alice M"

    def test_update_profile_color(self, test_app):
        """PUT /api/profiles/{id} with color should update color."""
        client, server, _, alice, bob = test_app
        resp = client.put(f"/api/profiles/{alice['id']}", json={"color": "#c9b8b0"})
        assert resp.status_code == 200
        data = resp.json()
        assert data["profile"]["color"] == "#c9b8b0"
        # Verify persisted
        p = server.db.get_profile(alice["id"])
        assert p["color"] == "#c9b8b0"

    def test_update_profile_name_and_color(self, test_app):
        """PUT /api/profiles/{id} with both name and color."""
        client, server, _, alice, bob = test_app
        resp = client.put(f"/api/profiles/{alice['id']}", json={"name": "Renamed", "color": "#b0c9b8"})
        assert resp.status_code == 200
        p = resp.json()["profile"]
        assert p["name"] == "Renamed"
        assert p["color"] == "#b0c9b8"
        assert p["initials"] == "R"
