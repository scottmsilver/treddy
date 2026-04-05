import React, { useState, useEffect, useRef } from 'react';
import { useLocation } from 'wouter';
import * as api from '../state/api';
import type { Profile } from '../state/types';
import { haptic } from '../utils/haptics';

export const AVATAR_COLORS = ['#d4c4a8', '#b8c9d4', '#c9b8b0', '#b0c9b8', '#c4b8d4'];

function initialsFrom(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  return name.slice(0, 2).toUpperCase();
}

// --- Avatar circle (reused across the app) ---

export function AvatarCircle({ profile, size = 80, fontSize }: { profile: Profile; size?: number; fontSize?: number }) {
  const fs = fontSize ?? Math.round(size * 0.35);
  if (profile.has_avatar) {
    return (
      <img
        src={api.avatarUrl(profile.id)}
        alt={profile.name}
        style={{
          width: size, height: size, borderRadius: '50%',
          objectFit: 'cover', display: 'block',
        }}
      />
    );
  }
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: profile.color || AVATAR_COLORS[0],
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: fs, fontWeight: 700, color: '#1E1D1B',
      flexShrink: 0,
    }}>
      {profile.initials || initialsFrom(profile.name)}
    </div>
  );
}

// --- Create profile form ---

export function CreateForm({ onCreated, onCancel }: { onCreated: (p: Profile) => void; onCancel: () => void }) {
  const [name, setName] = useState('');
  const [color, setColor] = useState(AVATAR_COLORS[0]);
  const [saving, setSaving] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { inputRef.current?.focus(); }, []);

  const submit = async () => {
    const trimmed = name.trim();
    if (!trimmed || saving) return;
    setSaving(true);
    try {
      const p = await api.createProfile({ name: trimmed, color });
      haptic(25);
      onCreated(p);
    } catch {
      setSaving(false);
    }
  };

  return (
    <div style={{
      background: 'var(--card)', borderRadius: 'var(--r-lg)',
      padding: 20, width: '100%', maxWidth: 320,
    }}>
      <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text)', marginBottom: 16 }}>
        New Profile
      </div>
      <input
        ref={inputRef}
        type="text"
        placeholder="Name"
        value={name}
        onChange={e => setName(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter') submit(); }}
        maxLength={30}
        style={{
          width: '100%', height: 44, borderRadius: 'var(--r-sm)',
          border: 'none', background: 'var(--fill2)',
          color: 'var(--text)', fontSize: 16, fontWeight: 500,
          padding: '0 12px', fontFamily: 'inherit',
          marginBottom: 16,
        }}
      />

      {/* Color picker */}
      <div style={{ display: 'flex', gap: 12, marginBottom: 20, justifyContent: 'center' }}>
        {AVATAR_COLORS.map(c => (
          <button
            key={c}
            onClick={() => { setColor(c); haptic(15); }}
            style={{
              width: 36, height: 36, borderRadius: '50%',
              background: c, border: color === c ? '3px solid var(--text)' : '3px solid transparent',
              cursor: 'pointer', padding: 0,
              transition: 'border 150ms var(--ease)',
              WebkitTapHighlightColor: 'transparent',
            }}
          />
        ))}
      </div>

      <div style={{ display: 'flex', gap: 8 }}>
        <button
          onClick={onCancel}
          style={{
            flex: 1, height: 44, borderRadius: 'var(--r-sm)',
            border: 'none', background: 'var(--fill)',
            color: 'var(--text2)', fontSize: 15, fontWeight: 600,
            fontFamily: 'inherit', cursor: 'pointer',
            WebkitTapHighlightColor: 'transparent',
          }}
        >Cancel</button>
        <button
          onClick={submit}
          disabled={!name.trim() || saving}
          style={{
            flex: 1, height: 44, borderRadius: 'var(--r-sm)',
            border: 'none',
            background: name.trim() ? 'var(--green)' : 'var(--fill)',
            color: name.trim() ? '#000' : 'var(--text3)',
            fontSize: 15, fontWeight: 700,
            fontFamily: 'inherit', cursor: name.trim() ? 'pointer' : 'default',
            WebkitTapHighlightColor: 'transparent',
            transition: 'all 150ms var(--ease)',
          }}
        >Create</button>
      </div>
    </div>
  );
}

// --- Main picker ---

