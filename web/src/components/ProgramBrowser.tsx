import React from 'react';
import WorkoutList from './WorkoutList';
import HistoryList from './HistoryList';

const sectionHeader: React.CSSProperties = {
  fontSize: 13, fontWeight: 600, color: 'var(--text3)',
  textTransform: 'uppercase' as const, letterSpacing: '0.02em',
  padding: '12px 16px 8px',
};

interface ProgramBrowserProps {
  variant: 'lobby' | 'compact';
  onAfterLoad?: () => void;
  onVoice?: (prompt?: string) => void;
}

export default function ProgramBrowser({ variant, onAfterLoad, onVoice }: ProgramBrowserProps): React.ReactElement | null {
  const [workoutListKey, setWorkoutListKey] = React.useState(0);
  const [historyListKey, setHistoryListKey] = React.useState(0);

  if (variant === 'compact') {
    return <HistoryList variant="compact" onAfterLoad={onAfterLoad} />;
  }

  return (
    <>
      <div style={sectionHeader}>My Workouts</div>
      <WorkoutList
        key={workoutListKey}
        onAfterLoad={onAfterLoad}
        onWorkoutDeleted={() => setHistoryListKey(k => k + 1)}
      />
      <div style={sectionHeader}>Your Programs</div>
      <HistoryList
        key={historyListKey}
        variant="lobby"
        onAfterLoad={onAfterLoad}
        onVoice={onVoice}
        onWorkoutSaved={() => setWorkoutListKey(k => k + 1)}
      />
    </>
  );
}
