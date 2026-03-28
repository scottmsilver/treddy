import { useMemo, useState, useEffect, useRef } from 'react';
import { useTreadmillState } from './TreadmillContext';
import { fmtDur, paceDisplay } from '../utils/formatters';

export function useSession() {
  const { session, status, program } = useTreadmillState();

  // --- Pure client-side timer with gradual drift correction ---
  // Instead of anchoring to server elapsed and interpolating forward (which causes
  // visible bouncing when server updates arrive late), we maintain a local start time
  // and count up independently. On each server update, we blend toward the server value
  // using exponential smoothing — never snapping, always smooth.
  const BLEND_FACTOR = 0.15;    // 15% correction per server update (~1Hz)
  const SNAP_THRESHOLD = 2000;  // ms — snap if drift > 2s (unpause, initial state)

  const serverElapsed = session.elapsed;
  const timerStartRef = useRef(0);        // Date.now() base for local counting
  const timerInitRef = useRef(false);
  const prevServerElapsed = useRef(serverElapsed);
  const [localElapsed, setLocalElapsed] = useState(serverElapsed);
  const tickRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined);

  // When server sends a new elapsed value, apply gradual drift correction
  useEffect(() => {
    if (serverElapsed !== prevServerElapsed.current) {
      prevServerElapsed.current = serverElapsed;
      const now = Date.now();
      const targetStart = now - serverElapsed * 1000;

      if (!timerInitRef.current) {
        // First update — snap to server elapsed
        timerStartRef.current = targetStart;
        timerInitRef.current = true;
      } else {
        // Gradual drift correction via exponential blend
        const drift = targetStart - timerStartRef.current;
        if (Math.abs(drift) > SNAP_THRESHOLD) {
          timerStartRef.current = targetStart;  // large drift — snap
        } else {
          timerStartRef.current += drift * BLEND_FACTOR;
        }
      }
    }
  }, [serverElapsed]);

  // Reset when session becomes inactive
  useEffect(() => {
    if (!session.active) {
      timerInitRef.current = false;
      setLocalElapsed(serverElapsed);
    }
  }, [session.active, serverElapsed]);

  // Run local ticker when session is active and not paused
  useEffect(() => {
    if (tickRef.current) {
      clearInterval(tickRef.current);
      tickRef.current = undefined;
    }

    if (!session.active || program.paused) {
      setLocalElapsed(serverElapsed);
      return;
    }

    tickRef.current = setInterval(() => {
      if (timerInitRef.current) {
        setLocalElapsed(Math.max(0, (Date.now() - timerStartRef.current) / 1000));
      }
    }, 100);

    return () => {
      if (tickRef.current) {
        clearInterval(tickRef.current);
        tickRef.current = undefined;
      }
    };
  }, [session.active, program.paused, serverElapsed]);

  return useMemo(() => {
    const speedMph = status.emulate
      ? status.emuSpeed / 10
      : (status.speed ?? 0);

    return {
      active: session.active,
      elapsed: session.elapsed,
      elapsedDisplay: fmtDur(localElapsed),
      distance: session.distance,
      distDisplay: session.distance.toFixed(2),
      vertFeet: session.vertFeet,
      vertDisplay: Math.round(session.vertFeet).toLocaleString(),
      calories: session.calories,
      caloriesDisplay: Math.round(session.calories).toLocaleString(),
      pace: paceDisplay(speedMph),
      speedMph,
      endReason: session.endReason,
    };
  }, [session, status.emulate, status.emuSpeed, status.speed, localElapsed]);
}
