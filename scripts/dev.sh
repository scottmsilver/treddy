#!/bin/bash
# dev.sh — Launch the full dev stack (Caddy + server.py + Vite) with worktree isolation.
#
# Usage:
#   ./scripts/dev.sh                    # Connect to real Pi
#   TREADMILL_MOCK=1 ./scripts/dev.sh   # Mock mode, no Pi needed
#
# Ctrl-C kills all processes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/worktree-env.sh"

echo "=== Dev Stack ==="
echo "  Caddy:  http://localhost:$CADDY_PORT  (entry point)"
echo "  Server: http://localhost:$TREADMILL_SERVER_PORT  (internal)"
echo "  Vite:   http://localhost:$VITE_SERVER_PORT  (internal)"
if [ "${TREADMILL_MOCK:-}" = "1" ]; then
    echo "  Mode:   MOCK (no Pi connection)"
fi
echo ""

# Export for child processes
export CADDY_PORT TREADMILL_SERVER_PORT VITE_SERVER_PORT

# Kill all children on exit
trap 'kill 0 2>/dev/null; exit' EXIT INT TERM

# Start Caddy
caddy run --config "$PROJECT_ROOT/Caddyfile.dev" --adapter caddyfile &

# Start server.py
(cd "$PROJECT_ROOT" && python3 python/server.py) &

# Start Vite dev server
(cd "$PROJECT_ROOT/web" && npx vite --port "$VITE_SERVER_PORT" --strictPort) &

wait
