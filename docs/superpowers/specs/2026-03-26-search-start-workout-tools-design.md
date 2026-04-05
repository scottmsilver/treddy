# Search & Start Workout Voice Tools

## Goal

Add two Gemini Live tools — `search_workouts` and `start_saved_workout` — so users can browse their saved workouts and program history by voice, then start one without generating a new program from scratch.

## Motivation

Currently the only way to start a workout via voice is `start_workout`, which always generates a brand-new program via Gemini. Users who have saved favorites or recently ran a program have no voice path to find and reuse them. They must use the UI to scroll through history or saved workouts, tap to load, then start.

## Tools

### `search_workouts`

Search across saved workouts and recent program history. Returns a text summary of matching entries for Gemini to read back.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `query` | STRING | yes | Search term — matched case-insensitively against workout name and original prompt. Empty string returns all entries. |
| `source` | STRING | no | Filter: `"saved"` (favorites only), `"history"` (recent 10 only), or omitted for both |

**Returns:** A formatted text string listing matches. Each entry includes:
- Name
- Duration (human-readable, e.g. "30 min")
- Source label (`saved` or `history`)
- Number of intervals
- ID (for `start_saved_workout`)

Example return value:
```
Found 2 workouts matching "hill":
1. "Hill Climber" — 25 min, 5 intervals (saved, used 3 times) [id: 1741623456789012345]
2. "Rolling Hills" — 30 min, 8 intervals (history) [id: 1773247873]
```

If no matches: `"No workouts found matching "<query>"."`

If query is empty or very generic (e.g. "all", "everything"): return all entries (saved first, then history), capped at 10 results to keep the response concise for voice.

