import os from 'node:os';
import { unixMs } from './util.js';
import type { MarqueeLevel } from './marquee.js';

export type LogLevel = 'debug' | 'info' | 'warning' | 'error' | 'critical';

let seq = 0;

export interface StructuredLog {
  domain: string;
  level: LogLevel;
  code: string;
  msg: string;
  [extra: string]: unknown;
}

export function structLog(entry: Omit<StructuredLog, 'domain'> & { domain?: string }): void {
  const payload: Record<string, unknown> = {
    ...(entry as Record<string, unknown>),
    domain: entry.domain ?? 'daemon',
    level: entry.level,
    code: entry.code,
    msg: entry.msg,
    t: unixMs(),
    seq: seq++,
    pid: process.pid,
    host: os.hostname(),
  };
  const line = JSON.stringify(payload) + '\n';
  if (entry.level === 'error' || entry.level === 'critical') {
    process.stderr.write(line);
  } else {
    process.stdout.write(line);
  }
}

export function marqueeMapping(code: string): { level: MarqueeLevel; text: string } | null {
  switch (code) {
    case 'cdp_connected':
      return { level: 'idle', text: 'cdp attached — screencast live' };
    case 'cdp_offline':
      return { level: 'alert', text: 'chrome cdp offline — run scripts/chrome_launch.sh' };
    case 'task_checked_out':
      return { level: 'working', text: 'task running on worker' };
    case 'task_staged':
      return { level: 'success', text: 'artifact staged — validation queueing' };
    case 'task_failed':
      return { level: 'alert', text: 'task failed — retry budget applied' };
    case 'task_verified':
      return { level: 'success', text: 'artifact verified' };
    case 'lease_expired':
      return { level: 'alert', text: 'lease expired — task reclaimed' };
    case 'repo_indexed':
      return { level: 'success', text: 'repo tree indexed' };
    case 'repo_missing':
      return { level: 'alert', text: 'repo not found in org' };
    case 'bad_client_frame':
      return { level: 'alert', text: 'malformed client message rejected' };
    case 'auth_rejected':
      return { level: 'alert', text: 'ws auth token missing' };
    case 'recovered':
      return { level: 'success', text: 'state recovered — all systems nominal' };
    case 'permission_denied':
      return { level: 'alert', text: 'filesystem permission error — check workspace path' };
    case 'db_busy':
      return { level: 'warning', text: 'sqlite contended — retrying' };
    case 'battery_low':
      return { level: 'warning', text: 'battery low — stream throttled' };
    default:
      return null;
  }
}
