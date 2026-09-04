import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { MAX_CONSULTS, MAX_CONVERSATIONS, MAX_PROMPT_CHARS, MAX_POLLS, POLL_MS, RESET_ALLOWED } from './lib/config.js';
import * as ledger from './lib/ledger.js';
import { validate, applyDefaults } from './lib/validate.js';
import { consult, check } from './lib/session.js';
import { listPrompts, getPrompt } from './lib/prompts.js';
import { closeAll } from './lib/browser.js';

const CONSULT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['prompt'],
  properties: {
    prompt: {
      type: 'string',
      minLength: 1,
      maxLength: MAX_PROMPT_CHARS,
      description: 'exact message text to send. prefer verbatim wording assembled from a consult_prompts template.',
    },
    conversation_id: {
      type: 'string',
      description: 'continue an existing thread. omit to open a new conversation (consumes one conversation slot).',
    },
    max_wait_polls: {
      type: 'integer',
      minimum: 1,
      maximum: 40,
      default: MAX_POLLS,
      description: `how many ${Math.round(POLL_MS / 1000)}-second completion polls before returning with status "generating".`,
    },
  },
};

function consultDescription(provider) {
  return `Start or continue an audit consultation with web ${provider} driven through a real logged-in stealth browser session.

Args:
  - prompt (string, required): exact message text. Pull precise wording from consult_prompts templates whenever possible; redact secrets before sending.
  - conversation_id (string, optional): continue an existing ${provider} thread. Omit to open a new conversation (consumes one of the ${MAX_CONVERSATIONS} conversation slots).
  - max_wait_polls (integer, optional): number of ${Math.round(POLL_MS / 1000)}s completion polls before yielding (default ${MAX_POLLS}).

Behavior:
  - Sends the prompt, then waits ${Math.round(POLL_MS / 1000)} seconds at a time until the model stops streaming (text stable across two polls AND page idle).
  - Returns JSON: {ok, provider, conversation_id, url, status: complete|generating|login_required|error, response_text, polls, waited_seconds, budget}.
  - status "generating": call consult_check with the returned conversation_id to keep waiting. Never resend the prompt.
  - status "login_required": a visible Chrome window opened at the site — sign in manually once; the session persists in its profile dir; then retry this exact call unchanged.
  - status "complete": you decide whether another consult adds value. Follow-ups continue the same conversation_id; cross-examination goes to the other provider using the verify_findings template; merge results with synthesis_merge.

Budget: every send (new or follow-up) consumes 1 of ${MAX_CONSULTS} consults; at most ${MAX_CONSULTS} conversations exist per engagement. Remaining budget ships in every response; consult_reset starts a fresh engagement.`;
}

const TOOL_DEFS = [
  {
    name: 'consult_gemini',
    description: consultDescription('Gemini'),
    inputSchema: CONSULT_SCHEMA,
  },
  {
    name: 'consult_deepseek',
    description: consultDescription('DeepSeek') + '\nSpecialized for deep coding consult loops, algorithmic optimization, and backend logic.',
    inputSchema: CONSULT_SCHEMA,
  },
  {
    name: 'consult_kimi',
    description: consultDescription('Kimi') + '\nSpecialized for design audits, UI/UX critiques, visual layout reviews, and frontend aesthetics.',
    inputSchema: CONSULT_SCHEMA,
  },
  {
    name: 'consult_check',
    description: `Re-poll an in-flight consultation without sending anything or spending budget.

Args:
  - conversation_id (string, required)
  - max_wait_polls (integer, optional)

Use after any response with status "generating". Same JSON shape as consult_gemini/consult_deepseek.`,
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['conversation_id'],
      properties: {
        conversation_id: { type: 'string', description: 'thread to keep waiting on' },
        max_wait_polls: {
          type: 'integer',
          minimum: 1,
          maximum: 40,
          default: MAX_POLLS,
          description: `${Math.round(POLL_MS / 1000)}s polls before returning status "generating" again.`,
        },
      },
    },
  },
  {
    name: 'consult_list',
    description: `List every conversation in the current engagement with live status, turn counts, thread URLs, and remaining budget. Costs nothing. Call it whenever you lose track of thread ids.`,
    inputSchema: { type: 'object', additionalProperties: false, properties: {} },
  },
  {
    name: 'consult_prompts',
    description: `Prewritten audit prompt library — precise verbage engineered to get high-signal results from web Gemini and DeepSeek.

Args:
  - template_id (string, optional): return that full prompt text. Omit for the catalog.

Templates: kickoff_context_primer, code_audit_deep, security_audit, architecture_review, ui_design_critique, bug_triage, performance_review, refactor_blueprint, spec_polish, verify_findings, synthesis_merge, release_signoff.

Workflow: fetch a template, replace {{TOKENS}} with your material, pass the finished string as prompt to consult_gemini or consult_deepseek.`,
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        template_id: { type: 'string', description: 'specific template to retrieve in full' },
      },
    },
  },
  {
    name: 'consult_reset',
    description: `Start a fresh engagement: zeroes the consult counter and clears the conversation ledger (${MAX_CONSULTS} sends / ${MAX_CONVERSATIONS} conversations restored).

Args:
  - confirm (boolean, required, must be true)`,
    inputSchema: {
      type: 'object',
      additionalProperties: false,
      required: ['confirm'],
      properties: {
        confirm: { type: 'boolean', const: true, description: 'must be exactly true' },
      },
    },
  },
];

