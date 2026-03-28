"""Tests for WorkoutDB — in-memory SQLite query interface for workout data."""

import sqlite3

import pytest
from workout_db import WorkoutDB

# --- Test fixtures ---


def _make_program(name, intervals):
    """Build a program dict with the given intervals."""
    return {
        "name": name,
        "intervals": [
            {"name": f"Interval {i+1}", "duration": iv[0], "speed": iv[1], "incline": iv[2]}
            for i, iv in enumerate(intervals)
        ],
    }


def _make_history_entry(id, program, prompt=""):
    return {
        "id": str(id),
        "prompt": prompt,
        "program": program,
        "created_at": "2026-03-28T10:00:00",
        "total_duration": sum(iv["duration"] for iv in program["intervals"]),
        "completed": False,
        "last_interval": 0,
        "last_elapsed": 0,
    }


def _make_saved_entry(id, program, source="generated"):
    return {
        "id": str(id),
        "name": program["name"],
        "program": program,
        "source": source,
        "prompt": "",
        "created_at": "2026-03-28T10:00:00",
        "last_used": None,
        "times_used": 0,
        "total_duration": sum(iv["duration"] for iv in program["intervals"]),
    }


def _make_run(id, fingerprint, name="Test", elapsed=600, distance=1.0):
    return {
        "id": str(id),
        "program_fingerprint": fingerprint,
        "program_name": name,
        "started_at": "2026-03-28T10:00:00",
        "ended_at": "2026-03-28T10:10:00",
        "elapsed": elapsed,
        "distance": distance,
        "vert_feet": 0,
        "calories": 100,
        "end_reason": "program_complete",
        "program_completed": True,
        "is_manual": False,
    }


def _fingerprint(program):
    intervals = program.get("intervals", [])
    return "|".join(f"{iv.get('speed', 0)},{iv.get('incline', 0)},{iv.get('duration', 0)}" for iv in intervals)


def _make_db(history=None, workouts=None, runs=None):
    """Create a WorkoutDB with test data."""
    return WorkoutDB(
        history_loader=lambda: history or [],
        workouts_loader=lambda: workouts or [],
        runs_loader=lambda: runs or [],
        fingerprint_fn=_fingerprint,
    )


# --- Init tests ---


def test_init_empty():
    """WorkoutDB with no data creates tables and returns empty results."""
    db = _make_db()
    assert db.query("SELECT COUNT(*) as cnt FROM workouts") == [{"cnt": 0}]
    assert db.query("SELECT COUNT(*) as cnt FROM intervals") == [{"cnt": 0}]
    assert db.query("SELECT COUNT(*) as cnt FROM runs") == [{"cnt": 0}]
    db.close()


# --- Sync tests ---


def test_sync_from_history():
    """Populates workouts + intervals from history entries."""
    prog = _make_program("Hills", [(60, 3.0, 0), (120, 5.0, 3.0)])
    entry = _make_history_entry(1001, prog)
    db = _make_db(history=[entry])

    rows = db.query("SELECT id, name, is_saved FROM workouts")
    assert len(rows) == 1
    assert rows[0]["name"] == "Hills"
    assert rows[0]["is_saved"] == 0  # False

    intervals = db.query("SELECT * FROM intervals ORDER BY position")
    assert len(intervals) == 2
    assert intervals[0]["speed_mph"] == 3.0
    assert intervals[1]["speed_mph"] == 5.0
    db.close()


def test_sync_from_saved():
    """Populates workouts + intervals from saved workout entries."""
    prog = _make_program("HIIT", [(30, 8.0, 0), (30, 3.0, 0)])
    entry = _make_saved_entry(2001, prog)
    db = _make_db(workouts=[entry])

    rows = db.query("SELECT id, name, is_saved, source FROM workouts")
    assert len(rows) == 1
    assert rows[0]["name"] == "HIIT"
    assert rows[0]["is_saved"] == 1  # True
    assert rows[0]["source"] == "generated"
    db.close()


def test_merge_dedup():
    """Same fingerprint in both history + saved: saved wins."""
    prog = _make_program("MyWorkout", [(60, 3.0, 0), (60, 5.0, 2.0)])
    history_entry = _make_history_entry(1001, prog)
    saved_entry = _make_saved_entry(2001, prog)

    db = _make_db(history=[history_entry], workouts=[saved_entry])

    rows = db.query("SELECT id, name, is_saved FROM workouts")
    assert len(rows) == 1
    assert rows[0]["id"] == "2001"  # saved wins
    assert rows[0]["is_saved"] == 1
    db.close()


def test_sync_runs():
    """Populates runs table from run records."""
    prog = _make_program("Test", [(60, 3.0, 0)])
    fp = _fingerprint(prog)
    run = _make_run(3001, fp, elapsed=600, distance=1.5)
    db = _make_db(runs=[run])

    rows = db.query("SELECT * FROM runs")
    assert len(rows) == 1
    assert rows[0]["elapsed"] == 600
    assert rows[0]["distance"] == 1.5
    assert rows[0]["program_fingerprint"] == fp
    db.close()


def test_active_program_injected():
    """sync(active_program=...) inserts the live workout."""
    prog = _make_program("Live Workout", [(120, 6.0, 2.0)])
    db = _make_db()
    db.sync(active_program=prog)

    rows = db.query("SELECT id, name FROM workouts WHERE id = '__active__'")
    assert len(rows) == 1
    assert rows[0]["name"] == "Live Workout"

    intervals = db.query("SELECT * FROM intervals WHERE workout_id = '__active__' ORDER BY position")
    assert len(intervals) == 1
    assert intervals[0]["speed_mph"] == 6.0
    db.close()


