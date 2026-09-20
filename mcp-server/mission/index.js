#!/usr/bin/env node
// mission.mcp — long-horizon orchestration. Schedule heartbeat pulses with
// prewritten instructions and continuous context; each pulse reports back and
// the next one inherits the updated context. Shares the pulse engine with
// heartbeat.mcp (one scheduler, two pulse sources).

import { existsSync, readFileSync, writeFileSync, mkdirSync, openSync, readdirSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { homedir } from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { serve, textResult, errorResult } from '../lib/mcp-stdio.js';

const HOME = path.join(homedir(), '.offcoder');
const MISSIONS_DIR = path.join(HOME, 'missions');
const PID_PATH = path.join(HOME, 'heartbeat', 'engine.pid');
const LOG_PATH = path.join(HOME, 'logs', 'pulse-engine.log');
const REPO_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', '..');
const ENGINE = path.join(REPO_ROOT, 'scripts', 'pulse_engine.py');

const DEFAULT_ENDPOINT = process.env.HEARTBEAT_ENDPOINT ?? 'http://127.0.0.1:9090/v1/chat/completions';
const DEFAULT_MODEL = process.env.HEARTBEAT_MODEL ?? 'qwythos/qwythos';

function ensureDirs() {
  mkdirSync(MISSIONS_DIR, { recursive: true });
  mkdirSync(path.join(HOME, 'logs'), { recursive: true });
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

function missionPath(id) {
  return path.join(MISSIONS_DIR, `${id}.json`);
}

function loadMission(id) {
  try {
    return JSON.parse(readFileSync(missionPath(id), 'utf-8'));
  } catch {
    return null;
  }
}

function saveMission(mission) {
  writeFileSync(missionPath(mission.id), JSON.stringify(mission, null, 2));
  return mission;
}

function listMissions() {
  ensureDirs();
  return readdirSync(MISSIONS_DIR)
    .filter((name) => name.endsWith('.json'))
    .map((name) => {
      try {
        return JSON.parse(readFileSync(path.join(MISSIONS_DIR, name), 'utf-8'));
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => (b.created_at ?? 0) - (a.created_at ?? 0));
}

function summarize(mission) {
  const secondsUntilNext = mission.status === 'ACTIVE'
    ? Math.max(0, Math.round((mission.next_pulse_at ?? 0) - Date.now() / 1000))
    : null;
  return {
    id: mission.id,
    title: mission.title,
    status: mission.status,
    pulses_used: mission.pulses_used ?? 0,
    max_pulses: mission.max_pulses ?? null,
    interval_seconds: mission.interval_seconds,
    next_pulse_at: mission.next_pulse_at ?? null,
    seconds_until_next: secondsUntilNext,
    context: mission.context ?? '',
    intent: mission.intent ?? '',
    pathnames: mission.pathnames ?? {},
    last_pulse: mission.last_pulse ?? null,
    last_error: mission.last_error ?? null,
  };
}

const tools = [
  {
    name: 'mission_create',
    description: 'Schedule a long-horizon mission: prewritten instructions re-fired as heartbeat pulses with continuous context. Each pulse returns updated context and may choose its own next interval (NEXT_INTERVAL) or complete (STATUS: complete).',
    inputSchema: {
      type: 'object', additionalProperties: false, required: ['title', 'instructions'],
      properties: {
        title: { type: 'string' },
        instructions: { type: 'string', description: 'prewritten instructions repeated (and evolved) every pulse' },
        interval_seconds: { type: 'integer', minimum: 60, maximum: 86400, default: 900 },
        max_pulses: { type: 'integer', minimum: 0, description: '0 = unbounded' },
        context: { type: 'string', description: 'initial continuous context' },
        pathnames: { type: 'object', additionalProperties: { type: 'string' }, description: 'file pathname map carried into every pulse' },
        endpoint: { type: 'string' },
        model: { type: 'string' },
      },
    },
  },
  {
    name: 'mission_list',
    description: 'List missions with status, pulse counts, and next awakening.',
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
  {
    name: 'mission_status',
    description: 'Read one mission in full.',
    inputSchema: { type: 'object', additionalProperties: false, required: ['id'], properties: { id: { type: 'string' } } },
  },
  {
    name: 'mission_update',
    description: 'Steer a mission: replace context or instructions, retime the next pulse, merge pathnames.',
    inputSchema: {
      type: 'object', additionalProperties: false, required: ['id'],
      properties: {
        id: { type: 'string' },
        context: { type: 'string' },
        instructions: { type: 'string' },
        interval_seconds: { type: 'integer', minimum: 60, maximum: 86400 },
        pathnames: { type: 'object', additionalProperties: { type: 'string' } },
      },
    },
  },
  {
    name: 'mission_pause',
    description: 'Pause a mission; context and ledger stay intact.',
    inputSchema: { type: 'object', additionalProperties: false, required: ['id'], properties: { id: { type: 'string' } } },
  },
  {
    name: 'mission_resume',
    description: 'Resume a paused mission, optionally retiming the next pulse.',
    inputSchema: { type: 'object', additionalProperties: false, required: ['id'], properties: { id: { type: 'string' }, interval_seconds: { type: 'integer', minimum: 60, maximum: 86400 } } },
  },
  {
    name: 'mission_cancel',
    description: 'Cancel a mission (status CANCELLED; the ledger remains for review).',
    inputSchema: { type: 'object', additionalProperties: false, required: ['id'], properties: { id: { type: 'string' } } },
  },
  {
    name: 'mission_log',
    description: 'Read a mission pulse ledger (newest last).',
    inputSchema: { type: 'object', additionalProperties: false, required: ['id'], properties: { id: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 100, default: 10 } } },
  },
];

const handlers = {
  async mission_create(args) {
    ensureEngine();
    ensureDirs();
    const slug = String(args.title).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40) || 'mission';
    const id = `${slug}-${crypto.randomBytes(3).toString('hex')}`;
    const now = Date.now() / 1000;
    const mission = {
      id,
      title: args.title,
      instructions: args.instructions,
      status: 'ACTIVE',
      created_at: now,
      interval_seconds: args.interval_seconds ?? 900,
      next_pulse_at: now + 3,
      pulses_used: 0,
      max_pulses: args.max_pulses ?? 0,
      context: args.context ?? '',
      intent: '',
      pathnames: args.pathnames ?? {},
      endpoint: args.endpoint ?? DEFAULT_ENDPOINT,
      model: args.model ?? DEFAULT_MODEL,
      ledger_tail: [],
    };
    saveMission(mission);
    return textResult(JSON.stringify({ ok: true, engine_running: engineRunning(), mission: summarize(mission) }, null, 2));
  },

  async mission_list() {
    return textResult(JSON.stringify({ ok: true, engine_running: engineRunning(), missions: listMissions().map(summarize) }, null, 2));
  },

  async mission_status(args) {
    const mission = loadMission(args.id);
    if (!mission) return errorResult(`mission not found: ${args.id}`);
    return textResult(JSON.stringify({ ok: true, engine_running: engineRunning(), mission: summarize(mission) }, null, 2));
  },

  async mission_update(args) {
    const mission = loadMission(args.id);
    if (!mission) return errorResult(`mission not found: ${args.id}`);
    if (args.context !== undefined) mission.context = args.context;
    if (args.instructions !== undefined) mission.instructions = args.instructions;
    if (args.interval_seconds) {
      mission.interval_seconds = args.interval_seconds;
      if (mission.status === 'ACTIVE') mission.next_pulse_at = Date.now() / 1000 + args.interval_seconds;
    }
    if (args.pathnames) mission.pathnames = { ...(mission.pathnames ?? {}), ...args.pathnames };
    saveMission(mission);
    return textResult(JSON.stringify({ ok: true, mission: summarize(mission) }, null, 2));
  },

  async mission_pause(args) {
    const mission = loadMission(args.id);
    if (!mission) return errorResult(`mission not found: ${args.id}`);
    mission.status = 'PAUSED';
    mission.paused_at = Date.now() / 1000;
    saveMission(mission);
    return textResult(JSON.stringify({ ok: true, mission: summarize(mission) }, null, 2));
  },

  async mission_resume(args) {
    ensureEngine();
    const mission = loadMission(args.id);
    if (!mission) return errorResult(`mission not found: ${args.id}`);
    mission.status = 'ACTIVE';
    mission.next_pulse_at = Date.now() / 1000 + (args.interval_seconds ?? 3);
    if (args.interval_seconds) mission.interval_seconds = args.interval_seconds;
    saveMission(mission);
    return textResult(JSON.stringify({ ok: true, mission: summarize(mission) }, null, 2));
  },

  async mission_cancel(args) {
    const mission = loadMission(args.id);
    if (!mission) return errorResult(`mission not found: ${args.id}`);
    mission.status = 'CANCELLED';
    mission.cancelled_at = Date.now() / 1000;
    saveMission(mission);
    return textResult(JSON.stringify({ ok: true, mission: summarize(mission) }, null, 2));
  },

  async mission_log(args) {
    const ledgerPath = path.join(MISSIONS_DIR, `${args.id}.jsonl`);
    if (!existsSync(ledgerPath)) return textResult(JSON.stringify({ ok: true, entries: [] }, null, 2));
    const limit = args.limit ?? 10;
    const lines = readFileSync(ledgerPath, 'utf-8').split('\n').filter((line) => line.trim());
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

serve({ name: 'mission', version: '1.0.0', tools, handlers });
