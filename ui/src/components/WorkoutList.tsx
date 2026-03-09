import React, { useState, useEffect, useCallback } from 'react';
import type { SavedWorkout } from '../state/types';
import * as api from '../state/api';
import { useToast } from '../state/TreadmillContext';
import { haptic } from '../utils/haptics';
import WorkoutCard from './WorkoutCard';

interface WorkoutListProps {
  onAfterLoad?: () => void;
  onWorkoutDeleted?: () => void;
}

export default function WorkoutList({ onAfterLoad, onWorkoutDeleted }: WorkoutListProps): React.ReactElement {
  const [workouts, setWorkouts] = useState<SavedWorkout[]>([]);
  const showToast = useToast();

  useEffect(() => {
    let stale = false;
    api.getWorkouts().then(w => { if (!stale) setWorkouts(w); }).catch(() => {});
    return () => { stale = true; };
  }, []);

  const handleLoad = useCallback(async (id: string) => {
    try {
      const res = await api.loadWorkout(id);
      if (res?.ok && res.program) {
        haptic(25);
        onAfterLoad?.();
      }
    } catch (_e) {
      showToast('Failed to load workout');
    }
  }, [showToast, onAfterLoad]);

  const handleDelete = useCallback(async (id: string) => {
    try {
      await api.deleteWorkout(id);
      setWorkouts(prev => prev.filter(w => w.id !== id));
      onWorkoutDeleted?.();
      haptic(15);
    } catch (_e) {
      showToast('Failed to delete workout');
    }
  }, [showToast, onWorkoutDeleted]);

  const handleRename = useCallback(async (id: string, name: string) => {
    try {
      await api.renameWorkout(id, name);
      setWorkouts(prev => prev.map(w => w.id === id ? { ...w, name } : w));
    } catch (_e) {
      showToast('Failed to rename workout');
    }
  }, [showToast]);

  if (workouts.length === 0) {
    return (
      <div style={{ padding: '0 16px' }}>
        <div style={{ fontSize: 13, color: 'var(--text3)', padding: '8px 0', textAlign: 'center' }}>
          Save your favorite workouts with the &#9825; icon
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, padding: '0 16px' }}>
      {workouts.map(w => (
        <WorkoutCard
          key={w.id}
          workout={w}
          onLoad={handleLoad}
          onDelete={handleDelete}
          onRename={handleRename}
        />
      ))}
    </div>
  );
}
