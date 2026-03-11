import { useMemo } from 'react';
import { useTreadmillState } from './TreadmillContext';
import type { Interval } from './types';

const W = 400, H = 140, PAD = 10;

/** Ramp width in chart units — represents incline transition time.
 *  The ramp starts at the interval boundary and slopes into the next interval.
 *  Capped so the ramp never exceeds 30% of the next interval's width. */
const RAMP_W = 8;

/** Build staircase-with-ramps SVG paths from interval data.
 *  Each interval is flat at its incline. At the boundary, the line holds
 *  the old incline right up to the boundary, then ramps into the next
 *  interval's incline over a short distance. */
function staircasePaths(
  segments: { x: number; w: number; y: number }[],
): { outline: string; area: string } {
  const n = segments.length;
  if (n === 0) return { outline: '', area: '' };
  if (n === 1) {
    const s = segments[0];
    const outline = `M0,${s.y} L${W},${s.y}`;
    return { outline, area: outline + ` L${W},${H} L0,${H} Z` };
  }

  let outline = `M0,${segments[0].y}`;
  for (let i = 0; i < n - 1; i++) {
    const seg = segments[i];
    const next = segments[i + 1];
    const boundary = seg.x + seg.w;

    // Flat at current incline all the way to boundary
    outline += ` L${boundary},${seg.y}`;

    if (seg.y !== next.y) {
      // Ramp into next interval's incline
      const ramp = Math.min(RAMP_W, next.w * 0.3);
      outline += ` L${boundary + ramp},${next.y}`;
    }
  }
  // Last segment extends flat to end
  outline += ` L${segments[n - 1].x + segments[n - 1].w},${segments[n - 1].y}`;
  outline += ` L${W},${segments[n - 1].y}`;

  const area = outline + ` L${W},${H} L0,${H} Z`;
  return { outline, area };
}

/** Evaluate staircase-with-ramps Y at a given x position */
function evalStaircaseY(
  segments: { x: number; w: number; y: number }[],
  x: number,
): number {
  const n = segments.length;
  if (n === 0) return H / 2;
  if (n === 1) return segments[0].y;

  for (let i = 0; i < n - 1; i++) {
    const seg = segments[i];
    const next = segments[i + 1];
    const boundary = seg.x + seg.w;

    if (x <= boundary) return seg.y;

    if (seg.y !== next.y) {
      const ramp = Math.min(RAMP_W, next.w * 0.3);
      if (x < boundary + ramp) {
        const t = (x - boundary) / ramp;
        return seg.y + t * (next.y - seg.y);
      }
    }
  }

  return segments[n - 1].y;
}

export function useProgram() {
  const { program: pgm } = useTreadmillState();

  const { program, running, paused, completed, currentInterval, intervalElapsed, totalElapsed, totalDuration } = pgm;
  const intervals = program?.intervals ?? [];

  // Static elevation paths — only recompute when the interval list changes
  const { elevOutline, elevAreaPath, segs, totalDur, maxIncline, yAxisMax, intervalBoundaryXs } = useMemo(() => {
    const dur = totalDuration || intervals.reduce((s, iv) => s + iv.duration, 0);

    // Build staircase segments: one per interval with x, width, y
    let x = 0;
    const segments: { x: number; w: number; y: number }[] = [];
    let maxInc = 0;
    if (dur) {
      for (const iv of intervals) {
        if (iv.incline > maxInc) maxInc = iv.incline;
      }
    }
    // Autoscale: Y-axis max = smallest nice tick ceiling above maxInc
    const yAxisMax = maxInc <= 0 ? 5 : maxInc <= 5 ? 5 : maxInc <= 10 ? 10 : 15;
    if (dur) {
      for (const iv of intervals) {
        const segW = (iv.duration / dur) * W;
        const y = H - PAD - (iv.incline / yAxisMax) * (H - PAD * 2);
        segments.push({ x, w: segW, y });
        x += segW;
      }
    }

    const intervalBoundaryXs: number[] = [];
    if (dur && intervals.length > 0) {
      let cumX = 0;
      for (const iv of intervals) {
        intervalBoundaryXs.push(cumX);
        cumX += (iv.duration / dur) * W;
      }
      intervalBoundaryXs.push(W);
    }

    const { outline, area } = staircasePaths(segments);

    return { elevOutline: outline, elevAreaPath: area, segs: segments, totalDur: dur, maxIncline: maxInc, yAxisMax, intervalBoundaryXs };
  }, [intervals, totalDuration]);

  // Dynamic position — recomputes every tick
  const timelinePos = totalDur ? Math.min(100, (totalElapsed / totalDur) * 100) : 0;
  const elevPosX = Math.min(W, (timelinePos / 100) * W);

  // Evaluate staircase at current X for dot tracking
  const elevPosY = segs.length ? evalStaircaseY(segs, elevPosX) : H / 2;

  const currentIv: Interval | null =
    program && currentInterval < intervals.length ? intervals[currentInterval] : null;
  const nextIv: Interval | null =
    program && currentInterval + 1 < intervals.length ? intervals[currentInterval + 1] : null;
  const ivRemaining = currentIv ? Math.max(0, currentIv.duration - intervalElapsed) : 0;
  const totalRemaining = Math.max(0, totalDur - totalElapsed);
  const ivPct = currentIv && currentIv.duration ? Math.min(100, (intervalElapsed / currentIv.duration) * 100) : 0;

  return {
    program,
    running,
    paused,
    completed,
    currentInterval,
    intervalElapsed,
    totalElapsed,
    totalDuration: totalDur,
    currentIv,
    nextIv,
    ivRemaining,
    totalRemaining,
    ivPct,
    timelinePos,
    elevOutline,
    elevAreaPath,
    elevPosX,
    elevPosY,
    intervalCount: intervals.length,
    maxIncline,
    yAxisMax,
    intervalBoundaryXs,
  };
}
