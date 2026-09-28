# explore → surf

`explore` is now **`surf`** (canonical).

- New MCP: `mcp-server/surf/index.js` — tools `surf_search`, `surf_read`, `surf_plan`, `surf_wander`
- Old `explore_*` tools remain as legacy aliases inside `surf` (backward compat)
- Keep `mcp-server/explore/index.js` for reference, but all new code and opencode registration use `surf`
- Trigger: type `/surf` at the start of your prompt

Sync: this mirrors `~/Documents/modular/mcp-server/surf/` which is registered in `~/.config/opencode/opencode.jsonc` as `surf`.
