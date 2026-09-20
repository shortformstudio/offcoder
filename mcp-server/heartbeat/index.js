#!/usr/bin/env node
// heartbeat.mcp — Indigo's self-designed loop. The working memory layer.
//
// State lives in ~/.offcoder/heartbeat/state.json and re-instantiates at the rate
// Indigo chooses. Each pulse writes INTENT / CONTEXT / NEXT_INTERVAL / PATHNAME
// control lines; the pulse engine persists them for the next self. This server
// is the agent's hand on that layer: start, steer, inspect, sleep, wake.

import { existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync, openSync } from 'node:fs';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir } from 'node:os';
import path from 'node:path';
import { serve, textResult, errorResult } from '../lib/mcp-stdio.js';

const execFileAsync = promisify(execFile);

const HOME = path.join(homedir(), '.offcoder');
const HEARTBEAT_DIR = path.join(HOME, 'heartbeat');
const STATE_PATH = path.join(HEARTBEAT_DIR, 'state.json');
const LEDGER_PATH = path.join(HEARTBEAT_DIR, 'pulses.jsonl');
const PID_PATH = path.join(HEARTBEAT_DIR, 'engine.pid');
const LOG_PATH = path.join(HOME, 'logs', 'pulse-engine.log');
const REPO_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
const ENGINE = path.join(REPO_ROOT, 'scripts', 'pulse_engine.py');

const DEFAULT_ENDPOINT = process.env.HEARTBEAT_ENDPOINT ?? 'http://127.0.0.1:9090/v1/chat/completions';
const DEFAULT_MODEL = process.env.HEARTBEAT_MODEL ?? 'qwythos/qwythos';

function ensureDirs() {
  mkdirSync(HEARTBEAT_DIR, { recursive: true });
  mkdirSync(path.join(HOME, 'logs'), { recursive: true });
}

function defaultState() {
  const now = Date.now() / 1000;
  return {
    id: 'indigo-heartbeat',
    active: true,
    created_at: now,
    interval_seconds: 900,
    next_pulse_at: now + 5,
    pulse_count: 0,
    status: 'sleep',
    context: '',
    intent: '',
    pathnames: {},
    endpoint: DEFAULT_ENDPOINT,
    model: DEFAULT_MODEL,
    last_pulse: null,
    ledger_tail: [],
  };
}

function loadState() {
  ensureDirs();
  try {
    return { ...defaultState(), ...JSON.parse(readFileSync(STATE_PATH, 'utf-8')) };
  } catch {
    return defaultState();
  }
}

function saveState(state) {
  ensureDirs();
  state.updated_at = Date.now() / 1000;
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2));
  return state;
}