def test_active_program_overrides():
    """Live workout with same fingerprint as saved still appears as __active__."""
    prog = _make_program("Original", [(60, 3.0, 0)])
    saved = _make_saved_entry(2001, prog)

    # Mutate the live program (extend an interval)
    mutated = _make_program("Original", [(120, 3.0, 0)])  # duration changed
    db = _make_db(workouts=[saved])
    db.sync(active_program=mutated)

    # Both should exist: saved version AND active version
    rows = db.query("SELECT id, name FROM workouts ORDER BY id")
    assert len(rows) == 2
    active = db.query("SELECT * FROM intervals WHERE workout_id = '__active__'")
    assert active[0]["duration_s"] == 120  # mutated duration
    saved_ivs = db.query("SELECT * FROM intervals WHERE workout_id = '2001'")
    assert saved_ivs[0]["duration_s"] == 60  # original duration
    db.close()


def test_resync_after_mutation():
    """sync() picks up new data from loaders."""
    data = {"history": [], "workouts": [], "runs": []}
    db = WorkoutDB(
        history_loader=lambda: data["history"],
        workouts_loader=lambda: data["workouts"],
        runs_loader=lambda: data["runs"],
        fingerprint_fn=_fingerprint,
    )
    assert db.query("SELECT COUNT(*) as cnt FROM workouts") == [{"cnt": 0}]

    # Add data and resync
    prog = _make_program("New", [(60, 4.0, 1.0)])
    data["history"] = [_make_history_entry(1001, prog)]
    db.sync()

    assert db.query("SELECT COUNT(*) as cnt FROM workouts") == [{"cnt": 1}]
    db.close()


# --- Authorizer tests ---


def test_authorizer_blocks_insert():
    """INSERT is denied by the authorizer."""
    db = _make_db()
    with pytest.raises(sqlite3.DatabaseError):
        db.query("INSERT INTO workouts VALUES ('x','x','x','x','x',0,'x',0,0)")
    db.close()


def test_authorizer_blocks_drop():
    """DROP is denied by the authorizer."""
    db = _make_db()
    with pytest.raises(sqlite3.DatabaseError):
        db.query("DROP TABLE workouts")
    db.close()


def test_authorizer_blocks_attach():
    """ATTACH DATABASE is denied by the authorizer."""
    db = _make_db()
    with pytest.raises(sqlite3.DatabaseError):
        db.query("ATTACH DATABASE ':memory:' AS evil")
    db.close()


def test_authorizer_allows_functions():
    """Aggregate functions (COUNT, MAX, AVG) work via SQLITE_FUNCTION."""
    prog = _make_program("Test", [(60, 3.0, 0), (120, 8.0, 5.0)])
    entry = _make_history_entry(1001, prog)
    db = _make_db(history=[entry])

    result = db.query("SELECT COUNT(*) as cnt, MAX(speed_mph) as max_speed FROM intervals")
    assert result[0]["cnt"] == 2
    assert result[0]["max_speed"] == 8.0
    db.close()


# --- Query tests ---


def test_query_row_limit():
    """Returns max 50 rows."""
    # Create a workout with 60 intervals
    intervals = [(10, 3.0, 0) for _ in range(60)]
    prog = _make_program("Long", intervals)
    entry = _make_history_entry(1001, prog)
    db = _make_db(history=[entry])

    rows = db.query("SELECT * FROM intervals")
    assert len(rows) == 50  # capped at MAX_ROWS
    db.close()


def test_query_invalid_sql():
    """Invalid SQL returns an error, doesn't crash."""
    db = _make_db()
    with pytest.raises(sqlite3.OperationalError):
        db.query("SELECTT * FORM workoutz")
    db.close()


def test_query_empty_result():
    """Query with no matching rows returns empty list."""
    db = _make_db()
    rows = db.query("SELECT * FROM workouts WHERE name = 'nonexistent'")
    assert rows == []
    db.close()


# --- Join tests ---


def test_intervals_join():
    """Can JOIN intervals to workouts."""
    prog = _make_program("Tempo", [(300, 6.0, 1.0), (180, 3.0, 0)])
    entry = _make_history_entry(1001, prog)
    db = _make_db(history=[entry])

    rows = db.query(
        "SELECT w.name, i.position, i.speed_mph "
        "FROM workouts w JOIN intervals i ON w.id = i.workout_id "
        "ORDER BY i.position"
    )
    assert len(rows) == 2
    assert rows[0]["name"] == "Tempo"
    assert rows[0]["speed_mph"] == 6.0
    assert rows[1]["speed_mph"] == 3.0
    db.close()


def test_runs_join_fingerprint():
    """Can JOIN runs to workouts via fingerprint."""
    prog = _make_program("Hills", [(60, 3.0, 0), (60, 7.0, 5.0)])
    fp = _fingerprint(prog)
    entry = _make_history_entry(1001, prog)
    run = _make_run(3001, fp, name="Hills", elapsed=120, distance=0.5)
    db = _make_db(history=[entry], runs=[run])

    rows = db.query(
        "SELECT w.name, r.elapsed, r.distance " "FROM workouts w JOIN runs r ON w.fingerprint = r.program_fingerprint"
    )
    assert len(rows) == 1
    assert rows[0]["name"] == "Hills"
    assert rows[0]["elapsed"] == 120
    db.close()
