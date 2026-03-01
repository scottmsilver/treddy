#!/bin/bash
# pi-lock.sh — Advisory lock for Pi hardware access.
#
# Prevents multiple worktrees from deploying to the Pi simultaneously.
# Uses flock on a shared lock file.
#
# Usage:
#   scripts/pi-lock.sh acquire "deploying from feature-branch"
#   scripts/pi-lock.sh release
#   scripts/pi-lock.sh status

set -euo pipefail

LOCK_FILE="/tmp/precor-pi.lock"
INFO_FILE="/tmp/precor-pi.lock.info"

case "${1:-status}" in
    acquire)
        REASON="${2:-unspecified}"
        # Try non-blocking first to report holder
        if ! flock -n 9 2>/dev/null; then
            echo "Pi is locked by another session:"
            cat "$INFO_FILE" 2>/dev/null || echo "  (no info available)"
            echo ""
            echo "Waiting for lock..."
        fi
        # Block until lock acquired
        exec 9>"$LOCK_FILE"
        flock 9
        # Write lock info
        cat > "$INFO_FILE" << EOF
  User:    $(whoami)
  PID:     $$
  Reason:  $REASON
  Since:   $(date -Iseconds)
  PWD:     $(pwd)
EOF
        echo "Pi lock acquired: $REASON"
        ;;

    release)
        if [ -f "$INFO_FILE" ]; then
            rm -f "$INFO_FILE"
        fi
        # Lock is released when the fd is closed (process exits)
        echo "Pi lock released"
        ;;

    status)
        if [ -f "$INFO_FILE" ]; then
            # Check if lock is actually held
            if ! flock -n "$LOCK_FILE" -c true 2>/dev/null; then
                echo "Pi is LOCKED:"
                cat "$INFO_FILE"
            else
                echo "Pi is available (stale info file cleaned)"
                rm -f "$INFO_FILE"
            fi
        else
            echo "Pi is available"
        fi
        ;;

    *)
        echo "Usage: $0 {acquire|release|status} [reason]"
        exit 1
        ;;
esac
