import React from 'react';
import { useLocation } from 'wouter';
import { useTreadmillState } from '../state/TreadmillContext';
import { AvatarCircle } from './ProfilePicker';
import { haptic } from '../utils/haptics';

/**
 * Small circular avatar in the top-right corner of all pages.
 * Shows profile image or initials+color. Tap navigates to /profiles.
 * Hidden when already on /profiles.
 */
export default function ProfileAvatar(): React.ReactElement | null {
  const { activeProfile, guestMode } = useTreadmillState();
  const [location, setLocation] = useLocation();

  // Hidden on the profile picker page
  if (location === '/profiles') return null;

  // Nothing to show if no profile and not guest
  if (!activeProfile && !guestMode) return null;

  const handleTap = () => {
    haptic(15);
    setLocation('/profiles');
  };

  if (guestMode && !activeProfile) {
    return (
      <button
        onClick={handleTap}
        aria-label="Switch profile"
        style={{
          position: 'fixed', top: 12, right: 12, zIndex: 200,
          width: 36, height: 36, borderRadius: '50%',
          border: '1.5px dashed var(--text3)',
          background: 'rgba(30,29,27,0.8)',
          backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 16, fontWeight: 300, color: 'var(--text3)',
          cursor: 'pointer', padding: 0,
          WebkitTapHighlightColor: 'transparent',
        }}
      >
        ?
      </button>
    );
  }

  if (!activeProfile) return null;

  return (
    <button
      onClick={handleTap}
      aria-label="Switch profile"
      style={{
        position: 'fixed', top: 12, right: 12, zIndex: 200,
        width: 36, height: 36, borderRadius: '50%',
        border: 'none', padding: 0, cursor: 'pointer',
        background: 'none',
        boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
        WebkitTapHighlightColor: 'transparent',
      }}
    >
      <AvatarCircle profile={activeProfile} size={36} fontSize={13} />
    </button>
  );
}
