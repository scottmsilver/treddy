import React, { useState, useRef, useCallback, useEffect } from 'react';
import { useLocation } from 'wouter';
import { useTreadmillState, useTreadmillActions, useToast } from '../state/TreadmillContext';
import * as api from '../state/api';
import { haptic } from '../utils/haptics';
import { hrColor } from '../utils/hrColor';
import { AvatarCircle, AVATAR_COLORS } from './ProfilePicker';
import type { Profile } from '../state/types';

interface SettingsPanelProps {
  open: boolean;
  onClose: () => void;
}

const rowStyle: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
  height: 48, padding: '0 4px',
  borderBottom: '1px solid var(--separator)',
  cursor: 'pointer',
  WebkitTapHighlightColor: 'transparent',
};

export default function SettingsPanel({ open, onClose }: SettingsPanelProps): React.ReactElement | null {
  const { status, hrmDevices, activeProfile } = useTreadmillState();
  const actions = useTreadmillActions();
  const showToast = useToast();
  const [debugUnlocked, setDebugUnlocked] = useState(false);
  const [smartass, setSmartass] = useState(() => {
    try { return localStorage.getItem('smartass_mode') === 'true'; } catch { return false; }
  });
  const [mountainView, setMountainView] = useState(() => {
    try { return localStorage.getItem('mountain_view') === 'true'; } catch { return false; }
  });
  const [hrmScanning, setHrmScanning] = useState(false);
  const [weightLbs, setWeightLbs] = useState<number | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const avatarInputRef = useRef<HTMLInputElement>(null);
  const debugTaps = useRef<number[]>([]);
  const [, setLocation] = useLocation();

  // Profile editing state
  const [editingName, setEditingName] = useState(false);
  const [profileName, setProfileName] = useState('');
  const [profileColor, setProfileColor] = useState('');
  const [localProfile, setLocalProfile] = useState<Profile | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const nameInputRef = useRef<HTMLInputElement>(null);

  // Sync profile state when panel OPENS (not on every activeProfile change)
  const prevOpen = useRef(false);
  useEffect(() => {
    if (open && !prevOpen.current) {
      // Panel just opened — sync from context
      api.getUser().then(u => setWeightLbs(u.weight_lbs)).catch(() => {});
      if (activeProfile) {
        setProfileName(activeProfile.name);
        setProfileColor(activeProfile.color);
        setLocalProfile(activeProfile);
      }
      setConfirmDelete(false);
      setEditingName(false);
    }
    prevOpen.current = open;
  }, [open]); // intentionally omit activeProfile — don't reset mid-edit

  // Reset debug unlock when panel closes
  useEffect(() => {
    if (!open) setDebugUnlocked(false);
  }, [open]);

  const handleHeaderTap = useCallback(() => {
    const now = Date.now();
    debugTaps.current.push(now);
    debugTaps.current = debugTaps.current.filter(t => now - t < 500);
    if (debugTaps.current.length >= 3) {
      debugTaps.current = [];
      setDebugUnlocked(true);
      haptic(50);
    }
  }, []);

  if (!open) return null;

  const handleGpxUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const data = await api.uploadGpx(file);
      if (data.ok && data.program) {
        const name = (data.program as { name?: string }).name || 'Route';
        showToast(`Loaded GPX route "${name}". Tap Start to begin!`);
        haptic(25);
        onClose();
      } else {
        showToast('GPX upload failed: ' + (data.error || 'unknown error'));
      }
    } catch (err) {
      showToast('GPX upload failed: ' + (err instanceof Error ? err.message : 'unknown error'));
    }
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  return (
    <>
      {/* Overlay */}
      <div
        onClick={onClose}
        style={{
          position: 'fixed', inset: 0, zIndex: 300,
          background: 'rgba(18,18,16,0.6)',
          backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
        }}
      />

      {/* Panel */}
      <div style={{
        position: 'fixed', top: 0, right: 0, bottom: 0, zIndex: 301,
        width: 'min(320px, 85vw)', background: '#1E1D1B',
        borderRadius: 'var(--r-xl) 0 0 var(--r-xl)',
        padding: '24px 16px', overflowY: 'auto',
      }}>
        {/* Header — triple-tap unlocks debug */}
        <h2
          onClick={handleHeaderTap}
          style={{
            fontSize: 18, fontWeight: 700, color: 'var(--text)',
            margin: '0 0 20px', cursor: 'default',
            WebkitTapHighlightColor: 'transparent',
            userSelect: 'none',
          }}
        >
          Settings
        </h2>

        {/* Profile Section */}
        {localProfile && (
          <div style={{ marginBottom: 20 }}>
            {/* Avatar + Name */}
            <div style={{
              display: 'flex', alignItems: 'center', gap: 14,
              padding: '8px 4px 16px',
            }}>
              <div style={{ position: 'relative', flexShrink: 0 }}>
                <AvatarCircle profile={{ ...localProfile, name: profileName, color: profileColor }} size={56} fontSize={20} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                {editingName ? (
                  <input
                    ref={nameInputRef}
                    type="text"
                    value={profileName}
                    onChange={e => setProfileName(e.target.value)}
                    onBlur={() => {
                      setEditingName(false);
                      const trimmed = profileName.trim();
                      if (trimmed && trimmed !== localProfile.name) {
                        api.updateProfile(localProfile.id, { name: trimmed }).then(p => {
                          setLocalProfile(p);
                          setProfileName(p.name);
                        }).catch(() => {
                          setProfileName(localProfile.name);
                        });
                      } else {
                        setProfileName(localProfile.name);
                      }
                    }}
                    onKeyDown={e => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        (e.target as HTMLInputElement).blur();
                      }
                    }}
                    maxLength={30}
                    style={{
                      width: '100%', height: 32, borderRadius: 'var(--r-sm)',
                      border: 'none', background: 'var(--fill2)',
                      color: 'var(--text)', fontSize: 16, fontWeight: 700,
                      padding: '0 8px', fontFamily: 'inherit',
                    }}
                  />
                ) : (
                  <div
                    onClick={() => {
                      setEditingName(true);
                      // Focus after render, with enough delay for the input to mount
                      setTimeout(() => nameInputRef.current?.focus(), 150);
                    }}
                    style={{
                      fontSize: 16, fontWeight: 700, color: 'var(--text)',
                      cursor: 'pointer',
                      WebkitTapHighlightColor: 'transparent',
                    }}
                  >
                    {profileName}
                    <span style={{ fontSize: 11, color: 'var(--text3)', marginLeft: 6 }}>edit</span>
                  </div>
                )}
              </div>
            </div>

            {/* Avatar actions */}
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              <button
                onClick={() => avatarInputRef.current?.click()}
                style={{
                  flex: 1, height: 40, borderRadius: 'var(--r-sm)',
                  border: 'none', background: 'var(--fill2)',
                  color: 'var(--text)', fontSize: 13, fontWeight: 600,
                  fontFamily: 'inherit', cursor: 'pointer',
                  WebkitTapHighlightColor: 'transparent',
                }}
              >
                {localProfile.has_avatar ? 'Change Photo' : 'Upload Photo'}
              </button>
              {localProfile.has_avatar && (
                <button
                  onClick={async () => {
                    haptic(25);
                    try {
                      await api.deleteAvatar(localProfile.id);
                      setLocalProfile({ ...localProfile, has_avatar: false });
                      showToast('Photo removed');
                    } catch {
                      showToast('Failed to remove photo');
                    }
                  }}
                  style={{
                    height: 40, padding: '0 14px', borderRadius: 'var(--r-sm)',
                    border: 'none', background: 'var(--fill2)',
                    color: 'var(--red)', fontSize: 13, fontWeight: 600,
                    fontFamily: 'inherit', cursor: 'pointer',
                    WebkitTapHighlightColor: 'transparent',
                  }}
                >
                  Remove
                </button>
              )}
              <input
                ref={avatarInputRef}
                type="file"
                accept="image/*"
                capture="environment"
                onChange={async (e) => {
                  const file = e.target.files?.[0];
                  if (!file) return;
                  try {
                    await api.uploadAvatar(localProfile.id, file);
                    setLocalProfile({ ...localProfile, has_avatar: true });
                    haptic(25);
                    showToast('Photo updated');
                  } catch {
                    showToast('Upload failed');
                  }
                  if (avatarInputRef.current) avatarInputRef.current.value = '';
                }}
                style={{ display: 'none' }}
              />
            </div>

            {/* Color swatches */}
            <div style={{
              display: 'flex', gap: 10, marginBottom: 16,
              padding: '0 4px',
            }}>
              {AVATAR_COLORS.map(c => (
                <button
                  key={c}
                  onClick={async () => {
                    setProfileColor(c);
                    haptic(15);
                    try {
                      const p = await api.updateProfile(localProfile.id, { color: c });
                      setLocalProfile(p);
                    } catch {
                      setProfileColor(localProfile.color);
                    }
                  }}
                  style={{
                    width: 32, height: 32, borderRadius: '50%',
                    background: c,
                    border: profileColor === c ? '3px solid var(--text)' : '3px solid transparent',
                    cursor: 'pointer', padding: 0,
                    transition: 'border 150ms var(--ease)',
                    WebkitTapHighlightColor: 'transparent',
                  }}
                />
              ))}
            </div>

            <div style={{ borderBottom: '1px solid var(--separator)' }} />
          </div>
        )}

        {/* Weight */}
        <div style={{ ...rowStyle, cursor: 'default' }}>
          <span style={{ fontSize: 15, color: 'var(--text)' }}>Weight</span>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <input
              type="number"
              inputMode="numeric"
              min={50}
              max={500}
              value={weightLbs ?? ''}
              onChange={e => {
                const v = parseInt(e.target.value, 10);
                if (!isNaN(v)) setWeightLbs(v);
              }}
              onBlur={() => {
                if (weightLbs != null && weightLbs >= 50 && weightLbs <= 500) {
                  api.updateUser({ weight_lbs: weightLbs }).catch(() => {});
                }
              }}
              style={{
                width: 60, height: 32, borderRadius: 'var(--r-sm)',
                border: 'none', background: 'var(--fill2)',
                color: 'var(--text)', fontSize: 15, fontWeight: 600,
                textAlign: 'right', padding: '0 8px',
                fontFamily: 'inherit',
              }}
            />
            <span style={{ fontSize: 13, color: 'var(--text3)' }}>lbs</span>
          </div>
        </div>

        {/* Import GPX */}
        <label style={rowStyle}>
          <span style={{ fontSize: 15, color: 'var(--text)' }}>Import GPX Route</span>
          <span style={{ fontSize: 13, color: 'var(--text3)' }}>&#8250;</span>
          <input
            ref={fileInputRef}
            type="file"
            accept=".gpx"
            onChange={handleGpxUpload}
            style={{ display: 'none' }}
          />
        </label>

        {/* Debug Console */}
        <div
          onClick={() => { setLocation('/debug'); onClose(); haptic(25); }}
          style={rowStyle}
        >
          <span style={{ fontSize: 15, color: 'var(--text)' }}>Debug Console</span>
          <span style={{ fontSize: 13, color: 'var(--text3)' }}>&#8250;</span>
        </div>

        {/* Smart-ass mode toggle */}
        <div
          onClick={() => {
            const next = !smartass;
            setSmartass(next);
            try { localStorage.setItem('smartass_mode', String(next)); } catch {}
            haptic(25);
            showToast(next ? 'Smart-ass mode ON. Brace yourself.' : 'Smart-ass mode off.');
          }}
          style={rowStyle}
        >
          <span style={{ fontSize: 15, color: 'var(--text)' }}>Smart-ass Mode</span>
          <div style={{
            width: 44, height: 26, borderRadius: 13,
            background: smartass ? 'var(--purple)' : 'var(--fill)',
            position: 'relative', transition: 'background 200ms var(--ease)',
            flexShrink: 0,
          }}>
            <div style={{
              width: 22, height: 22, borderRadius: 11,
              background: '#fff',
              position: 'absolute', top: 2,
              left: smartass ? 20 : 2,
              transition: 'left 200ms var(--ease)',
            }} />
          </div>
        </div>

        {/* Mountain View experiment */}
        <div
          onClick={() => {
            const next = !mountainView;
            setMountainView(next);
            try { localStorage.setItem('mountain_view', String(next)); } catch {}
            window.dispatchEvent(new Event('mountain_view_changed'));
            haptic(25);
            showToast(next ? 'Mountain view enabled' : 'Mountain view disabled');
          }}
          style={rowStyle}
        >
          <span style={{ fontSize: 15, color: 'var(--text)' }}>Mountain View</span>
          <div style={{
            width: 44, height: 26, borderRadius: 13,
            background: mountainView ? 'var(--teal)' : 'var(--fill)',
            position: 'relative', transition: 'background 200ms var(--ease)',
            flexShrink: 0,
          }}>
            <div style={{
              width: 22, height: 22, borderRadius: 11,
              background: '#fff',
              position: 'absolute', top: 2,
              left: mountainView ? 20 : 2,
              transition: 'left 200ms var(--ease)',
            }} />
          </div>
        </div>

        {/* Heart Rate Monitor */}
        <div style={{ marginTop: 24 }}>
          <h3 style={{
            fontSize: 13, fontWeight: 600, color: 'var(--text3)',
            textTransform: 'uppercase' as const, letterSpacing: '0.02em',
            margin: '0 0 8px',
          }}>Heart Rate Monitor</h3>

          {/* Connection status */}
          <div style={{
            ...rowStyle,
            cursor: 'default',
          }}>
            <span style={{ fontSize: 15, color: 'var(--text)' }}>
              {status.hrmConnected ? `${status.heartRate > 0 ? status.heartRate + ' bpm' : 'Connected'}` : 'Not connected'}
            </span>
            {status.hrmConnected && (
              <span style={{
                fontSize: 14,
                color: hrColor(status.heartRate),
              }}>{'\u2665'}</span>
            )}
            {!status.hrmConnected && (
              <span style={{ fontSize: 13, color: 'var(--text3)' }}>{'\u2013'}</span>
            )}
          </div>

          {/* Device list from scan results */}
          {hrmDevices.length > 0 && !status.hrmConnected && (
            <div style={{ borderBottom: '1px solid var(--separator)' }}>
              {hrmDevices.map(d => {
                const selectDevice = async () => {
                  haptic(25);
                  try {
                    await api.selectHrmDevice(d.address);
                    showToast(`Connecting to ${d.name || d.address}...`);
                  } catch {
                    showToast('Failed to select device');
                  }
                };
                return (
                <div
                  key={d.address}
                  role="button"
                  tabIndex={0}
                  onClick={selectDevice}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      selectDevice();
                    }
                  }}
                  style={{
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                    height: 44, padding: '0 4px',
                    cursor: 'pointer',
                    WebkitTapHighlightColor: 'transparent',
                  }}
                >
                  <span style={{ fontSize: 14, color: 'var(--text)' }}>
                    {d.name || d.address}
                  </span>
                  <span style={{ fontSize: 12, color: 'var(--text3)', fontVariantNumeric: 'tabular-nums' }}>
                    {d.rssi} dBm
                  </span>
                </div>
                );
              })}
            </div>
          )}

          {/* Scan / Forget buttons */}
          <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
            <button
              onClick={async () => {
                haptic(25);
                setHrmScanning(true);
                try {
                  await api.scanHrm();
                } catch {
                  showToast('Scan failed');
                }
                setTimeout(() => setHrmScanning(false), 10000);
              }}
              disabled={hrmScanning}
              style={{
                flex: 1, height: 44, border: 'none',
                borderRadius: 'var(--r-sm)',
                background: 'var(--fill2)',
                color: hrmScanning ? 'var(--text3)' : 'var(--text)',
                fontSize: 14, fontWeight: 600, fontFamily: 'inherit',
                cursor: hrmScanning ? 'default' : 'pointer',
                WebkitTapHighlightColor: 'transparent',
              }}
            >
              {hrmScanning ? 'Scanning...' : 'Scan'}
            </button>
            {status.hrmConnected && (
              <button
                onClick={async () => {
                  haptic([25, 30, 25]);
                  try {
                    await api.forgetHrmDevice();
                    showToast('HRM device forgotten');
                  } catch {
                    showToast('Failed to forget device');
                  }
                }}
                style={{
                  flex: 1, height: 44, border: 'none',
                  borderRadius: 'var(--r-sm)',
                  background: 'var(--fill2)',
                  color: 'var(--red)',
                  fontSize: 14, fontWeight: 600, fontFamily: 'inherit',
                  cursor: 'pointer',
                  WebkitTapHighlightColor: 'transparent',
                }}
              >
                Forget
              </button>
            )}
          </div>
        </div>

        {/* Mode toggle (unlocked by triple-tap) */}
        {debugUnlocked && (
          <div style={{ marginTop: 24 }}>
            <h3 style={{
              fontSize: 13, fontWeight: 600, color: 'var(--text3)',
              textTransform: 'uppercase' as const, letterSpacing: '0.02em',
              margin: '0 0 8px',
            }}>Mode</h3>
            <div style={{
              display: 'flex', borderRadius: 'var(--r-sm)', overflow: 'hidden',
              background: 'var(--fill2)',
            }}>
              {(['proxy', 'emulate'] as const).map(mode => {
                const active = mode === 'proxy' ? status.proxy : status.emulate;
                const bg = mode === 'proxy' ? 'var(--green)' : 'var(--purple)';
                const fg = mode === 'proxy' ? '#000' : '#fff';
                return (
                  <button
                    key={mode}
                    onClick={() => { actions.setMode(mode); haptic([25, 30, 25]); }}
                    style={{
                      flex: 1, height: 44, border: 'none',
                      background: active ? bg : 'transparent',
                      color: active ? fg : 'var(--text3)',
                      fontSize: 15, fontWeight: 600, fontFamily: 'inherit',
                      cursor: 'pointer', borderRadius: 'var(--r-sm)',
                      WebkitTapHighlightColor: 'transparent',
                      transition: 'all 200ms var(--ease)',
                    }}
                  >{mode === 'proxy' ? 'Proxy' : 'Emulate'}</button>
                );
              })}
            </div>
          </div>
        )}

        {/* Delete Profile (danger zone) */}
        {localProfile && (
          <div style={{ marginTop: 32 }}>
            {confirmDelete ? (
              <div style={{
                background: 'rgba(196,92,82,0.1)', borderRadius: 'var(--r-sm)',
                padding: 16, textAlign: 'center',
              }}>
                <div style={{ fontSize: 14, color: 'var(--red)', fontWeight: 600, marginBottom: 12 }}>
                  Delete "{localProfile.name}"? This cannot be undone.
                </div>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button
                    onClick={() => setConfirmDelete(false)}
                    style={{
                      flex: 1, height: 40, borderRadius: 'var(--r-sm)',
                      border: 'none', background: 'var(--fill)',
                      color: 'var(--text2)', fontSize: 14, fontWeight: 600,
                      fontFamily: 'inherit', cursor: 'pointer',
                      WebkitTapHighlightColor: 'transparent',
                    }}
                  >Cancel</button>
                  <button
                    onClick={async () => {
                      haptic([25, 50, 25]);
                      try {
                        await api.deleteProfile(localProfile.id);
                        showToast('Profile deleted');
                        onClose();
                        setLocation('/profiles');
                      } catch (err) {
                        showToast(err instanceof Error && err.message.includes('400')
                          ? 'Cannot delete the last profile'
                          : 'Failed to delete profile');
                      }
                      setConfirmDelete(false);
                    }}
                    style={{
                      flex: 1, height: 40, borderRadius: 'var(--r-sm)',
                      border: 'none', background: 'var(--red)',
                      color: '#fff', fontSize: 14, fontWeight: 700,
                      fontFamily: 'inherit', cursor: 'pointer',
                      WebkitTapHighlightColor: 'transparent',
                    }}
                  >Delete</button>
                </div>
              </div>
            ) : (
              <button
                onClick={() => { setConfirmDelete(true); haptic(25); }}
                style={{
                  width: '100%', height: 44, borderRadius: 'var(--r-sm)',
                  border: 'none', background: 'transparent',
                  color: 'var(--red)', fontSize: 14, fontWeight: 500,
                  fontFamily: 'inherit', cursor: 'pointer',
                  WebkitTapHighlightColor: 'transparent',
                }}
              >
                Delete Profile
              </button>
            )}
          </div>
        )}
      </div>
    </>
  );
}