function engineRunning() {
  try {
    const pid = Number.parseInt(readFileSync(PID_PATH, 'utf-8').trim(), 10);
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function ensureEngine() {
  if (engineRunning()) return true;
  ensureDirs();
  const out = openSync(LOG_PATH, 'a');
  const child = spawn('/usr/bin/python3', [ENGINE], { detached: true, stdio: ['ignore', out, out] });
  child.unref();
  return true;
}

function summarize(state) {
  return {
    ok: true,
    engine_running: engineRunning(),
    active: state.active,
    pulse_count: state.pulse_count,
    interval_seconds: state.interval_seconds,
    next_pulse_at: state.next_pulse_at,
    seconds_until_next: Math.max(0, Math.round((state.next_pulse_at ?? 0) - Date.now() / 1000)),
    status: state.status,
    intent: state.intent,
    context: state.context,
    pathnames: state.pathnames,
    endpoint: state.endpoint,
    model: state.model,
    last_pulse: state.last_pulse,
    last_error: state.last_error ?? null,
  };
}

const tools = [
  {
    name: 'heartbeat_start',
    description: 'Wake the self-designed heartbeat loop. Seeds working memory (context, intent, pathnames) and lets Indigo choose each next interval via NEXT_INTERVAL control lines. The engine persists every pulse.',
    inputSchema: {
      type: 'object', additionalProperties: false,
      properties: {
        interval_seconds: { type: 'integer', minimum: 60, maximum: 86400, description: 'first awakening delta; Indigo may override it in any pulse' },
        context: { type: 'string', description: 'initial working memory' },
        intent: { type: 'string', description: 'seed intent for the first pulse' },
        endpoint: { type: 'string' },
        model: { type: 'string' },
      },
    },
  },
  {
    name: 'heartbeat_status',
    description: 'Read the working memory layer: active state, interval, next awakening, carried context, intent, and pathname map.',
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
  {
    name: 'heartbeat_update',
    description: 'Steer the loop directly: set the awakening interval, replace working context, set intent, or merge pathnames.',
    inputSchema: {
      type: 'object', additionalProperties: false,
      properties: {
        interval_seconds: { type: 'integer', minimum: 60, maximum: 86400 },
        context: { type: 'string' },
        intent: { type: 'string' },
        pathnames: { type: 'object', additionalProperties: { type: 'string' } },
      },
    },
  },
  {
    name: 'heartbeat_pulse_now',
    description: 'Fire the next awakening immediately instead of waiting for the timer.',
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
  {
    name: 'heartbeat_sleep',
    description: 'Pause the loop without losing working memory. The next self wakes when heartbeat_wake is called.',
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
  {
    name: 'heartbeat_wake',
    description: 'Resume the loop; optionally choose the awakening delta.',
    inputSchema: { type: 'object', additionalProperties: false, properties: { interval_seconds: { type: 'integer', minimum: 60, maximum: 86400 } } },
  },
  {
    name: 'heartbeat_register_path',
    description: 'Inject a file pathname into the map every future pulse reads. Name = absolute path.',
    inputSchema: {
      type: 'object', additionalProperties: false, required: ['name', 'pathname'],
      properties: { name: { type: 'string' }, pathname: { type: 'string' } },
    },
  },
  {
    name: 'heartbeat_history',
    description: 'Read the pulse ledger (most recent pulses, newest last).',
    inputSchema: { type: 'object', additionalProperties: false, properties: { limit: { type: 'integer', minimum: 1, maximum: 100, default: 10 } } },
  },
];

const handlers = {
  async heartbeat_start(args) {
    ensureEngine();
    const state = loadState();
    state.active = true;
    state.next_pulse_at = Date.now() / 1000 + 3;
    if (args.interval_seconds) state.interval_seconds = args.interval_seconds;
    if (args.context !== undefined) state.context = args.context;
    if (args.intent !== undefined) state.intent = args.intent;
    if (args.endpoint) state.endpoint = args.endpoint;
    if (args.model) state.model = args.model;
    saveState(state);
    return textResult(JSON.stringify(summarize(state), null, 2));
  },

  async heartbeat_status() {
    return textResult(JSON.stringify(summarize(loadState()), null, 2));
  },

  async heartbeat_update(args) {
    const state = loadState();
    if (args.interval_seconds) state.interval_seconds = args.interval_seconds;
    if (args.context !== undefined) state.context = args.context;
    if (args.intent !== undefined) state.intent = args.intent;
    if (args.pathnames) state.pathnames = { ...(state.pathnames ?? {}), ...args.pathnames };
    if (args.interval_seconds && state.active) state.next_pulse_at = Date.now() / 1000 + args.interval_seconds;
    saveState(state);
    return textResult(JSON.stringify(summarize(state), null, 2));
  },

  async heartbeat_pulse_now() {
    ensureEngine();
    const state = loadState();
    state.active = true;
    state.next_pulse_at = Date.now() / 1000;
    saveState(state);
    return textResult(JSON.stringify({ ok: true, queued: true, engine_running: engineRunning() }, null, 2));
  },

  async heartbeat_sleep() {
    const state = loadState();
    state.active = false;
    state.status = 'sleeping';
    saveState(state);
    return textResult(JSON.stringify(summarize(state), null, 2));
  },

  async heartbeat_wake(args) {
    ensureEngine();
    const state = loadState();
    state.active = true;
    state.status = 'sleep';
    state.next_pulse_at = Date.now() / 1000 + (args.interval_seconds ?? 3);
    if (args.interval_seconds) state.interval_seconds = args.interval_seconds;
    saveState(state);
    return textResult(JSON.stringify(summarize(state), null, 2));
  },

  async heartbeat_register_path(args) {
    const state = loadState();
    state.pathnames = { ...(state.pathnames ?? {}), [args.name]: args.pathname };
    saveState(state);
    return textResult(JSON.stringify({ ok: true, pathnames: state.pathnames }, null, 2));
  },

  async heartbeat_history(args) {
    const limit = args.limit ?? 10;
    if (!existsSync(LEDGER_PATH)) return textResult(JSON.stringify({ ok: true, entries: [] }, null, 2));
    const lines = readFileSync(LEDGER_PATH, 'utf-8').split('\n').filter((line) => line.trim());
    const entries = lines.slice(-limit).map((line) => {
      try {
        const record = JSON.parse(line);
        return {
          pulse: record.pulse,
          iso: record.iso,
          interval_seconds: record.interval_seconds,
          intent: record.intent,
          status: record.status,
          duration_ms: record.duration_ms,
          endpoint: record.endpoint,
        };
      } catch {
        return null;
      }
    }).filter(Boolean);
    return textResult(JSON.stringify({ ok: true, entries }, null, 2));
  },
};

serve({ name: 'heartbeat', version: '1.0.0', tools, handlers });
