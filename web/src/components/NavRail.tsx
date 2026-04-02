import React, { useState, useEffect } from 'react';
import { useLocation } from 'wouter';
import { useTreadmillState } from '../state/TreadmillContext';
import { haptic } from '../utils/haptics';
import { HomeIcon, MicIcon } from './shared';
type VoiceState = 'idle' | 'connecting' | 'listening' | 'speaking';

function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const mql = window.matchMedia(query);
    const handler = (e: MediaQueryListEvent) => setMatches(e.matches);
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, [query]);
  return matches;
}

export function useIsLandscape(): boolean {
  return useMediaQuery('(orientation: landscape) and (min-width: 768px)');
}

interface NavRailProps {
  voiceState: VoiceState;
  onVoiceToggle: () => void;
  onSettingsToggle: () => void;
}

function NavItem({ icon, label, active, onClick, dot, color, grow, hideLabel }: {
  icon: React.ReactNode;
  label: string;
  active: boolean;
  onClick: () => void;
  dot?: 'green' | 'red';
  color?: string;
  grow?: boolean;
  hideLabel?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      style={{
        flex: grow ? 1 : 'none',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: hideLabel ? 0 : 2,
        background: 'none',
        border: 'none',
        color: color || (active ? 'var(--text)' : 'var(--text3)'),
        cursor: 'pointer',
        WebkitTapHighlightColor: 'transparent',
        fontFamily: 'inherit',
        padding: grow ? 0 : '10px 0',
        position: 'relative',
        minHeight: 44,
      }}
    >
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {icon}
        {dot && (
          <div style={{
            position: 'absolute',
            top: -1,
            right: -4,
            width: 6,
            height: 6,
            borderRadius: '50%',
            background: dot === 'green' ? 'var(--green)' : 'var(--red)',
          }} />
        )}
      </div>
      {!hideLabel && (
        <span className="nav-label" style={{ fontSize: 10, fontWeight: 500, lineHeight: 1 }}>{label}</span>
      )}
    </button>
  );
}

function RunIcon() {
  return (
    <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
    </svg>
  );
}

function SettingsIcon() {
  return (
    <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

export default function NavRail({ voiceState, onVoiceToggle, onSettingsToggle }: NavRailProps): React.ReactElement {
  const { wsConnected } = useTreadmillState();
  const [location, setLocation] = useLocation();
  const isLandscape = useIsLandscape();

  const voiceActive = voiceState === 'connecting' || voiceState === 'listening' || voiceState === 'speaking';
  const isHome = location === '/' || location === '';
  const isRun = location.startsWith('/run');
  const voiceColor = voiceActive
    ? (voiceState === 'connecting' ? 'var(--yellow)' : voiceState === 'listening' ? 'var(--green)' : 'var(--purple)')
    : undefined;

  const grow = !isLandscape;
  const hideLabel = isLandscape;

  const navItems = (
    <>
      <NavItem
        grow={grow}
        hideLabel={hideLabel}
        icon={<HomeIcon size={22} />}
        label="Home"
        active={isHome}
        dot={wsConnected ? 'green' : 'red'}
        onClick={() => { setLocation('/'); haptic(15); }}
      />
      <NavItem
        grow={grow}
        hideLabel={hideLabel}
        icon={<RunIcon />}
        label="Run"
        active={isRun}
        onClick={() => { setLocation('/run'); haptic(15); }}
      />
      <NavItem
        grow={grow}
        hideLabel={hideLabel}
        icon={<MicIcon size={22} />}
        label={voiceActive ? (voiceState === 'connecting' ? 'Connecting...' : voiceState === 'listening' ? 'Listening' : 'Speaking') : 'Voice'}
        active={voiceActive}
        color={voiceColor}
        onClick={() => { haptic(voiceState === 'idle' ? 20 : 10); onVoiceToggle(); }}
      />
      <NavItem
        grow={grow}
        hideLabel={hideLabel}
        icon={<SettingsIcon />}
        label="Settings"
        active={false}
        onClick={() => { onSettingsToggle(); haptic(15); }}
      />
    </>
  );

  if (isLandscape) {
    return (
      <nav style={{
        position: 'fixed',
        left: 0, top: 0, bottom: 0,
        width: 'calc(56px + env(safe-area-inset-left, 0px))',
        zIndex: 100,
        background: 'var(--card)',
        borderRight: '1px solid var(--separator)',
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        gap: 4,
        paddingLeft: 'env(safe-area-inset-left, 0px)',
      }}>
        {navItems}
      </nav>
    );
  }

  return (
    <nav style={{
      position: 'fixed',
      bottom: 0, left: 0, right: 0,
      zIndex: 100,
      background: 'var(--card)',
      borderTop: '1px solid var(--separator)',
      paddingBottom: 'env(safe-area-inset-bottom, 0px)',
    }}>
      <div style={{ display: 'flex', height: 56 }}>
        {navItems}
      </div>
    </nav>
  );
}
