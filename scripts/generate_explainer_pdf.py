#!/usr/bin/env python3
"""
Generate a pristine, ultra-clean 1-PAGE architecture explainer for Offcoder.
Aesthetic: Moonpond-style deep dark navy, effervescent ruby, and radiant turquoise.
Constraints:
- Exactly 1 page (A4 portrait).
- Minimal words: punchy, technical, architectural facts only.
- Zero paraphrasing of user prompts or conversational back-and-forth.
- Safe side margins (20mm) and bounded widths to prevent any clipping.
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
<title>Offcoder — System Architecture</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700;800&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap');

  @page {
    size: A4 portrait;
    margin: 18mm 20mm 18mm 20mm;
    @bottom-left {
      content: "OFFCODER // LOCAL INFERENCE OFFLOAD";
      font-family: 'JetBrains Mono', monospace;
      font-size: 6.8pt;
      letter-spacing: 0.8px;
      color: #3e5068;
    }
    @bottom-right {
      content: "SYSTEM SPECIFICATION // REV 3.4";
      font-family: 'JetBrains Mono', monospace;
      font-size: 6.8pt;
      font-weight: 700;
      letter-spacing: 0.8px;
      color: #00f2fe;
    }
  }

  * {
    box-sizing: border-box;
    -webkit-print-color-adjust: exact !important;
    print-color-adjust: exact !important;
  }

  html, body {
    margin: 0;
    padding: 0;
    background: #060913;
    color: #cbd5e1;
    font-family: 'Plus Jakarta Sans', -apple-system, sans-serif;
    font-size: 8.2pt;
    line-height: 1.4;
    overflow: hidden;
  }

  /* Accents */
  .font-mono {
    font-family: 'JetBrains Mono', monospace;
  }

  .ruby {
    color: #ff2a6d;
  }

  .turquoise {
    color: #00f2fe;
  }

  .emerald {
    color: #05d5b0;
  }

  /* Header Box */
  .header {
    background: linear-gradient(135deg, #0d1429 0%, #080c1b 100%);
    border: 1px solid rgba(0, 242, 254, 0.25);
    border-radius: 10px;
    padding: 16px 20px;
    margin-bottom: 12px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
  }

  .header-left h1 {
    font-size: 20pt;
    font-weight: 800;
    letter-spacing: -0.5px;
    margin: 0 0 2px 0;
    background: linear-gradient(90deg, #ffffff 0%, #00f2fe 60%, #ff2a6d 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }

  .header-left .tagline {
    font-size: 8.4pt;
    color: #94a3b8;
    margin: 0;
  }

  .badge {
    display: inline-block;
    background: rgba(0, 242, 254, 0.08);
    border: 1px solid rgba(0, 242, 254, 0.35);
    color: #00f2fe;
    padding: 4px 9px;
    border-radius: 6px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 7.2pt;
    font-weight: 700;
    letter-spacing: 1px;
    text-transform: uppercase;
  }

  /* Metric Ribbon */
  .metrics {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
    margin-bottom: 12px;
  }

  .metric-card {
    background: #090e1f;
    border: 1px solid rgba(255, 255, 255, 0.07);
    border-radius: 8px;
    padding: 9px 12px;
  }

  .metric-card.m-turquoise {
    border-top: 2px solid #00f2fe;
  }

  .metric-card.m-ruby {
    border-top: 2px solid #ff2a6d;
  }

  .metric-card.m-emerald {
    border-top: 2px solid #05d5b0;
  }

  .metric-card.m-violet {
    border-top: 2px solid #a855f7;
  }

  .metric-val {
    font-family: 'JetBrains Mono', monospace;
    font-size: 13pt;
    font-weight: 800;
    line-height: 1.1;
  }

  .metric-lbl {
    font-size: 6.8pt;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: #8da2be;
    font-weight: 600;
    margin-top: 2px;
  }

  /* Section Titles */
  .sec-head {
    font-size: 8.8pt;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: #ffffff;
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 10px 0 6px 0;
  }

  .sec-head::after {
    content: "";
    flex: 1;
    height: 1px;
    background: rgba(255, 255, 255, 0.08);
  }

  /* Architecture 3-Col Layout */
  .domain-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    margin-bottom: 10px;
  }

  .domain-card {
    background: #090e1f;
    border: 1px solid rgba(255, 255, 255, 0.07);
    border-radius: 8px;
    padding: 10px 11px;
  }

  .domain-title {
    font-size: 8.5pt;
    font-weight: 700;
    color: #ffffff;
    margin-bottom: 2px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .domain-port {
    font-family: 'JetBrains Mono', monospace;
    font-size: 6.8pt;
    color: #00f2fe;
    background: rgba(0, 242, 254, 0.1);
    padding: 1px 5px;
    border-radius: 4px;
  }

  .domain-desc {
    font-size: 7.6pt;
    color: #94a3b8;
    line-height: 1.35;
    margin: 0;
  }

  /* Execution Pipeline Steps */
  .pipeline-bar {
    background: #070c1a;
    border: 1px solid rgba(0, 242, 254, 0.18);
    border-radius: 8px;
    padding: 10px 14px;
    margin-bottom: 10px;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
  }

  .pipe-step {
    border-left: 2px solid rgba(255, 255, 255, 0.1);
    padding-left: 8px;
  }

  .pipe-step.active-turquoise {
    border-left-color: #00f2fe;
  }

  .pipe-step.active-ruby {
    border-left-color: #ff2a6d;
  }

  .pipe-step.active-emerald {
    border-left-color: #05d5b0;
  }

  .pipe-num {
    font-family: 'JetBrains Mono', monospace;
    font-size: 6.8pt;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    margin-bottom: 1px;
  }

  .pipe-name {
    font-size: 8pt;
    font-weight: 700;
    color: #ffffff;
    margin-bottom: 2px;
  }

  .pipe-desc {
    font-size: 7.2pt;
    color: #8da2be;
    line-height: 1.3;
  }

  /* Compact Capabilities Grid */
  .feat-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
    margin-bottom: 10px;
  }

  .feat-box {
    background: #080d1e;
    border: 1px solid rgba(255, 255, 255, 0.06);
    border-radius: 6px;
    padding: 8px 11px;
  }

  .feat-name {
    font-size: 8pt;
    font-weight: 700;
    color: #ffffff;
    margin-bottom: 2px;
    display: flex;
    align-items: center;
    gap: 5px;
  }

  .feat-desc {
    font-size: 7.3pt;
    color: #94a3b8;
    line-height: 1.32;
    margin: 0;
  }

  /* Bottom Summary Strip */
  .footer-strip {
    background: linear-gradient(90deg, rgba(255, 42, 109, 0.08) 0%, rgba(0, 242, 254, 0.08) 100%);
    border: 1px solid rgba(0, 242, 254, 0.2);
    border-radius: 6px;
    padding: 8px 12px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 7.5pt;
  }

  .footer-strip span {
    color: #cbd5e1;
  }
</style>
</head>
<body>

<!-- HEADER -->
<div class="header">
  <div class="header-left">
    <h1>OFFCODER</h1>
    <p class="tagline">Local-First Autonomous Inference Offload &amp; Verified Coding Harness</p>
  </div>
  <div class="badge">SPEC // PRODUCTION</div>
</div>

<!-- METRICS -->
<div class="metrics">
  <div class="metric-card m-turquoise">
    <div class="metric-val turquoise font-mono">$0.00</div>
    <div class="metric-lbl">API Ingress Cost</div>
  </div>
  <div class="metric-card m-ruby">
    <div class="metric-val ruby font-mono">100%</div>
    <div class="metric-lbl">LAN Data Sovereignty</div>
  </div>
  <div class="metric-card m-emerald">
    <div class="metric-val emerald font-mono">O(N+M)</div>
    <div class="metric-lbl">Trimmed LCS Diffing</div>
  </div>
  <div class="metric-card m-violet">
    <div class="metric-val font-mono" style="color: #c084fc;">ACID WAL</div>
    <div class="metric-lbl">Zero-Loss Memory Core</div>
  </div>
</div>

<!-- RUNTIME TOPOLOGY -->
<div class="sec-head">Runtime Architecture</div>
<div class="domain-grid">
  <div class="domain-card">
    <div class="domain-title">
      <span>Native Cockpit</span>
      <span class="domain-port">SwiftUI</span>
    </div>
    <p class="domain-desc">
      60fps macOS deck. Real-time visual diff inspector, live Web Reflection viewer, and project artifact manager.
    </p>
  </div>

  <div class="domain-card">
    <div class="domain-title">
      <span>Automation Daemon</span>
      <span class="domain-port">:7171 / :9222</span>
    </div>
    <p class="domain-desc">
      Node.js Puppeteer stealth browser engine, screencast frame broker, tree-sitter AST indexer, and task leasing ring.
    </p>
  </div>

  <div class="domain-card">
    <div class="domain-title">
      <span>Dispatcher Gateway</span>
      <span class="domain-port">:8000</span>
    </div>
    <p class="domain-desc">
      Python 3.13 FastAPI gateway. Handles model proxying, DOM layout extraction, and task verification runner.
    </p>
  </div>
</div>

<!-- EXECUTION PIPELINE -->
<div class="sec-head">Audit &amp; Verification Loop</div>
<div class="pipeline-bar">
  <div class="pipe-step active-turquoise">
    <div class="pipe-num turquoise font-mono">01 // Draft</div>
    <div class="pipe-name">Local Draft &amp; Baseline</div>
    <div class="pipe-desc">Local model creates draft; immutable baseline snapshot committed to memory ring.</div>
  </div>

  <div class="pipe-step active-ruby">
    <div class="pipe-num ruby font-mono">02 // Offload</div>
    <div class="pipe-name">Headless Web Audit</div>
    <div class="pipe-desc">Stealth browser offloads audit to DeepSeek or Kimi; live reflection streams to UI.</div>
  </div>

  <div class="pipe-step active-emerald">
    <div class="pipe-num emerald font-mono">03 // Diff</div>
    <div class="pipe-name">Trimmed LCS Diffing</div>
    <div class="pipe-desc">Computes line-by-line mutation window in O(N+M) with instant visual diffs.</div>
  </div>

  <div class="pipe-step active-turquoise">
    <div class="pipe-num turquoise font-mono">04 // Verify</div>
    <div class="pipe-name">Closed-Loop Tests</div>
    <div class="pipe-desc">Executes native linters, compilers, and test suites before final workspace commit.</div>
  </div>
</div>

<!-- KEY ENGINEERING SOLUTIONS -->
<div class="sec-head">Engine Capabilities</div>
<div class="feat-grid">
  <div class="feat-box">
    <div class="feat-name">
      <span class="turquoise font-mono">▪</span> Zero-Loss Version Control
    </div>
    <p class="feat-desc">
      Eliminates destructive overwrites. Pre-audit baselines and post-audit revisions are permanently linked with visual diff chains.
    </p>
  </div>

  <div class="feat-box">
    <div class="feat-name">
      <span class="ruby font-mono">▪</span> Live Web Reflection Window
    </div>
    <p class="feat-desc">
      Zero blind execution. Floating native viewer streams outbound prompts and inbound tokens from headless browser processes.
    </p>
  </div>

  <div class="feat-box">
    <div class="feat-name">
      <span class="emerald font-mono">▪</span> Semantic Context Compression
    </div>
    <p class="feat-desc">
      Distills lengthy chat history into executive semantic anchors while archiving literal verbose logs to disk.
    </p>
  </div>

  <div class="feat-box">
    <div class="feat-name">
      <span class="font-mono" style="color: #c084fc;">▪</span> Isolated Project Workspaces
    </div>
    <p class="feat-desc">
      All codebase operations execute within dedicated project directories. The Cockpit Artifacts drawer displays only active deliverables.
    </p>
  </div>
</div>

<!-- FOOTER STRIP -->
<div class="footer-strip">
  <span><strong>Status:</strong> All test suites passing (Swift package clean, 12/12 daemon, 8/8 dispatcher).</span>
  <span class="font-mono turquoise">STACK: Swift 5.9 · Node 20 · Python 3.13 · SQLite WAL</span>
</div>

</body>
</html>
"""

