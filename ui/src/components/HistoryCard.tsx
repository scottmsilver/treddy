import type React from 'react';
import type { HistoryEntry } from '../state/types';
import { fmtDur } from '../utils/formatters';
import { haptic } from '../utils/haptics';

interface HistoryCardProps {
  entry: HistoryEntry;
  variant: 'lobby' | 'compact';
  onLoad: (id: string) => void;
  onResume?: (id: string) => void;
  onSave?: (id: string) => void;
}

export default function HistoryCard({ entry, variant, onLoad, onResume, onSave }: HistoryCardProps): React.ReactElement {
  const name = entry.program?.name || 'Workout';
  const intervals = entry.program?.intervals?.length || 0;
  const duration = fmtDur(entry.total_duration);
  const canResume = !entry.completed && (entry.last_elapsed ?? 0) > 0;
  const resumeLabel = canResume ? `Resume from ${fmtDur(entry.last_elapsed ?? 0)}` : null;

  if (variant === 'lobby') {
    return (
      <div
        style={{
          width: '100%', flexShrink: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          background: 'var(--card)', borderRadius: 'var(--r-md)', padding: 12,
          cursor: 'pointer', WebkitTapHighlightColor: 'transparent',
          transition: 'transform 100ms var(--ease), opacity 100ms var(--ease)',
        }}
      >
        <div onClick={() => { onLoad(entry.id); haptic(25); }} style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontSize: 15, fontWeight: 600, marginBottom: 4,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{name}{entry.completed ? ' \u2713' : ''}</div>
          <div style={{ fontSize: 12, color: 'var(--text3)' }}>
            {duration} &middot; {intervals} intervals
          </div>
        </div>
        {onSave && (
          <button
            aria-label={entry.saved ? 'Saved to My Workouts' : 'Save to My Workouts'}
            disabled={entry.saved}
            onClick={(e) => { e.stopPropagation(); if (!entry.saved) { onSave(entry.id); haptic(15); } }}
            style={{
              fontSize: 18, padding: '4px 6px', cursor: entry.saved ? 'default' : 'pointer',
              color: entry.saved ? 'var(--accent, #e07)' : 'var(--text3)',
              opacity: entry.saved ? 1 : 0.5, flexShrink: 0, lineHeight: 1,
              background: 'none', border: 'none', fontFamily: 'inherit',
            }}
          >{entry.saved ? '\u2764' : '\u2661'}</button>
        )}
        {canResume && onResume && (
          <button
            aria-label={`Resume ${name}`}
            onClick={(e) => { e.stopPropagation(); onResume(entry.id); haptic(25); }}
            style={{
              fontSize: 12, fontWeight: 600, color: 'var(--green)',
              padding: '4px 10px', borderRadius: 'var(--r-sm)',
              background: 'rgba(107,200,155,0.12)',
              whiteSpace: 'nowrap', marginLeft: 8,
              border: 'none', cursor: 'pointer', fontFamily: 'inherit',
            }}
          >{resumeLabel}</button>
        )}
      </div>
    );
  }

  // compact (horizontal scroll)
  return (
    <div
      onClick={() => { (canResume && onResume) ? onResume(entry.id) : onLoad(entry.id); haptic(25); }}
      style={{
        flexShrink: 0, width: 140, background: 'var(--card)',
        borderRadius: 'var(--r-md)', padding: 12, cursor: 'pointer',
        WebkitTapHighlightColor: 'transparent',
        transition: 'transform 100ms var(--ease), opacity 100ms var(--ease)',
      }}
    >
      <div style={{
        fontSize: 13, fontWeight: 600, marginBottom: 4,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{name}{entry.completed ? ' \u2713' : ''}</div>
      <div style={{ fontSize: 11, color: 'var(--text3)' }}>
        {canResume ? resumeLabel : `${duration} \u00b7 ${intervals} intervals`}
      </div>
    </div>
  );
}
