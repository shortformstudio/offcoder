# performance audit — resource optimization directives

audit targets: daemon (node), cockpit (swift), dispatcher (python). baseline = current scaffold state.

## 1. bundle & footprint

- **daemon is the 40% win.** `web` runtime: current deps ship 4 tree-sitter grammar binaries (each ~2-6MB prebuilt) even though `github_sync.loadLanguage` already lazily imports them. directive: move `tree-sitter-go/python/rust/typescript` to `optionalDependencies` (load failures already fall back to regex), and mark the three heavy `tree-sitter-*` (python+rust+typescript ≈ 12MB) behind `npm install --workspace … --omit=optional` on headless machines. depth: grammars now optional in `package.json` field, zero code change.
- **module graph.** transitions: split `index.ts` boot into `index.entry` that lazy-loads `browser_broker` (only when cdp up) via `await import`, so a queue-only/headless run never pages in puppeteer (11MB+). puppeteer-core is the single largest dep after node_modules strip.
- **build step.** add `"build": "tsc && esbuild src/index.ts --bundle --platform=node --format=esm --outfile=dist/daemon.js --external:better-sqlite3 --external:tree-sitter*"` — one file, native mods external. plus `.npmignore`/files whitelist `[dist, src, schema]` so releases carry ~1MB not 300MB node_modules.
- **dispatcher.** split `requirements.txt` into `requirements-web.txt` (fastapi, uvicorn) + `requirements-worker.txt` (httpx). the worker path imports only `config, model_backend`; uvicorn `--no-access-log --workers 1` and `pip install --no-cache-dir` per stage. replace httpx in worker-only mode with stdlib `urllib.request` if bytes matter (httpx exists because streaming handles the api; keep for now).
- **cockpit.** swift release: `-O -whole-module-optimization` with `dSYM` stripped (SPM `settings: [.unsafeFlags(["-O","-whole-module-optimization"])]` in release overrides); usage of system fonts already zero-cost (no embedded font assets).

## 2. re-renders, layout thrash, main-thread work

- **frame path (the hot loop).** `OrchestratorViewModel.handle` decodes `NSImage(data:)` per frame on the main thread, and `ViewportView` re-layouts `resizable().aspectRatio(fit)` each frame. directive:
  1. receive → enqueue into a `Task`-free shared box (last-wins) → let a serial decode queue drain latest-only (drop while busy);
  2. set the bay to a fixed aspect container (16:9) so the image never changes layout;
  3. decode via `CGImageSourceCreateWithData` (thumbnail-for image, `kCGImageSourceCreateThumbnailFromImageAlways`) so cost is bounded by the display, not the 1440×900 source.
- **swiftui list churn.** `List` with `listRowBackground` recalculates per selection change on a 100-item list — cheap. the real churn: journal append inserts at 0 → `ForEach` diff on `JournalItem.id = UUID()` — fine, but cap `journalEntries` at 80 (pop tail) and `stagingCandidates` at 60 with explicit `.id` (id is per-struct, keep).
- **engine-side throttle.** `attachScreencast` sends `everyNthFrame: 1, quality: 60` → ~3-6MB/s of jpg. directive: base setup `everyNthFrame: 2, quality: 45, maxWidth: 1280`; adaptive edge — read `pmset -g batt` (interval 2min) → battery < 30% ⇒ `everyNthFrame: 4, quality: 30`; plus **skip identical frames** (hash of buffer; if equal last ⇒ skip unless 5s). ack for frames it sent, never backlog acks.
- **layout thrash — syncIndex.** recomputing checksums inside one tx (see adversarial #16) is also host CPU burst: read+hash 20k files = hundreds of MB; use `readFile` + `crypto.hash('sha256')` streaming w/ `concurrency 8` chunked outside tx, plus skip unchanged (`checksum` same ⇒ skip upsert — cheaper than write).

## 3. asset loading & caching

- `repo_registry` already caches trees: `listOrgRepos` should hit sqlite first (TTL 10min) before `gh`/REST. gh spawn per call = ~2s; cache eliminates it.
- screenshots: dedupe by sha-256 (`screenshot_path` already keyed by taskId; identical frames from retries → skip write when same buffer); retention prune: keep newest 200 files / 14 days on daemon boot.
- tree-sitter `grammarCache` already memoizes; add `MAX_FILE_BYTES` skip already in place; documents with `\0` skipped. good.
- ws: no asset cache issue — frames are ephemeral and last-wins.

## 4. 60+ fps on low-tier legacy hardware

- legacy = slow single-core + 8GB mac. frame deadline budget on that class: screencast 30fps target max (own the input, not the browser). directives:
  - cockpit coalescing (above) gives smoothness even at 5fps effective decode — jank is never per-frame decode;
  - `ViewportView` uses fixed-aspect + `.interpolation(.medium)` so no resample per repaint;
  - daemon frame ticker releases the head: ack immediately, enqueue on the ws socket without per-frame `broadcast` re-encode — message JSON stringify per frame is fine, but avoid `JSON.stringify` of the message twice (broadcast builds one string — good);
  - **memory bound:** drop any frame whose base64 string exceeds 512KB (400KB typical) without decode.
- telemetry hook (later): `perf` command in ipc returning frame rate + last-frame-ms; cockpit shows it in the bay title.

## 5. battery policy (summary table)

| runtime state | screencast | decode | polling |
|---|---|---|---|
| ac / idle | everyNthFrame 2, q45, 1280 | on-screen coalesced | journal poll 10s |
| battery > 30% | everyNthFrame 2, q45 | coalesced | poll 30s |
| battery < 30% | everyNthFrame 4, q30 | decode-on-show | poll 120s + sweep interval 120s |

low-tier fallback: swap `quality 45 → 25` and require the cockpit to render at half-resolution with `kCGImageSourceThumbnailMaxPixelSize 900`.
