"""Tests for TreadmillDB — SQLite persistence layer for multi-user profiles."""

import json
import os
import tempfile

import pytest
from db import GUEST_PROFILE_ID, MAX_CHAT, MAX_HISTORY, TreadmillDB

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def db():
    """Fresh in-memory TreadmillDB."""
    d = TreadmillDB(":memory:")
    yield d
    d.close()


@pytest.fixture
def profile(db):
    """Create a non-guest profile and return it."""
    return db.create_profile("Alice", color="#FF0000", weight_lbs=140)


def _prog(name="Test", intervals=None):
    if intervals is None:
        intervals = [{"name": "Warmup", "duration": 60, "speed": 3.0, "incline": 0}]
    return {"name": name, "intervals": intervals}


# ===========================================================================
# Schema & PRAGMAs
# ===========================================================================


class TestSchema:
    def test_tables_exist(self, db):
        tables = {r["name"] for r in db._read.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
        expected = {
            "profiles",
            "runs",
            "saved_workouts",
            "program_history",
            "coach_messages",
            "app_state",
            "migration_version",
        }
        assert expected.issubset(tables)

    def test_wal_mode(self, db):
        row = db._read.execute("PRAGMA journal_mode").fetchone()
        # In-memory shared cache may report 'memory'; file-based would report 'wal'
        assert row[0] in ("wal", "memory")

    def test_foreign_keys_enabled(self, db):
        row = db._read.execute("PRAGMA foreign_keys").fetchone()
        assert row[0] == 1


# ===========================================================================
# Guest profile
# ===========================================================================


class TestGuestProfile:
    def test_guest_exists_on_init(self, db):
        p = db.get_profile(GUEST_PROFILE_ID)
        assert p is not None
        assert p["name"] == "Guest"

    def test_get_profiles_excludes_guest_by_default(self, db):
        profiles = db.get_profiles()
        assert all(p["id"] != GUEST_PROFILE_ID for p in profiles)

    def test_get_profiles_includes_guest_when_asked(self, db):
        profiles = db.get_profiles(include_guest=True)
        assert any(p["id"] == GUEST_PROFILE_ID for p in profiles)

    def test_profile_count_excludes_guest(self, db):
        assert db.profile_count() == 0
        db.create_profile("Alice")
        assert db.profile_count() == 1

    def test_cannot_delete_guest(self, db):
        assert db.delete_profile(GUEST_PROFILE_ID) is False
        assert db.get_profile(GUEST_PROFILE_ID) is not None


# ===========================================================================
# Profile CRUD
# ===========================================================================


class TestProfileCRUD:
    def test_create_profile(self, db):
        p = db.create_profile("Bob", color="#00FF00", weight_lbs=180)
        assert p["name"] == "Bob"
        assert p["color"] == "#00FF00"
        assert p["weight_lbs"] == 180
        assert p["has_avatar"] == 0
        assert p["id"] != GUEST_PROFILE_ID

    def test_create_generates_initials(self, db):
        p = db.create_profile("John Doe")
        assert p["initials"] == "JD"

    def test_create_single_name_initial(self, db):
        p = db.create_profile("Alice")
        assert p["initials"] == "A"

    def test_update_profile(self, db, profile):
        updated = db.update_profile(profile["id"], name="Alice2", weight_lbs=150)
        assert updated["name"] == "Alice2"
        assert updated["weight_lbs"] == 150

    def test_update_vest(self, db, profile):
        updated = db.update_profile(profile["id"], vest_lbs=20)
        assert updated["vest_lbs"] == 20

    def test_delete_profile(self, db, profile):
        assert db.delete_profile(profile["id"]) is True
        assert db.get_profile(profile["id"]) is None

    def test_delete_nonexistent(self, db):
        assert db.delete_profile("nonexistent-id") is False

    def test_has_avatar_false_by_default(self, db, profile):
        assert profile["has_avatar"] == 0

    def test_avatar_roundtrip(self, db, profile):
        data = b"\x89PNG\r\n\x1a\nfakeimage"
        db.set_avatar(profile["id"], data)
        p = db.get_profile(profile["id"])
        assert p["has_avatar"] == 1
        assert db.get_avatar(profile["id"]) == data

    def test_clear_avatar(self, db, profile):
        db.set_avatar(profile["id"], b"img")
        db.clear_avatar(profile["id"])
        assert db.get_avatar(profile["id"]) is None
        assert db.get_profile(profile["id"])["has_avatar"] == 0


# ===========================================================================
# CASCADE deletes
# ===========================================================================


class TestCascade:
    def test_cascade_deletes_runs(self, db, profile):
        db.insert_run(profile["id"], {"started_at": "2026-01-01T00:00:00", "elapsed": 100})
        assert len(db.get_runs(profile["id"])) == 1
        db.delete_profile(profile["id"])
        assert len(db.get_runs(profile["id"])) == 0

    def test_cascade_deletes_workouts(self, db, profile):
        db.save_workout(profile["id"], _prog())
        assert len(db.get_saved_workouts(profile["id"])) == 1
        db.delete_profile(profile["id"])
        assert len(db.get_saved_workouts(profile["id"])) == 0

    def test_cascade_deletes_history(self, db, profile):
        db.add_to_history(profile["id"], _prog())
        assert len(db.get_program_history(profile["id"])) == 1
        db.delete_profile(profile["id"])
        assert len(db.get_program_history(profile["id"])) == 0

    def test_cascade_deletes_chat(self, db, profile):
        db.add_chat_message(profile["id"], {"role": "user", "text": "hi"})
        assert len(db.get_chat_history(profile["id"])) == 1
        db.delete_profile(profile["id"])
        assert len(db.get_chat_history(profile["id"])) == 0


# ===========================================================================
# Active profile
# ===========================================================================


class TestActiveProfile:
    def test_no_active_by_default(self, db):
        assert db.get_active_profile_id() is None

    def test_set_and_get_active(self, db, profile):
        db.set_active_profile_id(profile["id"])
        assert db.get_active_profile_id() == profile["id"]

    def test_clear_active(self, db, profile):
        db.set_active_profile_id(profile["id"])
        db.clear_active_profile()
        assert db.get_active_profile_id() is None


# ===========================================================================
# Data isolation
# ===========================================================================


class TestDataIsolation:
    def test_runs_isolated(self, db):
        a = db.create_profile("Alice")
        b = db.create_profile("Bob")
        db.insert_run(a["id"], {"started_at": "2026-01-01T00:00:00", "elapsed": 100})
        db.insert_run(b["id"], {"started_at": "2026-01-02T00:00:00", "elapsed": 200})
        assert len(db.get_runs(a["id"])) == 1
        assert len(db.get_runs(b["id"])) == 1
        assert db.get_runs(a["id"])[0]["elapsed"] == 100

    def test_workouts_isolated(self, db):
        a = db.create_profile("Alice")
        b = db.create_profile("Bob")
        db.save_workout(a["id"], _prog("Alice Workout"))
        db.save_workout(b["id"], _prog("Bob Workout"))
        assert len(db.get_saved_workouts(a["id"])) == 1
        assert db.get_saved_workouts(a["id"])[0]["name"] == "Alice Workout"
        assert len(db.get_saved_workouts(b["id"])) == 1

    def test_history_isolated(self, db):
        a = db.create_profile("Alice")
        b = db.create_profile("Bob")
        db.add_to_history(a["id"], _prog("A Prog"))
        db.add_to_history(b["id"], _prog("B Prog"))
        assert len(db.get_program_history(a["id"])) == 1
        assert len(db.get_program_history(b["id"])) == 1

    def test_chat_isolated(self, db):
        a = db.create_profile("Alice")
        b = db.create_profile("Bob")
        db.add_chat_message(a["id"], {"role": "user", "text": "hi from alice"})
        db.add_chat_message(b["id"], {"role": "user", "text": "hi from bob"})
        a_msgs = db.get_chat_history(a["id"])
        b_msgs = db.get_chat_history(b["id"])
        assert len(a_msgs) == 1
        assert len(b_msgs) == 1
        assert a_msgs[0]["text"] == "hi from alice"


# ===========================================================================
# Runs
# ===========================================================================


class TestRuns:
    def test_insert_and_get(self, db, profile):
        rid = db.insert_run(
            profile["id"],
            {
                "started_at": "2026-01-01T10:00:00",
                "elapsed": 600,
                "distance": 1.5,
                "end_reason": "user_stop",
            },
        )
        runs = db.get_runs(profile["id"])
        assert len(runs) == 1
        assert runs[0]["elapsed"] == 600
        assert runs[0]["id"] == rid

    def test_update_run(self, db, profile):
        rid = db.insert_run(profile["id"], {"started_at": "2026-01-01T10:00:00", "elapsed": 100})
        db.update_run(rid, elapsed=200, end_reason="program_complete")
        r = db.get_run(rid)
        assert r["elapsed"] == 200
        assert r["end_reason"] == "program_complete"

    def test_runs_ordered_newest_first(self, db, profile):
        db.insert_run(profile["id"], {"started_at": "2026-01-01T10:00:00", "elapsed": 100})
        db.insert_run(profile["id"], {"started_at": "2026-01-02T10:00:00", "elapsed": 200})
        runs = db.get_runs(profile["id"])
        assert runs[0]["elapsed"] == 200  # newest first


# ===========================================================================
# Saved workouts
# ===========================================================================


class TestSavedWorkouts:
    def test_save_and_get(self, db, profile):
        w = db.save_workout(profile["id"], _prog("My Workout"), source="generated", prompt="test")
        assert w["name"] == "My Workout"
        assert w["program"]["name"] == "My Workout"
        assert w["source"] == "generated"
        assert w["times_used"] == 0
        assert "total_duration" in w

    def test_rename_workout(self, db, profile):
        w = db.save_workout(profile["id"], _prog("Original"))
        renamed = db.rename_workout(w["id"], "New Name")
        assert renamed["name"] == "New Name"
        assert renamed["program"]["name"] == "New Name"

    def test_delete_workout(self, db, profile):
        w = db.save_workout(profile["id"], _prog())
        assert db.delete_workout(w["id"]) is True
        assert db.get_saved_workout(w["id"]) is None

    def test_update_usage(self, db, profile):
        w = db.save_workout(profile["id"], _prog())
        db.update_workout_usage(w["id"])
        w2 = db.get_saved_workout(w["id"])
        assert w2["times_used"] == 1
        assert w2["last_used_at"] is not None

    def test_save_returns_full_dict(self, db, profile):
        w = db.save_workout(profile["id"], _prog("Full"))
        assert "id" in w
        assert "program" in w
        assert "total_duration" in w
        assert isinstance(w["program"], dict)


# ===========================================================================
# Program history
# ===========================================================================


class TestProgramHistory:
    def test_add_and_get(self, db, profile):
        entry = db.add_to_history(profile["id"], _prog("Workout A"), prompt="make me sweat")
        assert entry["name"] == "Workout A"
        assert entry["prompt"] == "make me sweat"
        h = db.get_program_history(profile["id"])
        assert len(h) == 1

    def test_dedup_by_name(self, db, profile):
        db.add_to_history(profile["id"], _prog("Same Name"))
        db.add_to_history(profile["id"], _prog("Same Name"))
        h = db.get_program_history(profile["id"])
        assert len(h) == 1

    def test_cap_enforcement(self, db, profile):
        for i in range(MAX_HISTORY + 5):
            db.add_to_history(profile["id"], _prog(f"Workout {i}"))
        h = db.get_program_history(profile["id"])
        assert len(h) == MAX_HISTORY

    def test_update_history_entry(self, db, profile):
        entry = db.add_to_history(profile["id"], _prog())
        db.update_history_entry(entry["id"], completed=True, last_interval=2, last_elapsed=120)
        updated = db.get_history_entry(entry["id"])
        assert updated["completed"] == 1
        assert updated["last_interval"] == 2
        assert updated["last_elapsed"] == 120

    def test_get_history_entry_by_id(self, db, profile):
        entry = db.add_to_history(profile["id"], _prog("Findme"))
        found = db.get_history_entry(entry["id"])
        assert found is not None
        assert found["name"] == "Findme"

    def test_get_history_entry_not_found(self, db):
        assert db.get_history_entry("nonexistent") is None


# ===========================================================================
# Coach messages
# ===========================================================================


class TestCoachMessages:
    def test_add_and_get(self, db, profile):
        db.add_chat_message(profile["id"], {"role": "user", "parts": [{"text": "hello"}]})
        db.add_chat_message(profile["id"], {"role": "model", "parts": [{"text": "hi!"}]})
        msgs = db.get_chat_history(profile["id"])
        assert len(msgs) == 2

    def test_chronological_order(self, db, profile):
        for i in range(5):
            db.add_chat_message(profile["id"], {"role": "user", "seq": i})
        msgs = db.get_chat_history(profile["id"])
        assert [m["seq"] for m in msgs] == [0, 1, 2, 3, 4]

    def test_cap_enforcement(self, db, profile):
        for i in range(MAX_CHAT + 10):
            db.add_chat_message(profile["id"], {"seq": i})
        msgs = db.get_chat_history(profile["id"], limit=MAX_CHAT + 10)
        assert len(msgs) == MAX_CHAT

    def test_structured_messages(self, db, profile):
        msg = {"role": "model", "parts": [{"functionCall": {"name": "set_speed", "args": {"mph": 5}}}]}
        db.add_chat_message(profile["id"], msg)
        msgs = db.get_chat_history(profile["id"])
        assert msgs[0]["parts"][0]["functionCall"]["name"] == "set_speed"

    def test_limit_returns_most_recent(self, db, profile):
        for i in range(10):
            db.add_chat_message(profile["id"], {"seq": i})
        msgs = db.get_chat_history(profile["id"], limit=3)
        assert len(msgs) == 3
        assert msgs[0]["seq"] == 7  # most recent 3 in chrono order
        assert msgs[2]["seq"] == 9


# ===========================================================================
# Guest conversion
# ===========================================================================


class TestGuestConvert:
    def test_convert_transfers_runs(self, db):
        db.insert_run(GUEST_PROFILE_ID, {"started_at": "2026-01-01", "elapsed": 300})
        new = db.create_profile("NewUser")
        db.convert_guest(new["id"])
        assert len(db.get_runs(GUEST_PROFILE_ID)) == 0
        assert len(db.get_runs(new["id"])) == 1

    def test_convert_transfers_history(self, db):
        db.add_to_history(GUEST_PROFILE_ID, _prog("Guest Workout"))
        new = db.create_profile("NewUser")
        db.convert_guest(new["id"])
        assert len(db.get_program_history(GUEST_PROFILE_ID)) == 0
        assert len(db.get_program_history(new["id"])) == 1

    def test_convert_transfers_workouts(self, db):
        db.save_workout(GUEST_PROFILE_ID, _prog("Guest Fav"))
        new = db.create_profile("NewUser")
        db.convert_guest(new["id"])
        assert len(db.get_saved_workouts(GUEST_PROFILE_ID)) == 0
        assert len(db.get_saved_workouts(new["id"])) == 1

    def test_convert_transfers_chat(self, db):
        db.add_chat_message(GUEST_PROFILE_ID, {"role": "user", "text": "hi"})
        new = db.create_profile("NewUser")
        db.convert_guest(new["id"])
        assert len(db.get_chat_history(GUEST_PROFILE_ID)) == 0
        assert len(db.get_chat_history(new["id"])) == 1


# ===========================================================================
# Migration from JSON
# ===========================================================================


class TestMigration:
    def _write_json(self, path, data):
        with open(path, "w") as f:
            json.dump(data, f)

    def test_full_migration(self, db, profile):
        with tempfile.TemporaryDirectory() as td:
            runs_file = os.path.join(td, "runs.json")
            history_file = os.path.join(td, "history.json")
            workouts_file = os.path.join(td, "workouts.json")
            user_file = os.path.join(td, "user.json")

            self._write_json(runs_file, [{"id": "r1", "started_at": "2026-01-01", "elapsed": 600, "distance": 1.0}])
            self._write_json(
                history_file,
                [
                    {
                        "id": "h1",
                        "program": {
                            "name": "Hill Climb",
                            "intervals": [{"name": "W", "duration": 60, "speed": 3, "incline": 0}],
                        },
                        "created_at": "2026-01-01",
                        "total_duration": 60,
                    }
                ],
            )
            self._write_json(
                workouts_file,
                [
                    {
                        "id": "w1",
                        "name": "Fav",
                        "program": {
                            "name": "Fav",
                            "intervals": [{"name": "A", "duration": 120, "speed": 5, "incline": 2}],
                        },
                        "created_at": "2026-01-01",
                        "times_used": 3,
                    }
                ],
            )
            self._write_json(user_file, {"weight_lbs": 180, "vest_lbs": 10})

            db.migrate_from_json(
                profile["id"],
                runs_file=runs_file,
                history_file=history_file,
                workouts_file=workouts_file,
                user_file=user_file,
            )

            assert len(db.get_runs(profile["id"])) == 1
            assert len(db.get_program_history(profile["id"])) == 1
            assert len(db.get_saved_workouts(profile["id"])) == 1
            p = db.get_profile(profile["id"])
            assert p["weight_lbs"] == 180
            assert p["vest_lbs"] == 10
            # Files renamed
            assert os.path.isfile(runs_file + ".migrated")
            assert not os.path.isfile(runs_file)

    def test_migration_idempotent(self, db, profile):
        with tempfile.TemporaryDirectory() as td:
            runs_file = os.path.join(td, "runs.json")
            self._write_json(runs_file, [{"id": "r1", "started_at": "2026-01-01", "elapsed": 600}])
            db.migrate_from_json(profile["id"], runs_file=runs_file)
            # Second call should be a no-op
            db.migrate_from_json(profile["id"], runs_file=runs_file + ".migrated")
            assert len(db.get_runs(profile["id"])) == 1

    def test_migration_corrupted_json(self, db, profile):
        with tempfile.TemporaryDirectory() as td:
            runs_file = os.path.join(td, "runs.json")
            with open(runs_file, "w") as f:
                f.write("{not valid json")
            # Should not raise, just warn and skip
            db.migrate_from_json(profile["id"], runs_file=runs_file)
            assert len(db.get_runs(profile["id"])) == 0

    def test_migration_no_files(self, db, profile):
        # No files specified — should be a no-op
        db.migrate_from_json(profile["id"])
        # Just verify it doesn't crash and migration_version is set
        row = db._read.execute("SELECT version FROM migration_version WHERE version = 1").fetchone()
        assert row is not None

    def test_migration_fresh_db(self):
        """Migration on a fresh DB with no files just sets version."""
        d = TreadmillDB(":memory:")
        p = d.create_profile("Test")
        d.migrate_from_json(p["id"])
        row = d._read.execute("SELECT version FROM migration_version").fetchone()
        assert row["version"] == 1
        d.close()

    def test_migration_malformed_entry(self, db, profile):
        """Malformed entries within valid JSON are skipped, others succeed."""
        with tempfile.TemporaryDirectory() as td:
            runs_file = os.path.join(td, "runs.json")
            self._write_json(
                runs_file,
                [
                    {"id": "good1", "started_at": "2026-01-01", "elapsed": 100},
                    "not a dict",  # malformed
                    {"id": "good2", "started_at": "2026-01-02", "elapsed": 200},
                ],
            )
            db.migrate_from_json(profile["id"], runs_file=runs_file)
            runs = db.get_runs(profile["id"])
            assert len(runs) == 2  # both good entries survived
