import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { STATE_DIR, MAX_CONSULTS, MAX_CONVERSATIONS } from './config.js';

const LEDGER_PATH = path.join(STATE_DIR, 'ledger.json');
let cache;

export class LedgerError extends Error {}

function load() {
  if (cache) return cache;
  try {
    const parsed = JSON.parse(fs.readFileSync(LEDGER_PATH, 'utf8'));
    cache = {
      consults_used: Number(parsed.consults_used) || 0,
      conversations: Array.isArray(parsed.conversations) ? parsed.conversations : [],
    };
  } catch {
    cache = { consults_used: 0, conversations: [] };
  }
  return cache;
}

function save() {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  const tmp = `${LEDGER_PATH}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(cache, null, 2));
  fs.renameSync(tmp, LEDGER_PATH);
}

export function snapshot() {
  const s = load();
  return {
    consults_used: s.consults_used,
    consults_remaining: Math.max(0, MAX_CONSULTS - s.consults_used),
    conversations_used: s.conversations.length,
    conversations_remaining: Math.max(0, MAX_CONVERSATIONS - s.conversations.length),
    limits: { max_consults: MAX_CONSULTS, max_conversations: MAX_CONVERSATIONS },
  };
}

export function consultsRemaining() {
  return snapshot().consults_remaining;
}

export function getConversation(id) {
  return load().conversations.find((c) => c.id === id) ?? null;
}

export function listConversations() {
  return [...load().conversations].sort((a, b) =>
    String(b.updated_at ?? '').localeCompare(String(a.updated_at ?? '')),
  );
}

export function createConversation(provider) {
  const s = load();
  if (s.conversations.length >= MAX_CONVERSATIONS) {
    throw new LedgerError(
      `conversation limit reached (${MAX_CONVERSATIONS}/${MAX_CONVERSATIONS}). continue an existing thread via conversation_id (see consult_list) or run consult_reset.`,
    );
  }
  const now = new Date().toISOString();
  const rec = {
    id: crypto.randomBytes(4).toString('hex'),
    provider,
    url: null,
    turns: 0,
    status: 'new',
    created_at: now,
    updated_at: now,
  };
  s.conversations.push(rec);
  save();
  return rec;
}

export function touch(rec, fields = {}) {
  Object.assign(rec, fields, { updated_at: new Date().toISOString() });
  save();
}

export function spendConsult() {
  const s = load();
  if (s.consults_used >= MAX_CONSULTS) {
    throw new LedgerError(
      `consult budget exhausted (${s.consults_used}/${MAX_CONSULTS}). weigh whether more auditing earns its cost, then call consult_reset to start a fresh engagement.`,
    );
  }
  s.consults_used += 1;
  save();
}

export function resetLedger() {
  cache = { consults_used: 0, conversations: [] };
  save();
}
