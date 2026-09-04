import { execFileSync } from 'node:child_process';

let cached: 'AC' | 'BATTERY' | null = null;
let lastChecked = 0;
const CACHE_MS = 30_000;

export function batteryState(): 'AC' | 'BATTERY' {
  const now = Date.now();
  if (cached && now - lastChecked < CACHE_MS) return cached;
  lastChecked = now;
  try {
    const out = execFileSync('pmset', ['-g', 'batt'], { encoding: 'utf8' });
    cached = out.includes('AC Power') ? 'AC' : 'BATTERY';
  } catch {
    cached = 'AC';
  }
  return cached;
}

export function batteryPercentage(): number {
  try {
    const out = execFileSync('pmset', ['-g', 'batt'], { encoding: 'utf8' });
    const match = out.match(/(\d+)%/);
    if (match) return parseInt(match[1], 10);
  } catch {
    /* desktop or unsupported */
  }
  return 100;
}

export interface TelemetrySnapshot {
  battery: 'AC' | 'BATTERY';
  batteryPercent: number;
  platform: string;
  uptimeNow: number;
  pendingTasks: number;
  inflightTasks: number;
  cdpConnected: boolean;
}

export function computeTelemetry(pending: number, inflight: number, cdp: boolean): TelemetrySnapshot {
  return {
    battery: batteryState(),
    batteryPercent: batteryPercentage(),
    platform: process.platform,
    uptimeNow: Math.floor(process.uptime()),
    pendingTasks: pending,
    inflightTasks: inflight,
    cdpConnected: cdp,
  };
}
