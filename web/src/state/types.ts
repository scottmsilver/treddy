// --- Server message types ---

export interface KVMessage {
  type: 'kv';
  source: 'motor' | 'console' | 'emulate';
  key: string;
  value: string;
  ts?: number;
}

export interface StatusMessage {
  type: 'status';
  proxy: boolean;
  emulate: boolean;
  emu_speed: number;
  emu_speed_mph: number;
  emu_incline: number;
  speed: number | null;
  incline: number | null;
  motor: Record<string, string>;
  treadmill_connected: boolean;
  heart_rate: number;
  hrm_connected: boolean;
  hrm_device: string;
}

export interface SessionMessage {
  type: 'session';
  active: boolean;
  elapsed: number;
  distance: number;
  vert_feet: number;
  calories: number;
  wall_started_at: string;
  end_reason: 'user_stop' | 'watchdog' | 'auto_proxy' | 'disconnect' | null;
}

export interface Interval {
  name: string;
  duration: number;
  speed: number;
  incline: number;
}

export interface Program {
  name: string;
  manual?: boolean;
  intervals: Interval[];
}

export interface ProgramMessage {
  type: 'program';
  program: Program | null;
  running: boolean;
  paused: boolean;
  completed: boolean;
  current_interval: number;
  interval_elapsed: number;
  total_elapsed: number;
  total_duration: number;
  encouragement?: string;
}

export interface ConnectionMessage {
  type: 'connection';
  connected: boolean;
}

export interface HRMessage {
  type: 'hr';
  bpm: number;
  connected: boolean;
  device: string;
  address: string;
}

export interface ScanResultMessage {
  type: 'scan_result';
  devices: Array<{ address: string; name: string; rssi: number }>;
}

export interface ProfileChangedMessage {
  type: 'profile_changed';
  profile: Profile | null;
  guest_mode: boolean;
}

export type ServerMessage = KVMessage | StatusMessage | SessionMessage | ProgramMessage | ConnectionMessage | HRMessage | ScanResultMessage | ProfileChangedMessage;

// --- Client state ---

export interface TreadmillStatus {
  proxy: boolean;
  emulate: boolean;
  emuSpeed: number;       // tenths of mph
  emuIncline: number;
  speed: number | null;   // live motor speed mph
  incline: number | null;  // live motor incline
  motor: Record<string, string>;
  treadmillConnected: boolean;
  heartRate: number;
  hrmConnected: boolean;
}

export interface SessionState {
  active: boolean;
  elapsed: number;
  distance: number;
  vertFeet: number;
  calories: number;
  wallStartedAt: string;
  endReason: string | null;
}

export interface ProgramState {
  program: Program | null;
  running: boolean;
  paused: boolean;
  completed: boolean;
  currentInterval: number;
  intervalElapsed: number;
  totalElapsed: number;
  totalDuration: number;
}

export interface AppState {
  wsConnected: boolean;
  status: TreadmillStatus;
  session: SessionState;
  program: ProgramState;
  kvLog: KVEntry[];
  hrmDevices: Array<{ address: string; name: string; rssi: number }>;
  activeProfile: Profile | null;
  guestMode: boolean;
  _dirtySpeed: number;
  _dirtyIncline: number;
}

export interface KVEntry {
  ts: string;
  src: string;
  key: string;
  value: string;
}

// --- Run History ---

export interface RunRecord {
  id: string;
  started_at: string;
  ended_at: string;
  elapsed: number;
  distance: number;
  vert_feet: number;
  end_reason: string;
  program_name: string | null;
  program_completed: boolean;
  is_manual: boolean;
}

// --- History ---

export interface HistoryEntry {
  id: string;
  prompt: string;
  program: Program;
  created_at: string;
  total_duration: number;
  completed?: boolean;
  last_interval?: number;
  last_elapsed?: number;
  saved?: boolean;
  last_run?: RunRecord | null;
  last_run_text?: string;
}

export interface SavedWorkout {
  id: string;
  name: string;
  program: Program;
  created_at: string;
  source: 'generated' | 'gpx' | 'manual';
  prompt: string;
  times_used: number;
  last_used: string | null;
  total_duration: number;
  last_run?: RunRecord | null;
  last_run_text?: string;
  usage_text?: string;
}

// --- Chat ---

export interface ChatResponse {
  text: string;
  actions: Array<{ name: string; args: Record<string, unknown>; result: string }>;
  transcription?: string;
}

// --- Profile ---

export interface Profile {
  id: string;
  name: string;
  color: string;
  initials: string;
  weight_lbs: number;
  vest_lbs: number;
  has_avatar: boolean;
}

// --- Config ---

export interface AppConfig {
  gemini_api_key: string;
  gemini_model: string;
  gemini_live_model: string;
  gemini_voice: string;
  tools?: Array<{ functionDeclarations: unknown[] }>;
  system_prompt?: string;
  smartass_addendum?: string;
}
