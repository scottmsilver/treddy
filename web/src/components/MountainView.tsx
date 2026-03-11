import React, { memo, useRef, useCallback, useState, useEffect, useMemo } from 'react';
import { useProgram } from '../state/useProgram';
import { useTreadmillState, useTreadmillActions } from '../state/TreadmillContext';

/* Chart dimensions */
const W = 400, H = 140, PAD = 10;
const ML = 32, MR = 4, MT = 4, MB = 18;
const VB_W = ML + W + MR;
const VB_H = MT + H + MB;
const TICK = 4;
const DOUBLE_TAP_MS = 300;
const MAX_RENDER_PTS = 300;

/* ── Vert-ft-per-second for a given speed (mph) and incline (%) ── */
function vertRate(speedMph: number, inclinePct: number): number {
  // ft/s = speed_mph * 5280/3600 * grade
  return speedMph * (5280 / 3600) * (inclinePct / 100);
}

/* ── Y-axis helpers ── */

function niceElevCeil(maxElev: number): number {
  if (maxElev <= 0) return 25;
  const steps = [25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000];
  for (const s of steps) if (maxElev <= s * 0.85) return s;
  return Math.ceil(maxElev / 5000) * 5000;
}

function elevTickValues(yMax: number): number[] {
  if (yMax <= 25) return [0, 10, 25];
  if (yMax <= 50) return [0, 25, 50];
  if (yMax <= 100) return [0, 50, 100];
  if (yMax <= 200) return [0, 100, 200];
  if (yMax <= 300) return [0, 150, 300];
  if (yMax <= 500) return [0, 250, 500];
  if (yMax <= 750) return [0, 250, 500, 750];
  if (yMax <= 1000) return [0, 500, 1000];
  if (yMax <= 1500) return [0, 500, 1000, 1500];
  if (yMax <= 2000) return [0, 1000, 2000];
  if (yMax <= 3000) return [0, 1000, 2000, 3000];
  if (yMax <= 5000) return [0, 2500, 5000];
  return [0, 5000, 10000];
}

function fmtElev(ft: number): string {
  if (ft >= 1000) {
    const k = ft / 1000;
    return k === Math.floor(k) ? `${k}k` : `${k.toFixed(1)}k`;
  }
  return String(ft);
}

/* ── X-axis helpers ── */

function computeTimeTicks(totalSec: number): { sec: number; label: string }[] {
  if (totalSec <= 10) return [];
  const rawStep = totalSec / 5;
  const steps = [15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200];
  let step = steps[0];
  for (const s of steps) { step = s; if (s >= rawStep) break; }
  const out: { sec: number; label: string }[] = [];
  const hrs = totalSec >= 3600;
  for (let t = step; t < totalSec; t += step) {
    if (totalSec - t < step * 0.15) continue;
    let label: string;
    if (hrs) {
      const h = Math.floor(t / 3600);
      const m = Math.round((t % 3600) / 60);
      label = h === 0 ? `:${String(m).padStart(2, '0')}`
        : m === 0 ? `${h}h`
        : `${h}:${String(m).padStart(2, '0')}`;
    } else {
      label = String(Math.round(t / 60));
    }
    out.push({ sec: t, label });
  }
  return out;
}

/* ── Downsample for rendering performance ── */

interface DataPoint { time: number; elev: number }

function downsample(pts: DataPoint[], max: number): DataPoint[] {
  if (pts.length <= max) return pts;
  const result: DataPoint[] = [pts[0]];
  const step = (pts.length - 1) / (max - 1);
  for (let i = 1; i < max - 1; i++) result.push(pts[Math.round(i * step)]);
  result.push(pts[pts.length - 1]);
  return result;
}

/* ── Styles ── */

const labelStyle: React.CSSProperties = {
  position: 'absolute', pointerEvents: 'none',
  fontSize: 9, fontWeight: 500, fontFamily: 'inherit',
  color: 'rgba(232,228,223,0.5)',
};

