import { unixMs } from './util.js';

export type MarqueeLevel = 'idle' | 'success' | 'working' | 'warning' | 'alert';

export interface MarqueeState {
  level: MarqueeLevel;
  text: string;
  code: string;
  ts: number;
}

const TTL_MS: Record<MarqueeLevel, number> = {
  idle: 10_000,
  success: 8_000,
  working: 15_000,
  warning: 12_000,
  alert: 0,
};

const MAX_HISTORY = 8;

export class MarqueeDirector {
  private current: MarqueeState | null = null;
  private history: MarqueeState[] = [];

  post(level: MarqueeLevel, text: string, code: string): MarqueeState {
    this.current = { level, text, code, ts: unixMs() };
    this.history.push(this.current);
    if (this.history.length > MAX_HISTORY) this.history.shift();
    return this.current;
  }

  snapshot(): MarqueeState[] {
    const active = this.current ? [this.expire(this.current)].filter(Boolean) as MarqueeState[] : [];
    return [...active, ...this.history.slice(-3)].map((m) => this.expire(m)).filter(Boolean) as MarqueeState[];
  }

  currentState(): MarqueeState | null {
    return this.current ? this.expire(this.current) : null;
  }

  private expire(state: MarqueeState): MarqueeState | null {
    if (TTL_MS[state.level] === 0) return state;
    if (unixMs() - state.ts > TTL_MS[state.level]) return null;
    return state;
  }
}
