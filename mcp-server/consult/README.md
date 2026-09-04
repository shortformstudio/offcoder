# consult

MCP server that lets an LLM audit applications, code, and designs by consulting **web Gemini** (gemini.google.com) and **web DeepSeek** (chat.deepseek.com) through a real, logged-in, stealth browser session.

The driving LLM initiates conversations, waits 15 seconds at a time while the web model streams, keeps waiting until the answer settles, then decides whether another consult earns its cost — up to **10 consults across a maximum of 10 conversations** per engagement.

## Install

```bash
cd ~/Desktop/modular/mcp-server/consult
npm install
npx playwright install chromium   # headless/fallback engine; daily use drives system Chrome
npm run smoke                     # stdio jsonrpc self-test
```

## First-run login

The first `consult_gemini` / `consult_deepseek` call opens a visible Chrome window at the site. Sign in manually once — cookies persist in `~/.config/consult/profiles/<provider>` and every later run reuses the warm session. The tool replies with `status: "login_required"`; retry the exact same call after signing in.

## Registration

opencode (`~/.config/opencode/opencode.jsonc`):

```jsonc
"consult": {
  "type": "local",
  "command": ["node", "mcp-server/consult/index.js"],
  "cwd": "/Users/stevenjackson/Desktop/modular",
  "enabled": true
}
```

Any other MCP harness:

```json
{
  "mcpServers": {
    "consult": {
      "command": "node",
      "args": ["/Users/stevenjackson/Desktop/modular/mcp-server/consult/index.js"]
    }
  }
}
```

Restart opencode after editing its config.

## Tools

| tool | spends | what it does |
| --- | --- | --- |
| `consult_gemini` | 1 consult | sends a prompt to web Gemini, polls every 15s until the response settles |
| `consult_deepseek` | 1 consult | same against web DeepSeek |
| `consult_check` | free | re-polls an in-flight thread after a `status: "generating"` reply |
| `consult_list` | free | all threads + remaining budget |
| `consult_prompts` | free | prewritten audit prompt library (12 templates) or one full template via `template_id` |
| `consult_reset` | free | starts a fresh engagement: counters zeroed, ledger cleared (`confirm: true`) |

Every send returns JSON with `status`, `response_text`, `conversation_id`, thread `url`, poll counts, and the live budget block.

## Audit workflow

1. `consult_prompts` → pick a template.
2. Replace `{{TOKENS}}` with your material. Redact secrets first.
3. Optionally open with `kickoff_context_primer` once per provider so follow-ups inherit context.
4. Send via `consult_gemini` / `consult_deepseek`.
5. On `generating`, keep calling `consult_check` — never resend the prompt.
6. Cross-examine: feed findings from one model into `verify_findings` and send to the other.
7. Merge with `synthesis_merge`; gate the release with `release_signoff`.

Templates: `kickoff_context_primer`, `code_audit_deep`, `security_audit`, `architecture_review`, `ui_design_critique`, `bug_triage`, `performance_review`, `refactor_blueprint`, `spec_polish`, `verify_findings`, `synthesis_merge`, `release_signoff`.

## Stealth layer

- launches your real Chrome (`channel: chrome`) under a dedicated persistent profile — bundled chromium is fallback only
- strips Playwright's automation flags (`--enable-automation`) and `navigator.webdriver`
- patches window.chrome, plugin/mime arrays, languages, permissions query, WebGL vendor/renderer, hardware hints via init script on every document
- humanized pacing: randomized pauses, cursor approach before clicks, minimum gap between sends
- headed mode by default; headless is available but detects more easily

## Environment variables

| var | default | meaning |
| --- | --- | --- |
| `CONSULT_POLL_MS` | `15000` | pause length between completion checks |
| `CONSULT_MAX_POLLS` | `20` | polls per call before yielding as `generating` |
| `CONSULT_IDLE_MS` | `5000` | DOM idle threshold counting as settled |
| `CONSULT_MAX_CONSULTS` | `10` | sends per engagement |
| `CONSULT_MAX_CONVERSATIONS` | `10` | threads per engagement |
| `CONSULT_MAX_PROMPT_CHARS` | `80000` | per-send size cap |
| `CONSULT_MIN_SEND_GAP_MS` | `4000` | humanizing gap between sends |
| `CONSULT_HEADLESS` | off | `1` runs without a visible window |
| `CONSULT_CHANNEL` | `chrome` | browser channel; `chromium` uses the bundled build |
| `CONSULT_STATE_DIR` | `~/.config/consult` | ledger + browser profiles home |
| `CONSULT_ALLOW_RESET` | on | `0` disables `consult_reset` |

## Troubleshooting

- **Google blocks sign-in in the opened window**: sign in inside that window exactly like a normal user; if it still refuses, quit opencode, set `CONSULT_CHANNEL=chromium`, start one consult, and complete login there, then switch back — or temporarily copy cookies into `~/.config/consult/profiles/gemini`.
- **Selectors drift when Gemini/DeepSeek redesign**: adapters live in `lib/gemini.js` and `lib/deepseek.js`; each selector list has fallbacks, update the first entry when UIs change.
- **Budget exhausted mid-audit**: finish the current thread with `consult_check`, weigh the cost, then `consult_reset`.

## Layout

```
index.js            stdio server + tool registry
lib/config.js       env-derived settings
lib/browser.js      persistent contexts, mutex, lifecycle
lib/stealth.js      fingerprint patches + humanized input
lib/watcher.js      DOM mutation settle detection
lib/session.js      send/poll orchestration + budget enforcement
lib/gemini.js       Gemini adapter
lib/deepseek.js     DeepSeek adapter
lib/prompts.js      12-template audit prompt library
lib/ledger.js       engagement persistence (~/.config/consult/ledger.json)
scripts/smoke.mjs   stdio jsonrpc self-test
```
