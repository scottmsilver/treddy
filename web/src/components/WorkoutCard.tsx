import type React from 'react';
import type { SavedWorkout } from '../state/types';
import { fmtDur } from '../utils/formatters';
import { haptic } from '../utils/haptics';

interface WorkoutCardProps {
  workout: SavedWorkout;
  onLoad: (id: string) => void;
  onDelete: (id: string) => void;
  onRename: (id: string, name: string) => void;
}

export default function WorkoutCard({ workout, onLoad, onDelete, onRename }: WorkoutCardProps): React.ReactElement {
  const intervals = workout.program?.intervals?.length || 0;
  const duration = fmtDur(
    workout.program?.intervals?.reduce((s, i) => s + i.duration, 0) ?? 0
  );
  const usageText = workout.usage_text || 'Never used';

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
      <div role="button" tabIndex={0} onClick={() => { onLoad(workout.id); }} style={{ flex: 1, minWidth: 0 }}>
        <div
          onClick={(e) => {
            e.stopPropagation();
            const newName = window.prompt('Rename workout', workout.name);
            if (newName && newName !== workout.name) {
              onRename(workout.id, newName);
              haptic(15);
            }
          }}
          style={{
            fontSize: 15, fontWeight: 600, marginBottom: 4,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}
        >{workout.name}</div>
        <div style={{ fontSize: 12, color: 'var(--text3)' }}>
          {duration} &middot; {intervals} interval{intervals !== 1 ? 's' : ''}
        </div>
        <div style={{ fontSize: 11, color: 'var(--text3)', marginTop: 2 }}>
          {usageText}
        </div>
      </div>
      <button
        aria-label={`Delete ${workout.name}`}
        onClick={(e) => { e.stopPropagation(); if (window.confirm(`Delete "${workout.name}"?`)) onDelete(workout.id); }}
        style={{
          fontSize: 16, color: 'var(--text3)', padding: '4px 8px',
          cursor: 'pointer', opacity: 0.6, marginLeft: 8, flexShrink: 0,
          background: 'none', border: 'none', fontFamily: 'inherit',
        }}
      >&times;</button>
    </div>
  );
}
