import { IDLE_MS, MAX_POLLS, MAX_PROMPT_CHARS, MIN_SEND_GAP_MS, POLL_MS } from './config.js';
import { getPage, profilePath, withLock } from './browser.js';
import * as ledger from './ledger.js';
import { armIdleWatcher, idleMs } from './watcher.js';
import { GEMINI } from './gemini.js';
import { DEEPSEEK } from './deepseek.js';
import { KIMI } from './kimi.js';

const PROVIDERS = { gemini: GEMINI, deepseek: DEEPSEEK, kimi: KIMI };
const lastSendAt = new Map();

export class ConsultError extends Error {}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function settleLoop(page, prov, maxPolls) {
  const cap = Math.min(Math.max(1, maxPolls ?? MAX_POLLS), 60);
  let prev = '';
  for (let poll = 1; poll <= cap; poll++) {
    await sleep(POLL_MS);
    let text = '';
    let busy = false;
    let idle = IDLE_MS + 1;
    try {
      text = await prov.readLatest(page);
      busy = await prov.isBusy(page);
      idle = await idleMs(page);
    } catch (err) {
      return {
        status: 'error',
        response_text: prev,
        polls: poll,
        waited_seconds: Math.round((poll * POLL_MS) / 1000),
        error: `page unavailable while polling (${err instanceof Error ? err.message : String(err)}). reopen via consult_check.`,
      };
    }
    if (text && !busy && idle >= IDLE_MS && text === prev) {
      return {
        status: 'complete',
        response_text: text,
        polls: poll,
        waited_seconds: Math.round((poll * POLL_MS) / 1000),
      };
    }
    prev = text;
  }
  return {
    status: 'generating',
    response_text: prev,
    polls: cap,
    waited_seconds: Math.round((cap * POLL_MS) / 1000),
    hint: `still generating after ${cap} polls. call consult_check with this conversation_id to keep waiting; never resend the prompt.`,
  };
}

export async function consult(providerName, { prompt, conversationId, maxPolls }) {
  const prov = PROVIDERS[providerName];
  if (!prov) throw new ConsultError(`unknown provider "${providerName}"`);
  if (!prompt || typeof prompt !== 'string' || !prompt.trim()) {
    throw new ConsultError('prompt is required and must be non-empty');
  }
  if (prompt.length > MAX_PROMPT_CHARS) {
    throw new ConsultError(
      `prompt is ${prompt.length} chars; limit ${MAX_PROMPT_CHARS}. split material across follow-up turns in the same conversation.`,
    );
  }
  if (conversationId) {
    const existing = ledger.getConversation(conversationId);
    if (!existing) throw new ConsultError(`unknown conversation_id "${conversationId}". call consult_list for active threads.`);
    if (existing.provider !== providerName) {
      throw new ConsultError(`conversation ${conversationId} belongs to ${existing.provider}; use consult_${existing.provider}.`);
    }
  }
  if (ledger.consultsRemaining() <= 0) {
    throw new ConsultError(
      `consult budget exhausted (${ledger.snapshot().limits.max_consults}/${ledger.snapshot().limits.max_consults}). decide whether more auditing earns its cost, then call consult_reset.`,
    );
  }

  return withLock(providerName, async () => {
    const page = await getPage(providerName);
    const rec = conversationId ? ledger.getConversation(conversationId) : null;

    try {
      await page.goto(rec?.url ?? prov.home, { waitUntil: 'domcontentloaded', timeout: 45000 });
    } catch (err) {
      throw new ConsultError(
        `could not reach ${rec?.url ?? prov.home}: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    if (!(await prov.isLoggedIn(page))) {
      return {
        ok: false,
        provider: providerName,
        status: 'login_required',
        message: `a browser window is open at ${prov.home}. sign in manually once — the session persists in ${profilePath(providerName)} — then retry this exact call unchanged.`,
        budget: ledger.snapshot(),
      };
    }

    const recFinal = rec ?? ledger.createConversation(providerName);

    const gap = MIN_SEND_GAP_MS - (Date.now() - (lastSendAt.get(providerName) ?? 0));
    if (gap > 0) await sleep(gap);

    await armIdleWatcher(page);
    await prov.send(page, prompt.trim());
    lastSendAt.set(providerName, Date.now());

    ledger.spendConsult();
    ledger.touch(recFinal, { turns: recFinal.turns + 1, status: 'generating' });
    await sleep(2500);
    const url = page.url();
    if (url && url !== prov.home && prov.isThreadUrl(url)) recFinal.url = url;

    const result = await settleLoop(page, prov, maxPolls);
    ledger.touch(recFinal, { url: recFinal.url, status: result.status });
    return {
      ok: result.status !== 'error',
      provider: providerName,
      conversation_id: recFinal.id,
      url: recFinal.url,
      ...result,
      budget: ledger.snapshot(),
    };
  });
}

export async function check(conversationId, maxPolls) {
  const rec = ledger.getConversation(conversationId);
  if (!rec) throw new ConsultError(`unknown conversation_id "${conversationId}". call consult_list.`);
  const prov = PROVIDERS[rec.provider];

  return withLock(rec.provider, async () => {
    const page = await getPage(rec.provider);
    await page.goto(rec.url ?? prov.home, { waitUntil: 'domcontentloaded', timeout: 45000 }).catch(() => {});

    if (!(await prov.isLoggedIn(page))) {
      return {
        ok: false,
        provider: rec.provider,
        conversation_id: rec.id,
        status: 'login_required',
        message: `sign in at ${prov.home}; the session persists in ${profilePath(rec.provider)}; retry consult_check.`,
        budget: ledger.snapshot(),
      };
    }

    await armIdleWatcher(page);
    const result = await settleLoop(page, prov, maxPolls);
    ledger.touch(rec, { status: result.status });
    return {
      ok: result.status !== 'error',
      provider: rec.provider,
      conversation_id: rec.id,
      url: rec.url,
      ...result,
      budget: ledger.snapshot(),
    };
  });
}
