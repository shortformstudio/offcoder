# cross-platform & form-factor fluidity — upgrade directives

topology reality: the daemon is the platform carrier (mac-only chrome/cdp/disk). fluidity means **the cockpit window adapts on mac**, and **remote hand units (second mac / ipad catalyst / web thin-client) dial into the daemon** — no rewrite of the three-domain architecture.

## 1. responsive breakpoints & fluid typography

- window canvas logic (cockpit `MainCockpitView`): `GeometryReader` + width bands:
  - `≥ 1280`: 4-bay full bento (current)
  - `980–1279`: 3-bay + journal bay folds into a right-side `ScrollView` drawer (tabbed: journal|staging)
  - `760–979`: 2×2 grid (repos+viewport / journal+staging)
  - `< 760` (stage-manager snapshot, tiny splits): single bay with a `TabView`-style segmented top (map|journal|viewport|ring)
- breakpoint constants live in `Theme.swift` as `CockpitLayout.breakpoints(minWidth: 1280/980/760)`; no magic numbers in views.
- type scale: replace hardcoded 8–12pt with `CockpitLayout.type(scale:)` multiplying a base 11pt. fluid rule: `scale = clamp(0.9 + (width - 760) / 2600, 0.9, 1.12)`. elderly-zoom follows system: `@Environment(\.dynamicTypeSize)` maps into the same scale fn — a user who lifts text size in system settings lifts the whole deck.

## 2. context-aware input (touch vs pointer vs keyboard)

- **precision pointer (mac default):** keep hover affordances.
- **touch (ipad catalyst, or touchscreen mac):** all interactive rows get `.contentShape(Rectangle())` + min target 28×28pt (up from current chip ~20); staging `PASS/FAIL` chips grow to touchable for `voice-control` too.
- **keyboard:**
  - `Cmd+F` focus Fresh Project name field in modal; `Esc` closes modal;
  - `Cmd+1..4` focus bays; `Space` toggles viewport pause (stops consuming frames — battery win);
  - `Cmd+R` pull selected repo; `Cmd+N` (via `Scene` `commands`) new window.
- **distribution safety:** `Menu commands` + `.keyboardShortcut` in the modal; never a global event tap for this domain.

## 3. multi-window & split-screen state retention

- `WindowGroup` already yields one VM per window; retain what matters across windows/snaps:
  - use `@AppStorage("selectedRepo")` and `@AppStorage("journalSessionId")` so each window opens on the last context (`RestoresSession = .automatic`);
  - frame stream must be **one consumer per socket**: coalescing lives in `OrchestratorViewModel` — multiple windows each open their own `ws` connection; daemon broadcasts to all (already `channel.broadcast` to all clients — correct). bandwidth note: per-window full-frame stream at 30fps × 3 windows = 9MB/s — throttle with `attachScreencast`'s ac/battery policy and cap concurrent window sessions (only the focused window triggers `send('screencast:subscribe')`; others get 1fps poster).
  - split-screen/stage-manager: `windowStyle(.hiddenTitleBar)` + movable background already tested; add `windowResizability(.contentSize)` on the 4-bay layout so macOS tiling keeps all bays visible at min width 1080; smaller windows engage the breakpoint decks (1).
- persistence: `OrchestratorViewModel` gets `encode(to:)`/`decode(from:)` via `Codable` snapshot (journal list is server-truth anyway; only local choices persist).

## 4. continuity / handoff devices → daemon

- the daemon is the continuity anchor; hand-off = reconnect to the same session id.
  - `connect(host, port, sessionId)` + `resume` command; daemon answers `session_snapshot` (journal tail 20, staging ring last 10, queue counts);
  - second device binds `ORCH_WS_HOST=0.0.0.0` + `ORCH_WS_TOKEN` env; ipc handshake requires `token` in the first client frame (`CMD {auth}`), else 1008 close — keeps LAN paranoia honest;
  - ipc messages already carry `sessionId` (`journal`, `plan_queued`) — snapshot key is already there; add `task_event` broadcast with `{taskId, status}` so a remote deck sees live state without polling;
  - single screen swap: cockpit shows `IPC state` + session pill (`⌖ mesh-router`) — a quick `Cmd+Shift+R` resumes the last session from `@AppStorage`.
- true handoff across *mac↔ipad*: file-free, id-based. the browser + disk stay on the mac; the thin remote is a *monitor*. this is the deliberate design: no UIDocument sync, no keychain cross-device — the daemon owns substance, remotes own eyes.

## 5. implementation order

1. breakpoint constants + type scale + stage-deck collapse (cockpit only, 1 day)
2. keyboard shortcuts + confirmations + accessibility labels (cockpit, 0.5 day)
3. `@AppStorage` session retention + per-window stream subscribe control (cockpit + ipc cap, 1 day)
4. ws auth token + `session_snapshot` + `task_event` broadcast (daemon, 0.5 day)
5. remote thin deck: optional `cockpit-remote/` (swiftui, same sources, ORCH_HOST env) then foldable canvas test via stage-manager snapshots.
