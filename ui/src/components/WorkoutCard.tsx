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

function relativeTime(dateStr: string | null): string {
  if (!dateStr) return '';
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days === 1) return 'yesterday';
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  return `${months}mo ago`;
}

export default function WorkoutCard({ workout, onLoad, onDelete, onRename }: WorkoutCardProps): React.ReactElement {
  const intervals = workout.program?.intervals?.length || 0;
  const duration = fmtDur(
    workout.program?.intervals?.reduce((s, i) => s + i.duration, 0) ?? 0
  );

  const usageText = workout.times_used > 0
    ? `Used ${workout.times_used} time${workout.times_used !== 1 ? 's' : ''}${workout.last_used ? ' \u00b7 last ' + relativeTime(workout.last_used) : ''}`
    : 'Never used';

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
      <div onClick={() => { onLoad(workout.id); haptic(25); }} style={{ flex: 1, minWidth: 0 }}>
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
        onClick={(e) => { e.stopPropagation(); onDelete(workout.id); haptic(15); }}
        style={{
          fontSize: 16, color: 'var(--text3)', padding: '4px 8px',
          cursor: 'pointer', opacity: 0.6, marginLeft: 8, flexShrink: 0,
          background: 'none', border: 'none', fontFamily: 'inherit',
        }}
      >&times;</button>
    </div>
  );
}
