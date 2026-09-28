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
    summary: 'Mission Planner: Schedules recursive long-horizon autonomous task pulses',
    description: 'Schedule an asynchronous, long-horizon mission with evolving prompt instructions and continuous context. Each pulse runs against the shared pulse engine, updates context, logs events, and can dynamically adjust its next interval or complete itself.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['title', 'instructions'],
      properties: {
        title: {
          type: 'string',
          description: 'Short, descriptive title for the mission.',
        },
        instructions: {
          type: 'string',
          description: 'Base prompt instructions repeated, evaluated, and evolved across pulse cycles.',
        },
        interval_seconds: {
          type: 'integer',
          minimum: 60,
          maximum: 86400,
          default: 900,
          description: 'Cadence in seconds between pulses (default 900s = 15m).',
        },
        max_pulses: {
          type: 'integer',
          minimum: 0,
          description: 'Maximum allowable pulses before auto-completing (0 = unbounded).',
        },
        context: {
          type: 'string',
          description: 'Initial continuous memory context passed into the first pulse.',
        },
        pathnames: {
          type: 'object',
          additionalProperties: { type: 'string' },
          description: 'Map of filename labels to absolute filesystem paths carried into every pulse.',
        },
        endpoint: {
          type: 'string',
          description: 'Optional custom LLM API endpoint URL.',
        },
        model: {
          type: 'string',
          description: 'Model identifier for pulse generation.',
        },
      },
    },
  },
  {
    name: 'mission_list',
    summary: 'Mission Catalog: Lists all active and completed long-horizon missions',
    description: 'List all registered long-horizon missions with live status (ACTIVE, PAUSED, COMPLETE, CANCELLED), pulse counters, and scheduled awakening times.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      properties: {},
    },
  },
  {
    name: 'mission_status',
    summary: 'Mission Inspector: Inspects full state and context of a specific mission',
    description: 'Retrieve full details for a mission including carried context, latest intent, last pulse output, and any recent errors.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['id'],
      properties: {
        id: {
          type: 'string',
          description: 'Unique mission identifier (e.g. "deploy-audit-a1b2c3").',
        },
      },
    },
  },
  {
    name: 'mission_update',
    summary: 'Mission Steerer: Updates instructions, context, or interval on an active mission',
    description: 'Steer an existing mission by altering instructions, modifying current context, re-timing cadence, or merging new tracked file pathnames.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['id'],
      properties: {
        id: {
          type: 'string',
          description: 'Target mission ID to update.',
        },
        context: {
          type: 'string',
          description: 'New continuous context string.',
        },
        instructions: {
          type: 'string',
          description: 'Updated recursive prompt instructions.',
        },
        interval_seconds: {
          type: 'integer',
          minimum: 60,
          maximum: 86400,
          description: 'Updated interval between pulses in seconds.',
        },
        pathnames: {
          type: 'object',
          additionalProperties: { type: 'string' },
          description: 'Dictionary of paths to merge into mission memory.',
        },
      },
    },
  },
  {
    name: 'mission_pause',
    summary: 'Mission Pauser: Suspends execution of an active mission',
    description: 'Pause a currently active mission without losing accumulated state, context, or ledger history.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['id'],
      properties: {
        id: {
          type: 'string',
          description: 'Target mission ID to pause.',
        },
      },
    },
  },
  {
    name: 'mission_resume',
    summary: 'Mission Resumer: Resumes execution of a paused mission',
    description: 'Resume a previously paused mission and schedule its next pulse, optionally updating the pulse cadence.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['id'],
      properties: {
        id: {
          type: 'string',
          description: 'Target mission ID to resume.',
        },
        interval_seconds: {
          type: 'integer',
          minimum: 60,
          maximum: 86400,
          description: 'Optional new pulse interval in seconds upon resume.',
        },
      },
    },
  },
  {
    name: 'mission_cancel',
    summary: 'Mission Canceler: Permanently halts a mission while preserving logs',
    description: 'Permanently cancel a running or paused mission. Sets status to CANCELLED while retaining the audit ledger for analysis.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['id'],
      properties: {
        id: {
          type: 'string',
          description: 'Target mission ID to cancel.',
        },
      },
    },
  },
  {
    name: 'mission_log',
    summary: 'Mission Log Auditor: Reads pulse execution history for a mission',
    description: 'Retrieve chronological pulse logs for a specific mission, including model responses, state transitions, and evaluation outcomes.',
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['id'],
      properties: {
        id: {
          type: 'string',
          description: 'Target mission ID to audit.',
        },
        limit: {
          type: 'integer',
          minimum: 1,
          maximum: 100,
          default: 10,
          description: 'Maximum number of recent log entries to retrieve.',
        },
      },
    },
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
