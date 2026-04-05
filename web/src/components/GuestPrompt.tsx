import React, { useState } from 'react';
import { CreateForm } from './ProfilePicker';
import type { Profile } from '../state/types';
import * as api from '../state/api';

interface GuestPromptProps {
  visible: boolean;
  onDismiss: () => void;
}

/**
 * Modal shown after a guest session ends.
 * Offers to convert the guest session into a real profile.
 */
export default function GuestPrompt({ visible, onDismiss }: GuestPromptProps): React.ReactElement | null {
  const [showForm, setShowForm] = useState(false);

  if (!visible) return null;

  const handleCreated = async (p: Profile) => {
    // Select the newly created profile
    try { await api.selectProfile(p.id); } catch { /* ok */ }
    onDismiss();
  };

  return (
    <>
      {/* Backdrop */}
      <div
        onClick={onDismiss}
        style={{
          position: 'fixed', inset: 0, zIndex: 400,
          background: 'rgba(18,18,16,0.7)',
          backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)',
        }}
      />

      {/* Modal content */}
      <div style={{
        position: 'fixed', zIndex: 401,
        top: '50%', left: '50%',
        transform: 'translate(-50%, -50%)',
        width: 'min(360px, 90vw)',
        display: 'flex', flexDirection: 'column', alignItems: 'center',
      }}>
        {showForm ? (
          <CreateForm
            onCreated={handleCreated}
            onCancel={() => setShowForm(false)}
          />
        ) : (
          <div style={{
            background: 'var(--card)', borderRadius: 'var(--r-lg)',
            padding: '28px 24px', textAlign: 'center',
            width: '100%',
          }}>
            <div style={{ fontSize: 18, fontWeight: 700, color: 'var(--text)', marginBottom: 8 }}>
              Nice run!
            </div>
            <div style={{ fontSize: 14, color: 'var(--text2)', marginBottom: 24, lineHeight: 1.5 }}>
              Create a profile to save your workout history and personal settings.
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <button
                onClick={() => setShowForm(true)}
                style={{
                  height: 48, borderRadius: 'var(--r-sm)',
                  border: 'none', background: 'var(--green)',
                  color: '#000', fontSize: 16, fontWeight: 700,
                  fontFamily: 'inherit', cursor: 'pointer',
                  WebkitTapHighlightColor: 'transparent',
                }}
              >
                Create Profile
              </button>
              <button
                onClick={onDismiss}
                style={{
                  height: 44, borderRadius: 'var(--r-sm)',
                  border: 'none', background: 'transparent',
                  color: 'var(--text3)', fontSize: 14, fontWeight: 500,
                  fontFamily: 'inherit', cursor: 'pointer',
                  WebkitTapHighlightColor: 'transparent',
                }}
              >
                Skip
              </button>
            </div>
          </div>
        )}
      </div>
    </>
  );
}
