# Precor 9.3x — AI Treadmill

> A 2005 treadmill that listens when you talk to it.

A Raspberry Pi intercepts the serial bus on a Precor 9.31 treadmill, replacing the dumb console with an AI coach, voice control, phone/tablet UI, and Bluetooth fitness app support. Everything the original console could do, plus everything it couldn't.

---

## 🎙️ Voice Control + AI Coach

<img src="docs/screenshots/android-running.png" width="700" alt="Running screen on Android tablet — timer, elevation profile, speed/incline controls">

- Talk to your treadmill: "set speed to 5 mph" or "start a hill workout"
- Gemini Live: real-time voice to function calls to hardware control
- AI generates structured interval programs from plain English descriptions
- Queries your workout history via SQL to give contextual coaching
- 11 Gemini tools: speed, incline, start/stop/pause/skip, extend intervals, load saved workouts, query data

## 📱 Apps

<img src="docs/screenshots/android-lobby.png" width="700" alt="Lobby screen on Android tablet — saved workouts, program history">

- **Android**: Kotlin + Jetpack Compose, designed for a tablet mounted on the treadmill console
- **Web**: React 19 + TypeScript + Vite, same features, runs on any browser
- Saved workouts, program history, session metrics, elevation profiles
- Touch targets 44px+, landscape nav rail, warm dark palette

## 💙 Bluetooth FTMS

- Rust daemon advertises as a standard Bluetooth FTMS (Fitness Machine Service) device
- Zwift, Peloton, QZ Fitness, Apple Watch see it as a smart treadmill
- Speed, incline, distance, elapsed time broadcast at 1 Hz
- Control Point: fitness apps can set speed/incline back through BLE

## ❤️ Heart Rate

- Rust BLE client connects to any standard heart rate monitor (HR Service 0x180D)
- HR data flows to the UI, AI coach context, and ACSM-based calorie calculations
- Auto-reconnects, device persistence, multi-device scan

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│   Web UI (React + Vite)  │  Android (Kotlin + Compose)  │
├──────────────────────────┴──────────────────────────────┤
│  REST / WebSocket / Gemini Live (voice)                 │
├─────────────────────────────────────────────────────────┤
│                  server.py (FastAPI)                     │
│   Sessions, programs, AI chat, workout query DB          │
│   workout_session.py │ program_engine.py │ workout_db.py │
├──────────────────────┼───────────────────┼──────────────┤
│  treadmill_client.py │  hrm_client.py   │              │
│  (Unix socket IPC)   │  (Unix socket)   │              │
├──────────────────────┴───────────────────┴──────────────┤
│  treadmill_io (C++20)  │  ftms-daemon   │  hrm-daemon  │
│  GPIO serial, safety   │  (Rust, BLE)   │  (Rust, BLE) │
│  proxy/emulate modes   │  FTMS service  │  HR client   │
└─────────────────────────┴──────────────────┴────────────┘
                          │
                    Precor 9.31
                  RS-485 serial bus
```

- **C++ binary** — safety-critical GPIO serial I/O. 3-hour timeout, auto proxy/emulate, physical buttons always win. Zero-allocation hot paths.
- **Python server** — FastAPI, all business logic. Gemini AI, workout sessions, program engine, workout query DB.
- **FTMS daemon** — Rust, Bluetooth FTMS advertising for fitness apps.
- **HRM daemon** — Rust, BLE heart rate monitor client.
- **Web UI** — React 19 + TypeScript, display layer only. Every decision is server-side.
- **Android** — Kotlin + Jetpack Compose. Same server API, same features.

Full architecture details: [CLAUDE.md](CLAUDE.md)

---

## The Hardware Story

> This project started with a $200 Craigslist treadmill and a logic analyzer. The serial protocol turned out to be plain ASCII text — we just had the polarity wrong and spent days decoding "binary" that was actually `[key:value]` pairs with every bit flipped.

[Full reverse engineering writeup →](HARDWARE.md)

---

## Quick Start

**Prerequisites (Pi):** `libpigpio-dev`, `g++`, Python 3 with `google-genai`, `fastapi`, `uvicorn`, `gpxpy`. Gemini API key in `.gemini_key`.

```bash
make                         # build C++ binary
sudo ./build/treadmill_io    # start GPIO daemon (must be root)
python3 python/server.py     # start web server → https://<pi>:8000
```

**Deploy to Pi:**
```bash
make deploy    # stages, rsyncs, builds on Pi, restarts all 4 services
```

**Local dev (no Pi needed):**
```bash
TREADMILL_MOCK=1 ./scripts/dev.sh    # Caddy + server + Vite HMR
```

For developers: see [CLAUDE.md](CLAUDE.md) for API reference, testing, architecture details, and code review standards.

## License

MIT
