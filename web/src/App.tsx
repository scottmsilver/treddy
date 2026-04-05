import React, { useState, useCallback, useRef, useEffect } from 'react';
import ErrorBoundary from './components/ErrorBoundary';
import NavRail, { useIsLandscape } from './components/NavRail';
import Toast from './components/Toast';
import DisconnectBanner from './components/DisconnectBanner';
import SettingsPanel from './components/SettingsPanel';
import VoiceOverlay from './components/VoiceOverlay';
import GuestPrompt from './components/GuestPrompt';
import { ToastContext, registerToast, useTreadmillState } from './state/TreadmillContext';
import { useVoiceContext } from './state/VoiceContext';

function useWakeLock() {
  const wakeLock = useRef<WakeLockSentinel | null>(null);

  useEffect(() => {
    if (!('wakeLock' in navigator)) return;

    const request = async () => {
      try {
        wakeLock.current = await navigator.wakeLock.request('screen');
      } catch { /* user denied or not supported */ }
    };

    request();

    // Re-acquire on tab focus (wake lock is released when tab is hidden)
    const onVisibility = () => {
      if (document.visibilityState === 'visible') request();
    };
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      document.removeEventListener('visibilitychange', onVisibility);
      wakeLock.current?.release();
    };
  }, []);
}

export default function App({ children }: { children: React.ReactNode }) {
  const [toastMsg, setToastMsg] = useState('');
  const [toastVisible, setToastVisible] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [guestPromptVisible, setGuestPromptVisible] = useState(false);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const { voiceState, toggle: toggleVoice } = useVoiceContext();
  const isLandscape = useIsLandscape();
  const { session, guestMode } = useTreadmillState();
  const prevSessionActive = useRef(session.active);

  useWakeLock();

  // Show guest prompt when a guest session ends
  useEffect(() => {
    if (prevSessionActive.current && !session.active && guestMode && session.endReason) {
      setGuestPromptVisible(true);
    }
    prevSessionActive.current = session.active;
  }, [session.active, session.endReason, guestMode]);

  const showToast = useCallback((message: string) => {
    setToastMsg(message);
    setToastVisible(true);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToastVisible(false), 8000);
  }, []);

  // Wire up the module-level toast ref so TreadmillProvider's WebSocket
  // handler (encouragement, session-end warnings) can show toasts
  useEffect(() => {
    registerToast(showToast);
    return () => clearTimeout(toastTimer.current);
  }, [showToast]);

  return (
    <ErrorBoundary>
      <ToastContext.Provider value={showToast}>
        <DisconnectBanner />
        <div style={{
          flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden',
          paddingBottom: isLandscape ? 0 : 56,
          paddingLeft: isLandscape ? 'calc(56px + env(safe-area-inset-left, 0px))' : 0,
        }}>
          {children}
        </div>
        <NavRail
          voiceState={voiceState}
          onVoiceToggle={toggleVoice}
          onSettingsToggle={() => setSettingsOpen(s => !s)}
        />
        <VoiceOverlay voiceState={voiceState} />
        <Toast message={toastMsg} visible={toastVisible} />
        <SettingsPanel open={settingsOpen} onClose={() => setSettingsOpen(false)} />
        <GuestPrompt visible={guestPromptVisible} onDismiss={() => setGuestPromptVisible(false)} />
      </ToastContext.Provider>
    </ErrorBoundary>
  );
}