export default function ProfilePicker(): React.ReactElement {
  const [, setLocation] = useLocation();
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);

  useEffect(() => {
    api.getProfiles().then(p => { setProfiles(p); setLoading(false); }).catch(() => setLoading(false));
  }, []);

  const handleSelect = async (id: string) => {
    haptic(25);
    try {
      await api.selectProfile(id);
      setLocation('/');
    } catch { /* toast? */ }
  };

  const handleGuest = async () => {
    haptic(25);
    try {
      await api.startGuest();
      setLocation('/');
    } catch { /* toast? */ }
  };

  const handleCreated = async (p: Profile) => {
    setShowCreate(false);
    setProfiles(prev => [...prev, p]);
    try {
      await api.selectProfile(p.id);
      setLocation('/');
    } catch { /* fallback */ }
  };

  if (loading) {
    return (
      <div style={{
        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--text3)', fontSize: 14,
      }}>
        Loading...
      </div>
    );
  }

  if (showCreate) {
    return (
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center',
        justifyContent: 'center', padding: 24,
      }}>
        <CreateForm
          onCreated={handleCreated}
          onCancel={() => setShowCreate(false)}
        />
      </div>
    );
  }

  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      justifyContent: 'center', padding: '24px 0',
    }}>
      {/* Header */}
      <div style={{
        textAlign: 'center', marginBottom: 32,
        padding: '0 24px',
      }}>
        <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)' }}>
          Who's running today?
        </div>
      </div>

      {/* Horizontal scroll of profile circles */}
      <div style={{
        overflowX: 'auto',
        WebkitOverflowScrolling: 'touch',
        scrollbarWidth: 'none',
        paddingLeft: 24,
        paddingRight: 0,  /* half-cut-off signals scrollability */
      }} className="profile-scroll">
        <div style={{
          display: 'flex', gap: 24,
          paddingRight: 40, /* room for the half-visible last item */
        }}>
          {/* Existing profiles */}
          {profiles.map(p => (
            <button
              key={p.id}
              onClick={() => handleSelect(p.id)}
              style={{
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                gap: 8, background: 'none', border: 'none', cursor: 'pointer',
                padding: 0, minWidth: 80,
                WebkitTapHighlightColor: 'transparent',
              }}
            >
              <AvatarCircle profile={p} size={80} />
              <span style={{
                fontSize: 13, fontWeight: 600, color: 'var(--text)',
                maxWidth: 80, overflow: 'hidden', textOverflow: 'ellipsis',
                whiteSpace: 'nowrap', fontFamily: 'inherit',
              }}>
                {p.name}
              </span>
            </button>
          ))}

          {/* Guest */}
          <button
            onClick={handleGuest}
            style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center',
              gap: 8, background: 'none', border: 'none', cursor: 'pointer',
              padding: 0, minWidth: 80,
              WebkitTapHighlightColor: 'transparent',
            }}
          >
            <div style={{
              width: 80, height: 80, borderRadius: '50%',
              background: 'linear-gradient(135deg, #e8e4df 0%, #d4c4a8 100%)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 32,
            }}>
              👋
            </div>
            <span style={{
              fontSize: 13, fontWeight: 600, color: 'var(--text2)',
              fontFamily: 'inherit',
            }}>
              Guest
            </span>
            <span style={{
              fontSize: 11, color: 'var(--text3)', marginTop: -4,
            }}>
              Jump right in
            </span>
          </button>

          {/* Add profile */}
          <button
            onClick={() => { setShowCreate(true); haptic(25); }}
            style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center',
              gap: 8, background: 'none', border: 'none', cursor: 'pointer',
              padding: 0, minWidth: 80,
              WebkitTapHighlightColor: 'transparent',
            }}
          >
            <div style={{
              width: 80, height: 80, borderRadius: '50%',
              border: '2px dashed var(--text3)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 28, fontWeight: 300, color: 'var(--text3)',
            }}>
              +
            </div>
            <span style={{
              fontSize: 13, fontWeight: 600, color: 'var(--text3)',
              fontFamily: 'inherit',
            }}>
              Add
            </span>
          </button>
        </div>
      </div>

      {/* Hide scrollbar via inline style tag */}
      <style>{`.profile-scroll::-webkit-scrollbar { display: none; }`}</style>
    </div>
  );
}
