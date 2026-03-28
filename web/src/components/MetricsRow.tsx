import type React from 'react';
import { motion } from 'motion/react';
import { useSession } from '../state/useSession';
import { timerJsx } from '../utils/formatters';
import HeartRate from './HeartRate';

const valStyle: React.CSSProperties = {
  fontSize: 15, fontWeight: 600,
  fontVariantNumeric: 'tabular-nums',
  display: 'inline-block', textAlign: 'right', minWidth: '5ch',
};

const unitStyle: React.CSSProperties = { fontSize: 10, color: 'var(--text3)' };

const cellStyle: React.CSSProperties = { display: 'flex', alignItems: 'baseline', gap: 4 };

export default function MetricsRow(): React.ReactElement {
  const sess = useSession();

  return (
    <motion.div
      className="metrics-ro"
      animate={{ height: sess.active ? 'auto' : 0, opacity: sess.active ? 1 : 0 }}
      transition={{ type: 'spring', stiffness: 400, damping: 28 }}
      style={{
        overflow: 'hidden',
        display: 'flex', justifyContent: 'center', gap: 20,
        padding: '0 16px 4px', flexShrink: 0,
      }}
    >
      <div style={cellStyle}>
        <span className="metric-value font-timer" style={{ ...valStyle, color: 'var(--teal)' }}>{timerJsx(sess.pace)}</span>
        <span className="metric-label" style={unitStyle}>min/mi</span>
      </div>
      <div style={cellStyle}>
        <span className="metric-value" style={valStyle}>{sess.distDisplay}</span>
        <span className="metric-label" style={unitStyle}>miles</span>
      </div>
      <div style={cellStyle}>
        <span className="metric-value" style={{ ...valStyle, color: 'var(--orange)' }}>{sess.vertDisplay}</span>
        <span className="metric-label" style={unitStyle}>vert ft</span>
      </div>
      <div style={cellStyle}>
        <span className="metric-value" style={valStyle}>{sess.caloriesDisplay}</span>
        <span className="metric-label" style={unitStyle}>cal</span>
      </div>
      <HeartRate />
    </motion.div>
  );
}