function respond(payload) {
  return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }] };
}

const HANDLERS = {
  consult_gemini: (args) => consult('gemini', { prompt: args.prompt, conversationId: args.conversation_id, maxPolls: args.max_wait_polls }),
  consult_deepseek: (args) => consult('deepseek', { prompt: args.prompt, conversationId: args.conversation_id, maxPolls: args.max_wait_polls }),
  consult_kimi: (args) => consult('kimi', { prompt: args.prompt, conversationId: args.conversation_id, maxPolls: args.max_wait_polls }),
  consult_check: (args) => check(args.conversation_id, args.max_wait_polls),
  consult_list: () => ({
    ok: true,
    conversations: ledger.listConversations().map((c) => ({
      id: c.id,
      provider: c.provider,
      status: c.status,
      turns: c.turns,
      url: c.url,
      updated_at: c.updated_at,
    })),
    budget: ledger.snapshot(),
    tip: 'pass conversation_id back to consult_gemini / consult_deepseek to continue a thread; consult_check re-polls without spending.',
  }),
  consult_prompts: (args) => {
    if (!args.template_id) {
      const prompts = listPrompts();
      return {
        ok: true,
        count: prompts.length,
        prompts,
        tip: 'call again with template_id for the full text; replace {{TOKENS}}, redact secrets, then send via consult_gemini or consult_deepseek.',
      };
    }
    const p = getPrompt(args.template_id);
    return {
      ok: true,
      id: p.id,
      title: p.title,
      purpose: p.purpose,
      fill_with: p.fills,
      text: p.text,
      usage_note: 'replace {{TOKENS}} with your material, then pass the finished string as prompt to consult_gemini or consult_deepseek.',
    };
  },
  consult_reset: () => {
    if (!RESET_ALLOWED) {
      return { ok: false, error: 'reset disabled by CONSULT_ALLOW_RESET=0.' };
    }
    ledger.resetLedger();
    return { ok: true, message: 'engagement reset: counters zeroed, conversation ledger cleared.', budget: ledger.snapshot() };
  },
};

const server = new Server({ name: 'consult', version: '0.1.0' }, { capabilities: { tools: {} } });

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOL_DEFS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: rawArgs } = request.params;
  try {
    const def = TOOL_DEFS.find((t) => t.name === name);
    if (!def || !HANDLERS[name]) return respond({ ok: false, status: 'error', error: `unknown tool "${name}"` });
    const args = applyDefaults(def.inputSchema, rawArgs ?? {});
    const errs = validate(def.inputSchema, args);
    if (errs.length) return respond({ ok: false, status: 'error', error: `invalid arguments: ${errs.join('; ')}` });
    return respond(await HANDLERS[name](args));
  } catch (err) {
    return respond({
      ok: false,
      status: 'error',
      error: err instanceof Error ? err.message : String(err),
    });
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('[consult] mcp server listening on stdio');
}

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    closeAll().finally(() => process.exit(0));
  });
}

main().catch((err) => {
  console.error('[consult] fatal:', err);
  process.exit(1);
});
