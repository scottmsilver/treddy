"""In-memory SQLite database for workout and run history queries.

Provides a read-only SQL interface for the Gemini AI coach to query
workout structures, interval details, and run history. The database
is populated from existing JSON files and the live active program.

Safety: All writes are blocked at the engine level via set_authorizer().
"""

import logging
import sqlite3
import time

logger = logging.getLogger(__name__)

# Operations allowed by the authorizer (read-only)
_ALLOWED_OPS = {
    sqlite3.SQLITE_READ,
    sqlite3.SQLITE_SELECT,
    sqlite3.SQLITE_FUNCTION,
}

MAX_ROWS = 50
QUERY_TIMEOUT_MS = 500


def _readonly_authorizer(action, arg1, arg2, db_name, trigger_name):
    """Allow only read operations on the database."""
    if action in _ALLOWED_OPS:
        return sqlite3.SQLITE_OK
    return sqlite3.SQLITE_DENY


class WorkoutDB:
    """In-memory SQLite database for workout queries.

    Args:
        history_loader: callable returning list of program history entries
        workouts_loader: callable returning list of saved workout entries
        runs_loader: callable returning list of run record entries
        fingerprint_fn: callable(program) -> str for interval hashing
    """

    def __init__(self, history_loader, workouts_loader, runs_loader, fingerprint_fn):
        self._history_loader = history_loader
        self._workouts_loader = workouts_loader
        self._runs_loader = runs_loader
        self._fingerprint_fn = fingerprint_fn
        # check_same_thread=False is safe: all access is from the single asyncio
        # event loop (sync from mutation hooks, query from _exec_fn). No threads.
        self._conn = sqlite3.connect(":memory:", check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        # Authorizer is always-on by default — blocks all writes. Temporarily
        # disabled inside sync() which needs to DROP/CREATE/INSERT.
        self._conn.set_authorizer(_readonly_authorizer)
        self.sync()

    def sync(self, active_program=None):
        """Rebuild the database from JSON sources + optional live program.

        Args:
            active_program: The currently loaded program dict from ProgramState,
                or None if no program is active. This ensures the DB has the
                live workout state (including mid-run mutations).
        """
        # Temporarily disable the authorizer so we can write
        self._conn.set_authorizer(None)
        c = self._conn.cursor()

        # Drop and recreate tables
        c.execute("DROP TABLE IF EXISTS intervals")
        c.execute("DROP TABLE IF EXISTS runs")
        c.execute("DROP TABLE IF EXISTS workouts")

        c.execute(
            """
            CREATE TABLE workouts (
                id TEXT PRIMARY KEY,
                fingerprint TEXT,
                name TEXT NOT NULL,
                source TEXT,
                prompt TEXT,
                total_duration INTEGER,
                created_at TEXT,
                times_used INTEGER DEFAULT 0,
                is_saved BOOLEAN DEFAULT FALSE
            )
        """
        )
        c.execute(
            """
            CREATE TABLE intervals (
                workout_id TEXT REFERENCES workouts(id),
                position INTEGER,
                name TEXT,
                duration_s INTEGER,
                speed_mph REAL,
                incline_pct REAL,
                PRIMARY KEY (workout_id, position)
            )
        """
        )
        c.execute(
            """
            CREATE TABLE runs (
                id TEXT PRIMARY KEY,
                program_fingerprint TEXT,
                program_name TEXT,
                started_at TEXT,
                ended_at TEXT,
                elapsed REAL,
                distance REAL,
                vert_feet REAL,
                calories REAL,
                end_reason TEXT,
                program_completed BOOLEAN,
                is_manual BOOLEAN
            )
        """
        )

        seen_fingerprints = set()

        # Saved workouts first (they win on fingerprint collision)
        for w in self._workouts_loader():
            program = w.get("program", {})
            fp = self._fingerprint_fn(program)
            seen_fingerprints.add(fp)
            wid = str(w.get("id", ""))
            c.execute(
                "INSERT OR IGNORE INTO workouts VALUES (?,?,?,?,?,?,?,?,?)",
                (
                    wid,
                    fp,
                    w.get("name") or program.get("name", "?"),
                    w.get("source"),
                    w.get("prompt"),
                    w.get("total_duration"),
                    w.get("created_at"),
                    w.get("times_used", 0),
                    True,
                ),
            )
            self._insert_intervals(c, wid, program)

        # History entries (skip if fingerprint already seen)
        for h in self._history_loader():
            program = h.get("program", {})
            fp = self._fingerprint_fn(program)
            if fp in seen_fingerprints:
                continue
            seen_fingerprints.add(fp)
            hid = str(h.get("id", ""))
            c.execute(
                "INSERT OR IGNORE INTO workouts VALUES (?,?,?,?,?,?,?,?,?)",
                (
                    hid,
                    fp,
                    program.get("name", "?"),
                    None,
                    h.get("prompt"),
                    h.get("total_duration"),
                    h.get("created_at"),
                    0,
                    False,
                ),
            )
            self._insert_intervals(c, hid, program)

        # Active program (live state, may differ from saved JSON)
        if active_program:
            fp = self._fingerprint_fn(active_program)
            active_id = "__active__"
            total_dur = sum(iv.get("duration", 0) for iv in active_program.get("intervals", []))
            # Replace any existing active row
            c.execute("DELETE FROM intervals WHERE workout_id = ?", (active_id,))
            c.execute("DELETE FROM workouts WHERE id = ?", (active_id,))
            c.execute(
                "INSERT INTO workouts VALUES (?,?,?,?,?,?,?,?,?)",
                (
                    active_id,
                    fp,
                    active_program.get("name", "Active Workout"),
                    "active",
                    None,
                    total_dur,
                    None,
                    0,
                    False,
                ),
            )
            self._insert_intervals(c, active_id, active_program)

        # Run records
        for r in self._runs_loader():
            c.execute(
                "INSERT OR IGNORE INTO runs VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    str(r.get("id", "")),
                    r.get("program_fingerprint"),
                    r.get("program_name"),
                    r.get("started_at"),
                    r.get("ended_at"),
                    r.get("elapsed"),
                    r.get("distance"),
                    r.get("vert_feet"),
                    r.get("calories"),
                    r.get("end_reason"),
                    r.get("program_completed"),
                    r.get("is_manual"),
                ),
            )

        self._conn.commit()
        # Re-enable the authorizer
        self._conn.set_authorizer(_readonly_authorizer)

    def _insert_intervals(self, cursor, workout_id, program):
        """Insert interval rows for a workout program."""
        for i, iv in enumerate(program.get("intervals", [])):
            cursor.execute(
                "INSERT OR IGNORE INTO intervals VALUES (?,?,?,?,?,?)",
                (
                    workout_id,
                    i,
                    iv.get("name"),
                    iv.get("duration"),
                    iv.get("speed"),
                    iv.get("incline"),
                ),
            )

    def query(self, sql):
        """Execute a read-only SQL query and return results as list of dicts.

        Args:
            sql: SQL query string (only SELECT allowed, enforced by authorizer)

        Returns:
            list of dicts, one per row, with column names as keys

        Raises:
            sqlite3.DatabaseError: on invalid SQL or denied operations
            OperationalError: on timeout
        """
        logger.info("workout_db query: %s", sql)

        # Set up timeout via progress handler
        start = time.monotonic()

        def _check_timeout():
            elapsed_ms = (time.monotonic() - start) * 1000
            if elapsed_ms > QUERY_TIMEOUT_MS:
                return 1  # non-zero aborts
            return 0

        self._conn.set_progress_handler(_check_timeout, 1000)
        # Authorizer is always-on (set in __init__), no need to toggle here

        try:
            cursor = self._conn.execute(sql)
            rows = cursor.fetchmany(MAX_ROWS)
            return [dict(row) for row in rows]
        finally:
            self._conn.set_progress_handler(None, 0)

    def close(self):
        """Close the database connection."""
        self._conn.close()
