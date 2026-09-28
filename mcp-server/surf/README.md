# surf

MCP server for web research and exploration. Trigger with **`/surf`** at the start of your prompt.

Formerly `explore` — surf is the canonical name. `explore_*` tools remain as legacy aliases for backward compatibility.

## Tools

| tool | what it does |
|---|---|
| `surf_search` | Search the open web via Bing/DuckDuckGo/Wikipedia. Returns ranked titles, URLs, snippets. |
| `surf_read` | Fetch a URL and return clean text (scripts/nav stripped). |
| `surf_plan` | Multi-angle research: searches, reads top pages, compiles a cited markdown brief. `summarize=true` uses local model digests. |
| `surf_wander` | Crawl same-domain links from a seed URL, returns page map. |

All tools have `explore_*` aliases (e.g., `explore_search` → `surf_search`).

## Trigger

Type `/surf` at the beginning of your prompt:

```
/surf what is the latest Next.js 15 app router pattern
/surf research the Python 3.12 f-string debugging feature
```

The agent will call `surf_search`/`surf_read`/`surf_plan` automatically.

## Install

```bash
cd ~/Documents/modular/mcp-server/surf
# no extra deps beyond shared lib/mcp-stdio.js
node --check index.js
```

Registered in `~/.config/opencode/opencode.jsonc` as `surf`:

```jsonc
"surf": {
  "type": "local",
  "command": ["/opt/homebrew/bin/node", "mcp-server/surf/index.js"],
  "cwd": "/Users/stevenjackson/Documents/modular",
  "enabled": true
}
```

Restart opencode after editing config.

## Env

- `SURF_MODEL_URL` (fallback `EXPLORE_MODEL_URL`) — local model for `summarize` digests, default `http://127.0.0.1:8000/v1/chat/completions`
- `SURF_MODEL` (fallback `EXPLORE_MODEL`) — model name, default `qwythos/qwythos`

## Offload mirror

Same server at `~/Documents/DEVELOPMENT/WILD CARD/inference offload/mcp-server/surf/index.js` (shared `lib/mcp-stdio.js`). Keeps inference-offload and modular in sync.
