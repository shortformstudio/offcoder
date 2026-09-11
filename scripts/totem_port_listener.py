#!/usr/bin/env python3
"""
Totem Port Listener & Biodynamic Memory Proxy.
Transparently listens to and records all API input and output on the chosen port,
saving bulk content into 'local records - <port>/' and executing the 4-tier
Biodynamic Memory Distillation hierarchy outlined in the Totem whitepaper.
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# Add totem_memory module to sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(PROJECT_ROOT))

try:
    from totem_memory.engine import TotemMemoryEngine
    from totem_memory.models import Fact, WorkingKnowledge, RelationalProvenance
except ImportError:
    TotemMemoryEngine = None


class ModularMemoryFilter:
    """Pluggable modular filter for parsing and extracting candidate memories."""
    
    @staticmethod
    def filter_syntax_regex(user_prompt: str, response: str, reasoning: str):
        facts = []
        full_text = f"{response}\n{reasoning}"
        for line in full_text.splitlines():
            line_str = line.strip()
            lower = line_str.lower()
            if lower.startswith(("invariant:", "rule:", "principle:", "# architecture:")):
                facts.append({"content": line_str, "domain": "arch", "tags": ["syntax_rule"]})
        
        wk = {
            "title": user_prompt[:50] or "Code Modification",
            "semantic_summary": response[:250] or reasoning[:250],
            "domain": "arch",
            "origin_seed": user_prompt,
        }
        return facts, wk

    @staticmethod
    def filter_semantic_heuristic(user_prompt: str, response: str, reasoning: str):
        facts = []
        if user_prompt:
            facts.append({"content": f"User Goal: {user_prompt}", "domain": "heuristics", "tags": ["intent"]})
        wk = {
            "title": f"Heuristic: {user_prompt[:40]}",
            "semantic_summary": reasoning[:300] or response[:300],
            "domain": "heuristics",
            "origin_seed": user_prompt,
        }
        return facts, wk

    @staticmethod
    def filter_biodynamic_atlas(user_prompt: str, response: str, reasoning: str):
        full = f"{user_prompt} {response} {reasoning}".lower()
        if any(w in full for w in ["arch", "module", "pattern", "contract"]):
            domain = "arch"
        elif any(w in full for w in ["cli", "terminal", "build", "test", "docker"]):
            domain = "ops"
        elif any(w in full for w in ["style", "ui", "preference", "ux"]):
            domain = "heuristics"
        else:
            domain = "domain"
            
        facts = [{"content": response[:160] or user_prompt[:160], "domain": domain, "tags": ["atlas_routed"]}]
        wk = {
            "title": f"Atlas [{domain.upper()}]: {user_prompt[:40]}",
            "semantic_summary": reasoning[:200] or response[:200],
            "domain": domain,
            "origin_seed": user_prompt
        }
        return facts, wk

    @staticmethod
    def filter_raw_passthrough(user_prompt: str, response: str, reasoning: str):
        facts = [{"content": f"Prompt: {user_prompt}", "domain": "domain", "tags": ["raw_in"]}]
        wk = {
            "title": "Raw Turn",
            "semantic_summary": response[:250],
            "domain": "domain",
            "origin_seed": user_prompt
        }
        return facts, wk


def perform_biodynamic_distillation(records_dir: str, port_number: int, filter_mode: str, user_prompt: str = "", response: str = "", reasoning: str = ""):
    # Choose filter
    if filter_mode == "semantic":
        facts_data, wk_data = ModularMemoryFilter.filter_semantic_heuristic(user_prompt, response, reasoning)
    elif filter_mode == "atlas":
        facts_data, wk_data = ModularMemoryFilter.filter_biodynamic_atlas(user_prompt, response, reasoning)
    elif filter_mode == "raw":
        facts_data, wk_data = ModularMemoryFilter.filter_raw_passthrough(user_prompt, response, reasoning)
    else:
        facts_data, wk_data = ModularMemoryFilter.filter_syntax_regex(user_prompt, response, reasoning)

    bio_dir = Path(records_dir) / "biodynamic"
    bio_dir.mkdir(parents=True, exist_ok=True)

    bundle_path = bio_dir / "totem_bundle.json"
    if TotemMemoryEngine:
        if bundle_path.exists():
            engine = TotemMemoryEngine.from_json(str(bundle_path))
        else:
            engine = TotemMemoryEngine(totem_id=f"totem-{port_number}", totem_name=f"Totem Port {port_number}")

        # Record facts
        for fd in facts_data:
            engine.record_fact(content=fd["content"], domain=fd.get("domain", "arch"), tags=fd.get("tags", []))

        # Record working knowledge
        if wk_data and wk_data.get("title"):
            engine.record_working_knowledge(
                title=wk_data["title"],
                semantic_summary=wk_data["semantic_summary"],
                domain=wk_data.get("domain", "arch"),
                origin_seed=wk_data.get("origin_seed", ""),
                journey_trace=[f"port_{port_number}_{int(time.time())}"]
            )

        # Consolidate
        distill_result = engine.distill()
        engine.to_json(str(bundle_path))

        # Generate MEMORY.md
        memory_md_content = f"# Totem Biodynamic Memory Ledger (Port {port_number})\n\n" + engine.synthesize_prompt_context()
        (Path(records_dir) / "MEMORY.md").write_text(memory_md_content, encoding="utf-8")
        print(f"[Totem {port_number}] Biodynamic distillation pass complete -> {bundle_path}")


class TotemProxyHandler(BaseHTTPRequestHandler):
    target_host = "http://lockfort.local:8080"
    port_number = 8080
    records_dir = None
    filter_mode = "syntax"

    def do_POST(self):
        start_time = time.time()
        content_len = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_len) if content_len > 0 else b"{}"
        
        req_json = {}
        try:
            req_json = json.loads(post_data.decode("utf-8"))
        except Exception:
            pass

        target_url = f"{self.target_host}{self.path}"
        headers = {k: v for k, v in self.headers.items() if k.lower() not in ["host", "content-length"]}
        headers["Content-Type"] = "application/json"

        # Forward request to upstream model endpoint
        req = urllib.request.Request(target_url, data=post_data, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as res:
                res_data = res.read()
                self.send_response(res.status)
                for k, v in res.getheaders():
                    if k.lower() not in ["transfer-encoding", "content-length"]:
                        self.send_header(k, v)
                self.send_header("Content-Length", str(len(res_data)))
                self.end_headers()
                self.wfile.write(res_data)
                
                # Parse output and record transaction
                self.record_and_consolidate(req_json, res_data, start_time)
        except urllib.error.HTTPError as e:
            err_data = e.read()
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(err_data)
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))

    def do_GET(self):
        target_url = f"{self.target_host}{self.path}"
        try:
            with urllib.request.urlopen(target_url, timeout=10) as res:
                res_data = res.read()
                self.send_response(res.status)
                self.end_headers()
                self.wfile.write(res_data)
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))

    def record_and_consolidate(self, req_json, res_data, start_time):
        duration_ms = int((time.time() - start_time) * 1000)
        res_json = {}
        res_text = ""
        reasoning_text = ""
        try:
            res_json = json.loads(res_data.decode("utf-8"))
            choices = res_json.get("choices", [])
            if choices:
                msg = choices[0].get("message", {})
                res_text = msg.get("content", "")
                reasoning_text = msg.get("reasoning_content", "")
        except Exception:
            res_text = res_data.decode("utf-8", errors="ignore")

        raw_dir = Path(self.records_dir) / "raw"
        raw_dir.mkdir(parents=True, exist_ok=True)

        user_prompt = ""
        if "messages" in req_json and isinstance(req_json["messages"], list):
            for m in reversed(req_json["messages"]):
                if m.get("role") == "user":
                    user_prompt = m.get("content", "")
                    break

        entry = {
            "transaction_id": f"txn_{int(time.time() * 1000)}",
            "timestamp": time.time(),
            "port": self.port_number,
            "target_host": self.target_host,
            "path": self.path,
            "duration_ms": duration_ms,
            "request": req_json,
            "response": res_json or res_text
        }

        jsonl_path = raw_dir / "raw_transactions.jsonl"
        with open(jsonl_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")

        print(f"[Totem {self.port_number}] Recorded transaction ({duration_ms}ms) -> {jsonl_path}")
        perform_biodynamic_distillation(self.records_dir, self.port_number, self.filter_mode, user_prompt, res_text, reasoning_text)


def main():
    parser = argparse.ArgumentParser(description="Totem Port Listener & Biodynamic Consolidator")
    parser.add_argument("--listen-port", type=int, default=8081, help="Proxy listen port (default: 8081)")
    parser.add_argument("--target-port", type=int, default=8080, help="Target API port to monitor (default: 8080)")
    parser.add_argument("--target-host", type=str, default="http://lockfort.local:8080", help="Target endpoint host")
    parser.add_argument("--filter", type=str, default="syntax", choices=["syntax", "semantic", "atlas", "raw"], help="Modular memory filter")
    parser.add_argument("--consolidate", action="store_true", help="Run biodynamic consolidation on local records and exit")
    args = parser.parse_args()

    records_dir = PROJECT_ROOT / f"local records - {args.target_port}"
    records_dir.mkdir(parents=True, exist_ok=True)

    if args.consolidate:
        perform_biodynamic_distillation(str(records_dir), args.target_port, args.filter, user_prompt="Initial Baseline Calibration", response="Totem Biodynamic Baseline Activated.", reasoning="Initializing baseline consolidation.")
        print(f"Biodynamic consolidation complete for port {args.target_port} at {records_dir}")
        return

    TotemProxyHandler.target_host = args.target_host
    TotemProxyHandler.port_number = args.target_port
    TotemProxyHandler.records_dir = str(records_dir)
    TotemProxyHandler.filter_mode = args.filter

    server = HTTPServer(("0.0.0.0", args.listen_port), TotemProxyHandler)
    print(f"============================================================")
    print(f"  TOTEM PORT LISTENER ACTIVE ON PORT {args.listen_port}")
    print(f"  Monitoring API Port : {args.target_port} ({args.target_host})")
    print(f"  Modular Filter Mode : {args.filter.upper()}")
    print(f"  Records Directory   : {records_dir}")
    print(f"============================================================")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down Totem Port Listener...")
        server.server_close()


if __name__ == "__main__":
    main()