const arrowStyle: React.CSSProperties = {
  position: 'absolute', top: '50%', transform: 'translateY(-50%)',
  width: 48, height: 48, borderRadius: '50%',
  background: 'rgba(30,29,27,0.7)',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontSize: 24, fontWeight: 700, color: 'rgba(232,228,223,0.8)',
  pointerEvents: 'none', zIndex: 2,
  animation: 'arrowFlash 400ms ease-out forwards',
};

/* ── Component ── */

interface MountainViewProps {
  onSingleTap?: () => void;
}

const MountainView = memo(function MountainView({ onSingleTap }: MountainViewProps): React.ReactElement {
  const pgm = useProgram();
  const actions = useTreadmillActions();
  const { session } = useTreadmillState();

  /* ─── Planned cumulative elevation from program intervals ─── */
  const planned = useMemo(() => {
    const intervals = pgm.program?.intervals ?? [];
    const totalDur = pgm.totalDuration;
    if (!totalDur || intervals.length === 0) return [] as DataPoint[];

    const pts: DataPoint[] = [{ time: 0, elev: 0 }];
    let cumTime = 0;
    let cumElev = 0;
    for (const iv of intervals) {
      const rate = vertRate(iv.speed, iv.incline);
      cumTime += iv.duration;
      cumElev += rate * iv.duration;
      pts.push({ time: cumTime, elev: cumElev });
    }
    return pts;
  }, [pgm.program?.intervals, pgm.totalDuration]);

  /* ─── Actual cumulative elevation (sampled from session) ─── */
  const [actual, setActual] = useState<DataPoint[]>([{ time: 0, elev: 0 }]);
  const prevActive = useRef(false);
  const lastSample = useRef(0);

  useEffect(() => {
    if (session.active && !prevActive.current) {
      setActual([{ time: 0, elev: 0 }]);
      lastSample.current = 0;
    }
    prevActive.current = session.active;
    if (!session.active) return;
    if (session.elapsed - lastSample.current < 0.8) return;
    lastSample.current = session.elapsed;
    setActual(h => [...h, { time: session.elapsed, elev: session.vertFeet }]);
  }, [session.elapsed, session.vertFeet, session.active]);

  /* ─── Derived values ─── */
  const plannedMax = planned.length > 0 ? planned[planned.length - 1].elev : 0;
  const actualMax = actual.reduce((m, p) => Math.max(m, p.elev), 0);
  const totalDur = pgm.totalDuration || 1;
  const maxTime = Math.max(totalDur, actual[actual.length - 1]?.time ?? 0);
  const yMax = niceElevCeil(Math.max(plannedMax, actualMax, 5));
  const yTicks = elevTickValues(yMax);
  const xTicks = computeTimeTicks(maxTime);

  // Coordinate transforms
  const toX = (t: number) => (t / maxTime) * W;
  const toY = (elev: number) => H - PAD - (elev / yMax) * (H - PAD * 2);
  const toAbsY = (elev: number) => MT + toY(elev);

  // Build planned path (full program outline + fill)
  const plannedRender = downsample(planned, MAX_RENDER_PTS);
  let plannedOutline = '';
  let plannedTerrain = '';
  if (plannedRender.length > 1) {
    plannedOutline = `M${toX(plannedRender[0].time)},${toY(plannedRender[0].elev)}`;
    for (let i = 1; i < plannedRender.length; i++) {
      plannedOutline += ` L${toX(plannedRender[i].time)},${toY(plannedRender[i].elev)}`;
    }
    const lastX = toX(plannedRender[plannedRender.length - 1].time);
    plannedTerrain = plannedOutline + ` L${lastX},${H} L0,${H} Z`;
  }

  // Build actual path
  const actualRender = downsample(actual, MAX_RENDER_PTS);
  let actualOutline = '';
  let actualTerrain = '';
  if (actualRender.length > 1) {
    actualOutline = `M${toX(actualRender[0].time)},${toY(actualRender[0].elev)}`;
    for (let i = 1; i < actualRender.length; i++) {
      actualOutline += ` L${toX(actualRender[i].time)},${toY(actualRender[i].elev)}`;
    }
    const lastX = toX(actualRender[actualRender.length - 1].time);
    actualTerrain = actualOutline + ` L${lastX},${H} L0,${H} Z`;
  }

  // Position dot at latest actual point
  const lastPt = actual[actual.length - 1] ?? { time: 0, elev: 0 };
  const dotLeft = ((ML + toX(lastPt.time)) / VB_W) * 100;
  const dotTop = ((MT + toY(lastPt.elev)) / VB_H) * 100;

  /* ─── Double-tap detection ─── */
  const lastTapTime = useRef(0);
  const lastTapSide = useRef<'left' | 'right' | null>(null);
  const singleTapTimer = useRef<ReturnType<typeof setTimeout>>();
  const [arrow, setArrow] = useState<'left' | 'right' | null>(null);
  const arrowTimer = useRef<ReturnType<typeof setTimeout>>();

  const showArrow = useCallback((dir: 'left' | 'right') => {
    clearTimeout(arrowTimer.current);
    setArrow(dir);
    arrowTimer.current = setTimeout(() => setArrow(null), 400);
  }, []);

  const handleTap = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (!pgm.running) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const relX = (e.clientX - rect.left) / rect.width;
    const side: 'left' | 'right' = relX > 0.5 ? 'right' : 'left';
    const now = Date.now();

    if (now - lastTapTime.current < DOUBLE_TAP_MS && lastTapSide.current === side) {
      clearTimeout(singleTapTimer.current);
      lastTapTime.current = 0;
      lastTapSide.current = null;
      showArrow(side);
      if (side === 'right') actions.skipInterval();
      else actions.prevInterval();
    } else {
      lastTapTime.current = now;
      lastTapSide.current = side;
      clearTimeout(singleTapTimer.current);
      singleTapTimer.current = setTimeout(() => {
        lastTapTime.current = 0;
        lastTapSide.current = null;
        onSingleTap?.();
      }, DOUBLE_TAP_MS);
    }
  }, [pgm.running, actions, onSingleTap, showArrow]);

  return (
    <div
      data-testid="mountain-view"
      onClick={handleTap}
      style={{ position: 'relative', width: '100%', height: '100%', cursor: pgm.running ? 'pointer' : 'default' }}
    >
      <svg viewBox={`0 0 ${VB_W} ${VB_H}`} preserveAspectRatio="none"
        style={{ display: 'block', width: '100%', height: '100%' }}>
        <defs>
          {/* Planned terrain: muted, ghostly */}
          <linearGradient id="mtn-planned" x1={ML} y1={MT + H} x2={ML} y2={MT}
            gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="rgba(62,48,32,0.25)" />
            <stop offset="50%" stopColor="rgba(72,85,50,0.15)" />
            <stop offset="100%" stopColor="rgba(90,130,85,0.08)" />
          </linearGradient>
          {/* Actual terrain: vivid earthy */}
          <linearGradient id="mtn-actual" x1={ML} y1={MT + H} x2={ML} y2={MT}
            gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="rgba(62,48,32,0.65)" />
            <stop offset="35%" stopColor="rgba(72,85,50,0.45)" />
            <stop offset="70%" stopColor="rgba(90,130,85,0.3)" />
            <stop offset="100%" stopColor="rgba(107,200,155,0.2)" />
          </linearGradient>
          {/* Sky ambient */}
          <linearGradient id="mtn-sky" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="rgba(55,70,90,0.12)" />
            <stop offset="100%" stopColor="rgba(30,29,27,0)" />
          </linearGradient>
        </defs>

        {/* Sky background */}
        <rect x={ML} y={MT} width={W} height={H} fill="url(#mtn-sky)" />

        {/* Axis lines */}
        <line x1={ML} y1={MT} x2={ML} y2={MT + H}
          stroke="rgba(232,228,223,0.2)" strokeWidth="1" />
        <line x1={ML} y1={MT + H} x2={ML + W} y2={MT + H}
          stroke="rgba(232,228,223,0.2)" strokeWidth="1" />

        {/* Y-axis grid + tick marks */}
        {yTicks.map(e => (
          <React.Fragment key={e}>
            <line x1={ML} y1={toAbsY(e)} x2={ML + W} y2={toAbsY(e)}
              stroke="rgba(232,228,223,0.08)" strokeWidth="0.5" strokeDasharray="3,4" />
            <line x1={ML - TICK} y1={toAbsY(e)} x2={ML} y2={toAbsY(e)}
              stroke="rgba(232,228,223,0.25)" strokeWidth="1" />
          </React.Fragment>
        ))}

        {/* X-axis grid + tick marks */}
        {xTicks.map(({ sec, label }) => {
          const x = ML + toX(sec);
          return (
            <React.Fragment key={label}>
              <line x1={x} y1={MT} x2={x} y2={MT + H}
                stroke="rgba(232,228,223,0.06)" strokeWidth="0.5" strokeDasharray="3,4" />
              <line x1={x} y1={MT + H} x2={x} y2={MT + H + TICK}
                stroke="rgba(232,228,223,0.25)" strokeWidth="1" />
            </React.Fragment>
          );
        })}

        {/* Planned terrain (background — full program) */}
        <g transform={`translate(${ML},${MT})`}>
          {plannedTerrain && <path d={plannedTerrain} fill="url(#mtn-planned)" />}
          {plannedOutline && (
            <path d={plannedOutline} fill="none" stroke="rgba(232,228,223,0.15)" strokeWidth="1"
              strokeLinejoin="round" strokeLinecap="round" strokeDasharray="4,3" />
          )}
        </g>

        {/* Actual terrain (foreground — what you've achieved) */}
        <g transform={`translate(${ML},${MT})`}>
          {actualTerrain && <path d={actualTerrain} fill="url(#mtn-actual)" />}
          {actualOutline && (
            <>
              <path d={actualOutline} fill="none" stroke="rgba(107,200,155,0.12)" strokeWidth="4"
                strokeLinejoin="round" strokeLinecap="round" />
              <path d={actualOutline} fill="none" stroke="rgba(107,200,155,0.55)" strokeWidth="1.5"
                strokeLinejoin="round" strokeLinecap="round" />
            </>
          )}
        </g>
      </svg>

      {/* Y-axis elevation labels */}
      {yTicks.map(e => (
        <div key={e} style={{
          ...labelStyle,
          left: 0,
          width: `${((ML - TICK - 1) / VB_W) * 100}%`,
          top: `${(toAbsY(e) / VB_H) * 100}%`,
          transform: 'translateY(-50%)',
          textAlign: 'right',
        }}>
          {fmtElev(e)}
        </div>
      ))}

      {/* X-axis time labels */}
      {xTicks.map(({ sec, label }) => (
        <div key={label} style={{
          ...labelStyle,
          left: `${((ML + toX(sec)) / VB_W) * 100}%`,
          top: `${((MT + H + TICK + 1) / VB_H) * 100}%`,
          transform: 'translateX(-50%)',
        }}>
          {label}
        </div>
      ))}

      {/* Elevation badge */}
      <div style={{
        position: 'absolute', top: 6, right: 8,
        fontSize: 11, fontWeight: 600, color: 'var(--green)',
        background: 'rgba(30,29,27,0.6)',
        padding: '2px 8px', borderRadius: 4,
        pointerEvents: 'none',
      }}>
        {Math.round(lastPt.elev)} ft
      </div>

      {/* Double-tap arrow indicator */}
      {arrow && (
        <div key={Date.now()} style={{
          ...arrowStyle,
          ...(arrow === 'right' ? { right: '25%' } : { left: '25%' }),
        }}>
          {arrow === 'right' ? '\u00bb' : '\u00ab'}
        </div>
      )}

      {/* Position dot at actual elevation */}
      <div style={{
        position: 'absolute',
        left: `${dotLeft}%`,
        top: `${dotTop}%`,
        width: 10, height: 10, borderRadius: '50%',
        background: 'var(--green)',
        border: '1.5px solid var(--text)',
        transform: 'translate(-50%, -50%)',
        boxShadow: '0 0 6px rgba(232,228,223,0.6), 0 0 10px rgba(107,200,155,0.3)',
        pointerEvents: 'none', zIndex: 1,
      }} />
    </div>
  );
});

export default MountainView;
