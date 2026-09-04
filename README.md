# Offcoder: Autonomous Inference Offload & Zero-Loss Coding Harness

<p align="center">
  <img src="docs/assets/explainer_page-1.png" width="70%" alt="Offcoder 1-Page System Architecture Explainer" />
</p>

<p align="center">
  <a href="OFFCODER_EXPLAINER.pdf"><b>Download 1-Page Architecture Explainer PDF</b></a> &nbsp;|&nbsp; 
  <a href="offcoder-full-with-dependencies.zip"><b>Download Complete Bundle (.ZIP)</b></a>
</p>

---

## What is Offcoder?

Offcoder is a local-first coding harness pairing LAN-hosted models with automated headless web audits:

- **Local Development Agency**: The local model inspects codebases, drafts changes, and commits baseline snapshots.
- **Headless Web Auditing**: Audits are offloaded to frontier reasoning models (**DeepSeek R1** for security/algorithms, **Kimi** for visual UI) through automated stealth browser sessions at **$0.00 ingress API cost**.
- **Immutable Diff Tracking**: Pre-audit baselines and returned revisions are tracked with **$O(N+M)$ trimmed LCS visual diffs**.
- **Closed-Loop Test Execution**: Audited code is automatically verified against local compilers, linters, and test suites (`pytest`, `npm test`, `swift build`).
- **Live Reflection Window**: Outbound prompts and inbound tokens stream live to a native floating macOS window mirroring background browser processes.

---

## Core System Specifications

| Domain / Subsystem | Runtime Stack | Interfaces | Primary Roles |
| :--- | :--- | :--- | :--- |
| **Native Cockpit** | SwiftUI / AppKit (Swift 5.9, macOS 13+) | WS `:7171`<br>HTTP `:8080` / `:8000` | 60fps supervisor deck, real-time visual diff inspector, live Web Reflection viewer, and project artifact drawer. |
| **Automation Daemon** | Node.js 20+ / TypeScript | WS Server `:7171`<br>CDP `:9222` | Puppeteer stealth browser engine, screencast broker, git tree-sitter AST indexer, and transactional task leasing ring. |
| **Dispatcher Gateway** | Python 3.13 / FastAPI | HTTP `:8000`<br>OpenAI Compatible | Local model proxy, DOM layout map extraction for text models, and task verification worker with backoff retries. |
| **Memory Core** | SQLite 3 (WAL mode) | `~/.local_orchestrator/state.db` | Zero-loss ACID state storage for repos, context nodes, session journals, task queue, and staging ring. |

---

## Audit & Verification Loop

```
01 // DRAFT        Local model creates code draft; immutable v0 baseline snapshot stored to SQLite WAL ring.
02 // OFFLOAD      Stealth browser offloads audit to DeepSeek or Kimi; live reflection streams to UI.
03 // DIFF         Computes line-by-line mutation window in O(N+M) with instant visual diff display.
04 // VERIFY       Executes native linters, compilers, and test suites before committing changes to workspace.
```

---

## Repository Files

- **[OFFCODER_EXPLAINER.pdf](OFFCODER_EXPLAINER.pdf)**: Crisp, 1-page architecture explainer in Moonpond dark navy, ruby, and turquoise.
- **[offcoder-full-with-dependencies.zip](offcoder-full-with-dependencies.zip)**: Standalone 58MB zip bundle with all code, scripts, tools, and `node_modules` dependencies.
- **[docs/assets/explainer_page-1.png](docs/assets/explainer_page-1.png)**: High-resolution preview image of the 1-page PDF.
- **[cockpit/](cockpit/)**: Native macOS SwiftUI cockpit deck.
- **[daemon/](daemon/)**: Automation daemon with Puppeteer CDP driver and tree-sitter indexer.
- **[dispatcher/](dispatcher/)**: Python FastAPI local model gateway and task verification worker.
- **[mcp-server/](mcp-server/)**: Model Context Protocol stealth audit engine.

---

## Quickstart

```bash
# 1. Launch Chrome with isolated CDP debugging profile
./scripts/chrome_launch.sh

# 2. Run Daemon
cd daemon && npm install && npm run dev

# 3. Run Dispatcher
cd ../dispatcher && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt && uvicorn src.main:app --port 8000

# 4. Launch Native Cockpit Deck
cd ../cockpit && swift run
```