**Deduplication:** If the same program appears in both history and saved (matched by interval fingerprint via `_program_fingerprint()`), show the saved version only (it's the canonical one). Name matching alone is insufficient — different programs can share a name.

### `start_saved_workout`

Load and start a workout by ID (from search results).

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `workout_id` | STRING | yes | ID returned by `search_workouts` |

**Returns:** Confirmation message, e.g. `"Started 'Hill Climber': 5 intervals, 25 min"`

**Behavior:**
1. Look up `workout_id` in saved workouts first, then history
2. If found in saved: increment `times_used`, update `last_used`, add to history, load program, start it (same logic as `POST /api/workouts/{id}/load` + `POST /api/program/start` — extract a shared helper to avoid duplication)
3. If found in history: load the program, refresh history entry, start it
4. If not found: return `"Workout not found. Try search_workouts to find available workouts."`

## Implementation Scope

### Python changes

**`python/program_engine.py`** — Add 2 entries to `TOOL_DECLARATIONS[0]["functionDeclarations"]`:

```python
{
    "name": "search_workouts",
    "description": "Search saved workouts and recent program history by name or keyword",
    "parameters": {
        "type": "OBJECT",
        "properties": {
            "query": {"type": "STRING", "description": "Search term to match against workout names and prompts"},
            "source": {"type": "STRING", "description": "Filter: 'saved', 'history', or omit for both"},
        },
        "required": ["query"],
    },
},
{
    "name": "start_saved_workout",
    "description": "Start a previously saved or recent workout by its ID (from search_workouts results)",
    "parameters": {
        "type": "OBJECT",
        "properties": {
            "workout_id": {"type": "STRING", "description": "Workout ID from search results"},
        },
        "required": ["workout_id"],
    },
},
```

**`python/program_engine.py`** — Add tool descriptions to `CHAT_SYSTEM_PROMPT`:

```
- search_workouts: search saved workouts and recent history by name/keyword. Use when user asks about their workouts, favorites, or past programs. Returns a list with IDs.
- start_saved_workout: start a workout from search results by ID. Use after search_workouts to launch a specific match.
```

Also add a guideline:
```
- When user asks to start a specific past workout ("do my hill workout", "start morning run"), use search_workouts first to find it, then start_saved_workout with the ID. Do NOT use start_workout for these — that generates a new program.
```

**`python/server.py`** — Add 2 handlers in `_exec_fn()`:

`search_workouts` handler:
- Read `query` and optional `source` from args
- Load saved workouts (`_load_workouts()`) and/or history (`_load_history()`) based on `source` filter
- Case-insensitive substring match on `name` and `prompt` fields
- Deduplicate: if a program fingerprint appears in both saved and history, keep saved only
- Format results as numbered text list (max 10)
- Return the formatted string

`start_saved_workout` handler:
- Read `workout_id` from args
- Look up in saved workouts first, then history
- If saved workout: use existing load-workout logic (update times_used/last_used, add to history, load program)
- If history entry: load program, refresh history entry
- Start the program via `sess.start_program()`
- Return confirmation with name, interval count, duration

### Kotlin changes

**`kotlin/.../voice/VoiceTools.kt`** — Two changes:
1. Add 2 `FunctionDeclaration` entries to the `TOOL_DECLARATIONS` list (mirrors the Python declarations — these are the JSON schemas sent in the Gemini Live setup message)
2. Add tool descriptions to `VOICE_SYSTEM_PROMPT` (same text as Python, keep them in sync)

**`kotlin/.../data/remote/TreadmillApi.kt`** — Add endpoint declaration:
```kotlin
@GET("/api/workouts/search")
suspend fun searchWorkouts(@Query("query") query: String, @Query("source") source: String? = null): SearchWorkoutsResponse
```

**`kotlin/.../data/remote/models/ApiModels.kt`** — Add response model:
```kotlin
@Serializable
data class SearchWorkoutsResponse(val results: String, val count: Int)
```

**`kotlin/.../voice/FunctionBridge.kt`** — Add 2 cases to the `when` block:

`search_workouts`: call `api.searchWorkouts(query, source)`, return `response.results`.

`start_saved_workout`: call `api.loadWorkout(id)` (existing, handles times_used/last_used/history), then `api.startProgram()`. Return confirmation.

### New API endpoint

**`GET /api/workouts/search`** — Server-side search (keeps logic in one place, Kotlin just calls it).

Query params:
- `query` (string, required)
- `source` (string, optional: `"saved"`, `"history"`)

Returns: `{"results": "formatted text string", "count": N}`

This avoids duplicating search/format logic between `_exec_fn` and the Kotlin bridge — both call the same endpoint. The `_exec_fn` handler for `search_workouts` calls this endpoint's logic directly (shared function).

## Voice UX Examples

**"What workouts do I have?"**
→ Gemini calls `search_workouts(query="")` → reads back the list

**"Do I have any hill programs?"**
→ `search_workouts(query="hill")` → "I found 2 hill workouts: ..."

**"Start the hill climber"**
→ `search_workouts(query="hill climber")` → finds 1 match → `start_saved_workout(id="...")` → "Started Hill Climber!"

**"Show me my saved workouts"**
→ `search_workouts(query="", source="saved")` → reads back saved-only list

**"Start that HIIT one from last week"**
→ `search_workouts(query="HIIT")` → `start_saved_workout(id="...")` → started

## Testing

**Unit tests (no API key needed):**
- `search_workouts` with mocked history + workouts: verify matching, deduplication, source filtering, empty results, max 10 cap
- `start_saved_workout` with mocked data: verify lookup in saved vs history, not-found case
- Verify new tool declarations are syntactically valid

**Voice tests (API key needed):**
- Add 1-2 test cases to `voice_test_cases.py`:
  - "What workouts do I have" → expects `search_workouts`
  - "Do I have any hill programs" → expects `search_workouts`
- Note: multi-tool-call chaining (search then start) is unreliable as a voice test since Gemini may not chain two calls in one turn consistently. Test `start_saved_workout` via the text prompt ADB path instead.

## Out of Scope

- Fuzzy matching (substring is sufficient — Gemini will rephrase if no results)
- Sorting results by relevance (saved first, then history by recency is good enough)
- Deleting or renaming workouts by voice
- Resuming from a specific position by voice (existing resume endpoint exists but we won't expose it as a tool yet)
