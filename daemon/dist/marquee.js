import { unixMs } from './util.js';
const TTL_MS = {
    idle: 10_000,
    success: 8_000,
    working: 15_000,
    warning: 12_000,
    alert: 0,
};
const MAX_HISTORY = 8;
export class MarqueeDirector {
    current = null;
    history = [];
    post(level, text, code) {
        this.current = { level, text, code, ts: unixMs() };
        this.history.push(this.current);
        if (this.history.length > MAX_HISTORY)
            this.history.shift();
        return this.current;
    }
    snapshot() {
        const active = this.current ? [this.expire(this.current)].filter(Boolean) : [];
        return [...active, ...this.history.slice(-3)].map((m) => this.expire(m)).filter(Boolean);
    }
    currentState() {
        return this.current ? this.expire(this.current) : null;
    }
    expire(state) {
        if (TTL_MS[state.level] === 0)
            return state;
        if (unixMs() - state.ts > TTL_MS[state.level])
            return null;
        return state;
    }
}
