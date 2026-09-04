#!/usr/bin/env python3
"""
Generate a publication-grade PDF Explainer for 'Offcoder / Inference Offload'.
Aesthetic: Moonpond-inspired, deep dark navies, effervescent ruby, and radiant turquoise.
Renders to PDF via Google Chrome headless and exports high-resolution page previews for GitHub display.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
OUTPUT_PDF = ROOT_DIR / "OFFCODER_EXPLAINER.pdf"
HTML_REPORT = ROOT_DIR / "docs" / "OFFCODER_EXPLAINER.html"
ASSETS_DIR = ROOT_DIR / "docs" / "assets"

HTML_CONTENT = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Offcoder — Zero-Loss Local-First Inference Offload & Coding Harness</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700;800&family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&display=swap');

  @page {
    size: A4 portrait;
    margin: 12mm 14mm 14mm 14mm;
    @bottom-left {
      content: "OFFCODER // Inference Offload System Architecture";
      font-family: 'JetBrains Mono', monospace;
      font-size: 7pt;
      color: #52637a;
      letter-spacing: 0.5px;
    }
    @bottom-right {
      content: "PAGE " counter(page) " OF " counter(pages);
      font-family: 'JetBrains Mono', monospace;
      font-size: 7pt;
      font-weight: 700;
      color: #00f2fe;
      letter-spacing: 1px;
    }
  }

  * {
    box-sizing: border-box;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }

  body {
    font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    color: #e2e8f0;
    background: #060913;
    font-size: 8.8pt;
    line-height: 1.48;
    margin: 0;
    padding: 0;
  }

  .page-break {
    page-break-before: always;
  }

  /* Typography & Accents */
  h1, h2, h3, h4 {
    font-family: 'Plus Jakarta Sans', sans-serif;
    color: #ffffff;
    margin: 0;
    letter-spacing: -0.3px;
  }

  .font-mono {
    font-family: 'JetBrains Mono', monospace;
  }

  /* Glows & Gradients */
  .ruby-glow {
    color: #ff2a6d;
    text-shadow: 0 0 16px rgba(255, 42, 109, 0.45);
  }

  .turquoise-glow {
    color: #00f2fe;
    text-shadow: 0 0 16px rgba(0, 242, 254, 0.45);
  }

  .emerald-glow {
    color: #05d5b0;
    text-shadow: 0 0 14px rgba(5, 213, 176, 0.4);
  }

  /* Header Cover Area */
  .cover-header {
    position: relative;
    border-radius: 14px;
    background: linear-gradient(135deg, #0d1326 0%, #080c1a 100%);
    border: 1px solid rgba(0, 242, 254, 0.22);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.08);
    padding: 20px 24px;
    margin-bottom: 18px;
    overflow: hidden;
  }

  .cover-header::after {
    content: "";
    position: absolute;
    top: -50px;
    right: -40px;
    width: 220px;
    height: 220px;
    background: radial-gradient(circle, rgba(255, 42, 109, 0.18) 0%, rgba(0, 242, 254, 0.12) 50%, transparent 75%);
    pointer-events: none;
  }

  .brand-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: rgba(0, 242, 254, 0.08);
    border: 1px solid rgba(0, 242, 254, 0.35);
    color: #00f2fe;
    padding: 4px 10px;
    border-radius: 20px;
    font-size: 7.2pt;
    font-weight: 700;
    font-family: 'JetBrains Mono', monospace;
    letter-spacing: 1.2px;
    text-transform: uppercase;
    margin-bottom: 10px;
  }

  .brand-badge .dot {
    width: 6px;
    height: 6px;
    background: #ff2a6d;
    border-radius: 50%;
    box-shadow: 0 0 8px #ff2a6d;
  }

  .title-group h1 {
    font-size: 23pt;
    font-weight: 800;
    line-height: 1.12;
    margin-bottom: 6px;
    background: linear-gradient(90deg, #ffffff 30%, #00f2fe 75%, #ff2a6d 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }

  .title-group .lead {
    font-size: 9.8pt;
    color: #94a3b8;
    max-width: 90%;
    line-height: 1.45;
  }

  /* Stat Counter Ribbons */
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
    margin-bottom: 18px;
  }

  .stat-card {
    background: #090e1f;
    border: 1px solid rgba(255, 255, 255, 0.06);
    border-radius: 10px;
    padding: 12px 14px;
    position: relative;
    overflow: hidden;
  }

  .stat-card.accent-ruby {
    border-top: 2px solid #ff2a6d;
    background: linear-gradient(180deg, rgba(255, 42, 109, 0.08) 0%, #090e1f 60%);
  }

  .stat-card.accent-turquoise {
    border-top: 2px solid #00f2fe;
    background: linear-gradient(180deg, rgba(0, 242, 254, 0.08) 0%, #090e1f 60%);
  }

  .stat-card.accent-emerald {
    border-top: 2px solid #05d5b0;
    background: linear-gradient(180deg, rgba(5, 213, 176, 0.08) 0%, #090e1f 60%);
  }

  .stat-card.accent-violet {
    border-top: 2px solid #a855f7;
    background: linear-gradient(180deg, rgba(168, 85, 247, 0.08) 0%, #090e1f 60%);
  }

  .stat-num {
    font-family: 'JetBrains Mono', monospace;
    font-size: 15pt;
    font-weight: 800;
    margin-bottom: 2px;
  }

  .stat-label {
    font-size: 7.2pt;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    color: #94a3b8;
    font-weight: 600;
  }

  /* Section Styles */
  .section-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 11pt;
    font-weight: 700;
    color: #ffffff;
    margin: 18px 0 10px 0;
    padding-bottom: 6px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  }

  .section-tag {
    font-family: 'JetBrains Mono', monospace;
    font-size: 7pt;
    padding: 2px 7px;
    border-radius: 4px;
    background: rgba(0, 242, 254, 0.12);
    color: #00f2fe;
    border: 1px solid rgba(0, 242, 254, 0.3);
  }

  /* Grid Layouts */
  .grid-2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }

  .grid-3 {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }

  /* Feature & Architecture Cards */
  .card {
    background: #090e1f;
    border: 1px solid rgba(255, 255, 255, 0.07);
    border-radius: 10px;
    padding: 13px 15px;
    position: relative;
  }

  .card-title {
    font-size: 9.6pt;
    font-weight: 700;
    color: #ffffff;
    margin-bottom: 5px;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .card p {
    margin: 0;
    color: #94a3b8;
    font-size: 8.3pt;
    line-height: 1.42;
  }

  /* Diagram & Pipeline Visuals */
  .pipeline-flow {
    background: #070c1a;
    border: 1px solid rgba(0, 242, 254, 0.2);
    border-radius: 10px;
    padding: 14px;
    margin: 12px 0;
  }

  .flow-step {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    margin-bottom: 10px;
    position: relative;
  }

  .flow-step:last-child {
    margin-bottom: 0;
  }

  .step-badge {
    flex-shrink: 0;
    width: 26px;
    height: 26px;
    border-radius: 50%;
    background: #0e172e;
    border: 1px solid #00f2fe;
    color: #00f2fe;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: 'JetBrains Mono', monospace;
    font-size: 8pt;
    font-weight: 700;
    box-shadow: 0 0 10px rgba(0, 242, 254, 0.3);
  }

  .step-badge.ruby {
    border-color: #ff2a6d;
    color: #ff2a6d;
    box-shadow: 0 0 10px rgba(255, 42, 109, 0.3);
  }

  .step-content {
    flex-grow: 1;
  }

  .step-header {
    font-size: 8.8pt;
    font-weight: 700;
    color: #ffffff;
    margin-bottom: 2px;
  }

  .step-desc {
    font-size: 8pt;
    color: #94a3b8;
    line-height: 1.35;
  }

  /* Table Design */
  table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
    margin: 10px 0;
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 8px;
    overflow: hidden;
    font-size: 8pt;
  }

  thead {
    background: #0d152b;
  }

  th {
    text-align: left;
    padding: 7px 11px;
    font-weight: 700;
    font-size: 7.3pt;
    text-transform: uppercase;
    letter-spacing: 0.7px;
    color: #00f2fe;
    border-bottom: 1px solid rgba(0, 242, 254, 0.2);
  }

  td {
    padding: 7px 11px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.04);
    color: #cbd5e1;
    vertical-align: top;
  }

  tr:last-child td {
    border-bottom: none;
  }

  tr:nth-child(even) td {
    background: rgba(255, 255, 255, 0.015);
  }

  .badge-tag {
    display: inline-block;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 6.8pt;
    font-weight: 700;
    font-family: 'JetBrains Mono', monospace;
  }

  .tag-ruby {
    background: rgba(255, 42, 109, 0.15);
    color: #ff2a6d;
    border: 1px solid rgba(255, 42, 109, 0.35);
  }

  .tag-turquoise {
    background: rgba(0, 242, 254, 0.15);
    color: #00f2fe;
    border: 1px solid rgba(0, 242, 254, 0.35);
  }

  .tag-emerald {
    background: rgba(5, 213, 176, 0.15);
    color: #05d5b0;
    border: 1px solid rgba(5, 213, 176, 0.35);
  }

  /* Code & Callout Blocks */
  .code-pill {
    background: #0b1124;
    border: 1px solid rgba(0, 242, 254, 0.25);
    border-radius: 4px;
    padding: 1px 5px;
    color: #00f2fe;
    font-family: 'JetBrains Mono', monospace;
    font-size: 7.6pt;
  }

  .callout-box {
    border-radius: 8px;
    padding: 11px 14px;
    margin: 12px 0;
    border-left: 3px solid;
    background: #080d1e;
  }

  .callout-box.ruby {
    border-color: #ff2a6d;
    background: linear-gradient(90deg, rgba(255, 42, 109, 0.08) 0%, #080d1e 100%);
  }

  .callout-box.turquoise {
    border-color: #00f2fe;
    background: linear-gradient(90deg, rgba(0, 242, 254, 0.08) 0%, #080d1e 100%);
  }

  .callout-title {
    font-size: 8.5pt;
    font-weight: 700;
    margin-bottom: 3px;
  }
</style>
</head>
<body>

<!-- PAGE 1: EXECUTIVE VISION & KEY DRIVERS -->
<div class="cover-header">
  <div class="brand-badge">
    <span class="dot"></span>
    OFFCODER ARCHITECTURE EXPLAINER
  </div>
  <div class="title-group">
    <h1>Autonomous Inference Offload</h1>
    <div class="lead">
      A zero-loss, local-first coding harness pairing local intelligence with frontier web models for high-throughput, private, and continuously audited codebases.
    </div>
  </div>
</div>

<div class="stats-grid">
  <div class="stat-card accent-turquoise">
    <div class="stat-num turquoise-glow font-mono">$0.00</div>
    <div class="stat-label">API Ingress Cost</div>
  </div>
  <div class="stat-card accent-ruby">
    <div class="stat-num ruby-glow font-mono">100%</div>
    <div class="stat-label">Local Data Privacy</div>
  </div>
  <div class="stat-card accent-emerald">
    <div class="stat-num emerald-glow font-mono">O(N+M)</div>
    <div class="stat-label">Trimmed LCS Diffing</div>
  </div>
  <div class="stat-card accent-violet">
    <div class="stat-num font-mono" style="color: #c084fc;">Zero-Loss</div>
    <div class="stat-label">Version Audit Ring</div>
  </div>
</div>

<div class="section-title">
  <span>1. What is Offcoder in Plain English?</span>
  <span class="section-tag">OVERVIEW</span>
</div>

<p style="font-size: 9pt; color: #cbd5e1; margin-bottom: 12px;">
  Modern software engineering with AI usually presents an agonizing tradeoff: either you send your entire intellectual property to expensive proprietary cloud APIs (paying per-token with unpredictable rate limits and latency), or you run local models (like <em>Qwythos, Qwen, or Ollama</em>) that operate privately on your LAN but occasionally miss subtle edge cases, architectural traps, or deep algorithmic security pitfalls.
</p>
<p style="font-size: 9pt; color: #cbd5e1; margin-bottom: 12px;">
  <strong>Offcoder solves this completely.</strong> It gives your local model an apex coding harness equipped with live workspace read/write capabilities, real test and linter execution loops, durable architectural memory, and an automated <strong>dual-engine web audit loop</strong>. When your local model writes critical algorithms or UI layouts, it transparently offloads audits to frontier models (DeepSeek for algorithmic/security rigor; Kimi for visual design) through a real headless stealth browser session. Every draft, critique, and revision is immutably cached with instant visual diff tracking.
</p>

<div class="section-title">
  <span>2. The Core Value Drivers</span>
  <span class="section-tag">VALUE PROPOSITION</span>
</div>

<div class="grid-3">
  <div class="card">
    <div class="card-title">
      <span>Zero Cloud Lock-In</span>
      <span class="badge-tag tag-turquoise">SOVEREIGNTY</span>
    </div>
    <p>
      Runs entirely on your local machine and LAN. All codebase files, git AST indexes, and conversational logs remain anchored in your private SQLite memory ring and disk workspace.
    </p>
  </div>

  <div class="card">
    <div class="card-title">
      <span>Frontier Power at $0</span>
      <span class="badge-tag tag-ruby">HEADLESS CDP</span>
    </div>
    <p>
      Harnesses frontier reasoning capabilities (DeepSeek R1 and Kimi) using automated, rate-resilient browser automation. Bypasses token metering while capturing elite code reviews.
    </p>
  </div>

  <div class="card">
    <div class="card-title">
      <span>Verified Closed Loop</span>
      <span class="badge-tag tag-emerald">EXECUTION FEEDBACK</span>
    </div>
    <p>
      No hallucinations in production. Offcoder immediately executes local linters, compilers, and test suites (pytest, npm test, swift build) feeding execution output directly back into context.
    </p>
  </div>
</div>

<div class="callout-box turquoise" style="margin-top: 14px;">
  <div class="callout-title turquoise-glow">THE GOLDEN WORKFLOW FOR LOCAL DEVELOPERS</div>
  <div style="font-size: 8.2pt; color: #cbd5e1;">
    <strong>Explore Codebase &rarr; Draft Implementation &rarr; Offline Baseline Commit &rarr; Headless Frontier Audit &rarr; Trimmed Diff Resolution &rarr; Test Suite Verification.</strong> Offcoder ensures that your local AI has the exact same agency, rigor, and safety checks as an elite senior engineering team.
  </div>
</div>

<!-- PAGE 2: MULTI-PROCESS ARCHITECTURE & AUDITING PIPELINE -->
<div class="page-break"></div>

<div class="section-title" style="margin-top: 0;">
  <span>3. Multi-Process Tri-Domain Architecture</span>
  <span class="section-tag">SYSTEM TOPOLOGY</span>
</div>

<p style="font-size: 8.8pt; color: #94a3b8; margin-bottom: 12px;">
  Offcoder orchestrates three specialized, decoupled processes that communicate through high-throughput IPC and share an ACID SQLite write-ahead log (WAL) database:
</p>

<table>
  <thead>
    <tr>
      <th>Runtime Domain</th>
      <th>Technology Stack</th>
      <th>Network / IPC Boundary</th>
      <th>Primary Responsibilities</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong style="color: #ffffff;">Native Cockpit Deck</strong></td>
      <td>SwiftUI / AppKit (Swift 5.9)<br><span class="code-pill">macOS 13+</span></td>
      <td>WebSocket Client <span class="code-pill">:7171</span><br>HTTP Client <span class="code-pill">:8080 / :8000</span></td>
      <td>Real-time 60fps supervisor deck, trimmed LCS visual diff view, floating Web Reflection window, interactive chat, and project deliverables viewer.</td>
    </tr>
    <tr>
      <td><strong style="color: #ffffff;">Automation Daemon Core</strong></td>
      <td>Node.js 20+ / TypeScript<br><span class="code-pill">Puppeteer + Tree-Sitter</span></td>
      <td>WebSocket Server <span class="code-pill">:7171</span><br>CDP Bridge <span class="code-pill">:9222</span></td>
      <td>Stealth browser automation (DeepSeek/Kimi/Gemini), screencast frame broker, git AST parsing, transactional task lease ring, and Prometheus metrics.</td>
    </tr>
    <tr>
      <td><strong style="color: #ffffff;">Dispatcher & Local Harness</strong></td>
      <td>Python 3.13 / FastAPI<br><span class="code-pill">Asyncio + SQLite WAL</span></td>
      <td>OpenAI Compatible <span class="code-pill">:8000</span><br>LAN Model Gateway</td>
      <td>OpenAI-compatible proxy, vision vs. text routing (DOM layout map extraction), background task verification worker, and exponential backoff retry manager.</td>
    </tr>
  </tbody>
</table>

<div class="section-title">
  <span>4. The Zero-Loss Version & Diff Audit Ring</span>
  <span class="section-tag">KEY ALGORITHMIC INNOVATION</span>
</div>

<div class="pipeline-flow">
  <div class="flow-step">
    <div class="step-badge">01</div>
    <div class="step-content">
      <div class="step-header">Local Model Drafts Baseline (<span class="code-pill">v0 Baseline</span>)</div>
      <div class="step-desc">
        When the local model generates a function or file, Offcoder automatically captures an immutable snapshot in the version registry. It records author, timestamp, and raw code before any external transmission.
      </div>
    </div>
  </div>

  <div class="flow-step">
    <div class="step-badge ruby">02</div>
    <div class="step-content">
      <div class="step-header">Headless Offload & Web Reflection Window (<span class="code-pill">consult_deepseek</span> / <span class="code-pill">consult_kimi</span>)</div>
      <div class="step-desc">
        The code is sent to DeepSeek or Kimi via a stealth browser session. Simultaneously, Offcoder's <strong>Web Reflection Viewer</strong> pops up on macOS, showing live, real-time prompts and streaming responses directly mirroring the headless browser process.
      </div>
    </div>
  </div>

  <div class="flow-step">
    <div class="step-badge">03</div>
    <div class="step-content">
      <div class="step-header">Trimmed Prefix/Suffix LCS Diff Generation (<span class="code-pill">v1 Audited Revision</span>)</div>
      <div class="step-desc">
        Upon return, an $O(N+M)$ trimmed LCS algorithm matches unchanged prefix and suffix headers, isolating the exact mutation window. A unified line-by-line diff is created and displayed in the Cockpit with emerald additions and ruby deletions.
      </div>
    </div>
  </div>

  <div class="flow-step">
    <div class="step-badge ruby">04</div>
    <div class="step-content">
      <div class="step-header">Closed-Loop Execution Verification (<span class="code-pill">code_feedback</span>)</div>
      <div class="step-desc">
        The audited code is validated with native linters, compilers, and test suites. If tests fail, errors are fed back into context for automated repair.
      </div>
    </div>
  </div>
</div>

<div class="grid-2" style="margin-top: 12px;">
  <div class="card">
    <div class="card-title">
      <span>Semantic Context Compression</span>
      <span class="badge-tag tag-ruby">QWYTHOS NATIVE</span>
    </div>
    <p>
      Context bloat is eliminated without losing traceability. When conversation depth grows, Qwythos semantically distills history into executive briefing anchors while literal verbose transcripts are permanently archived in <span class="code-pill">.agents/logs/conversations/</span>.
    </p>
  </div>

  <div class="card">
    <div class="card-title">
      <span>Project-Centric Artifacts Column</span>
      <span class="badge-tag tag-emerald">ISOLATED REPOS</span>
    </div>
    <p>
      Every codebase effort begins with a clean workspace inside <span class="code-pill">/Users/stevenjackson/code/qwythos-agent/projects/</span>. The Artifacts column shows clean dropdown files and deliverables specific to the active project, staying completely uncluttered.
    </p>
  </div>
</div>

<div class="callout-box ruby" style="margin-top: 14px;">
  <div class="callout-title ruby-glow">ARCHITECTURAL SUMMARY</div>
  <div style="font-size: 8.2pt; color: #cbd5e1;">
    Offcoder represents the ultimate fusion of local data privacy, zero API costs, and frontier reasoning intelligence. By chaining immutable version diffs, headless audit offload, execution feedback, and native macOS supervision, developers gain superpowers without giving away their source code.
  </div>
</div>

</body>
</html>
"""