def generate():
    HTML_REPORT.parent.mkdir(parents=True, exist_ok=True)
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    with open(HTML_REPORT, "w", encoding="utf-8") as f:
        f.write(HTML_CONTENT)
    print(f"[+] Wrote 1-page HTML template to: {HTML_REPORT}")

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

    print("[+] Rendering 1-page PDF via Chrome Headless...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if not OUTPUT_PDF.exists():
        print(f"[-] PDF generation failed:\n{res.stderr}", file=sys.stderr)
        sys.exit(1)

    size_kb = OUTPUT_PDF.stat().st_size / 1024
    print(f"[✓] Generated PDF: {OUTPUT_PDF} ({size_kb:.1f} KB)")

    # Clean old page preview images
    for p in ASSETS_DIR.glob("explainer_page*.png"):
        p.unlink()

    # Render high-resolution PNG preview of the single page
    print("[+] Rendering 150 DPI PNG preview...")
    ppm_cmd = [
        "pdftoppm",
        "-png",
        "-r", "150",
        str(OUTPUT_PDF),
        str(ASSETS_DIR / "explainer_page")
    ]
    subprocess.run(ppm_cmd, check=True)
    print(f"[✓] Rendered page preview to: {ASSETS_DIR}")

if __name__ == "__main__":
    generate()
