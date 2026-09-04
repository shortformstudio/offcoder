import os from 'node:os';
import path from 'node:path';

function intEnv(name, fallback, min, max) {
  const raw = Number.parseInt(process.env[name] ?? '', 10);
  if (!Number.isFinite(raw)) return fallback;
  return Math.min(max, Math.max(min, raw));
}

export const STATE_DIR = process.env.CONSULT_STATE_DIR || path.join(os.homedir(), '.config', 'consult');
export const PROFILE_ROOT = path.join(STATE_DIR, 'profiles');
export const POLL_MS = intEnv('CONSULT_POLL_MS', 15000, 3000, 60000);
export const MAX_POLLS = intEnv('CONSULT_MAX_POLLS', 20, 1, 60);
export const IDLE_MS = intEnv('CONSULT_IDLE_MS', 5000, 1000, 30000);
export const MAX_CONSULTS = intEnv('CONSULT_MAX_CONSULTS', 10, 1, 100);
export const MAX_CONVERSATIONS = intEnv('CONSULT_MAX_CONVERSATIONS', 10, 1, 100);
export const MAX_PROMPT_CHARS = intEnv('CONSULT_MAX_PROMPT_CHARS', 80000, 1000, 400000);
export const HEADLESS = process.env.CONSULT_HEADLESS === '1';
export const CHANNEL = process.env.CONSULT_CHANNEL || 'chrome';
export const RESET_ALLOWED = process.env.CONSULT_ALLOW_RESET !== '0';
export const MIN_SEND_GAP_MS = intEnv('CONSULT_MIN_SEND_GAP_MS', 4000, 0, 60000);