def generate():
    HTML_REPORT.parent.mkdir(parents=True, exist_ok=True)
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    with open(HTML_REPORT, "w", encoding="utf-8") as f:
        f.write(HTML_CONTENT)
    print(f"[+] Wrote HTML template to: {HTML_REPORT}")

    chrome_path = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if not os.path.exists(chrome_path):
        print(f"[-] Error: Google Chrome not found at {chrome_path}", file=sys.stderr)
        sys.exit(1)

    cmd = [
        chrome_path,
        "--headless",
        "--disable-gpu",
        "--run-all-compositor-stages-before-draw",
        f"--print-to-pdf={OUTPUT_PDF}",
        "--no-pdf-header-footer",
        str(HTML_REPORT),
    ]

    print("[+] Rendering PDF via Chrome Headless...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if not OUTPUT_PDF.exists():
        print(f"[-] PDF generation failed:\n{res.stderr}", file=sys.stderr)
        sys.exit(1)

    size_kb = OUTPUT_PDF.stat().st_size / 1024
    print(f"[✓] Generated PDF: {OUTPUT_PDF} ({size_kb:.1f} KB)")

    # Render high-resolution PNGs of each page for GitHub README embedding
    print("[+] Rendering PNG previews for GitHub...")
    ppm_cmd = [
        "pdftoppm",
        "-png",
        "-r", "150",
        str(OUTPUT_PDF),
        str(ASSETS_DIR / "explainer_page")
    ]
    subprocess.run(ppm_cmd, check=True)
    print(f"[✓] Rendered page previews to: {ASSETS_DIR}")

if __name__ == "__main__":
    generate()
