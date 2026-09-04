// src/db/connection.ts
import Database from "better-sqlite3";
import { mkdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// src/config.ts
import path from "node:path";
import { homedir } from "node:os";
var ORCH_ROOT = process.env.ORCH_ROOT ?? path.join(homedir(), ".local_orchestrator");
var WORKSPACE_ROOT = process.env.ORCH_WORKSPACE_ROOT ?? path.join(ORCH_ROOT, "workspaces");
var SCREENSHOT_ROOT = path.join(ORCH_ROOT, "screenshots");
var ORG_NAME = process.env.ORCH_ORG ?? "shortformstudio";
var CDP_ENDPOINT = process.env.ORCH_CDP_URL ?? `http://127.0.0.1:${process.env.ORCH_CDP_PORT ?? 9222}`;
var DAEMON_WS_PORT = Number(process.env.ORCH_WS_PORT ?? 7171);
var CDP_PORT = Number(process.env.ORCH_CDP_PORT ?? 9222);
var LEASE_SECONDS = Number(process.env.ORCH_LEASE_SECONDS ?? 180);
var MAX_RETRIES = Number(process.env.ORCH_MAX_RETRIES ?? 3);
var WS_TOKEN = process.env.ORCH_WS_TOKEN ?? "";
var WS_MAX_FRAME_BYTES = 256 * 1024;
var IS_PRODUCTION = process.env.NODE_ENV === "production";
var WS_TLS_CERT = process.env.ORCH_WS_CERT ?? "";
var WS_TLS_KEY = process.env.ORCH_WS_KEY ?? "";

// src/db/connection.ts
var instance = null;
function getDb() {
  if (instance) return instance;
  mkdirSync(ORCH_ROOT, { recursive: true });
  mkdirSync(WORKSPACE_ROOT, { recursive: true });
  mkdirSync(SCREENSHOT_ROOT, { recursive: true });
  instance = new Database(`${ORCH_ROOT}/state.db`);
  instance.pragma("journal_mode = WAL");
  instance.pragma("busy_timeout = 5000");
  instance.pragma("foreign_keys = ON");
  const schemaPath = fileURLToPath(new URL("./schema.sql", import.meta.url));
  instance.exec(readFileSync(schemaPath, "utf8"));
  const queueCols = instance.pragma("table_info(task_queue)");
  if (!queueCols.some((c) => c.name === "scheduled_at")) {
    instance.exec("ALTER TABLE task_queue ADD COLUMN scheduled_at INTEGER");
  }
  return instance;
}

// src/util.ts
function unixNow() {
  return Math.floor(Date.now() / 1e3);
}
function unixMs() {
  return Date.now();
}

// src/db/journal.ts
function addJournal(db2, sessionId, entryType, targetModule, summary) {
  const capped = summary.trim().split(/\s+/).slice(0, 30).join(" ");
  const res = db2.prepare(
    `INSERT INTO session_journal (session_id, entry_type, target_module, summary, created_at)
       VALUES (?, ?, ?, ?, ?)`
  ).run(sessionId, entryType, targetModule, capped, unixNow());
  return Number(res.lastInsertRowid);
}
function listJournal(db2, sessionId, limit = 100) {
  return db2.prepare(
    `SELECT journal_id, entry_type AS entryType, target_module AS targetModule, summary, created_at
       FROM session_journal WHERE session_id = ?
       ORDER BY created_at DESC LIMIT ?`
  ).all(sessionId, limit);
}

// src/db/projects.ts
import { randomUUID as randomUUID2, createHash } from "node:crypto";
import path2 from "node:path";

// src/db/task_queue.ts
import { randomUUID } from "node:crypto";

// src/task_events.ts
import { EventEmitter } from "node:events";
var taskEvents = new EventEmitter();
taskEvents.setMaxListeners(16);

// src/db/task_queue.ts
function emit(db2, taskId, status) {
  const row = db2.prepare(`SELECT task_id, target_worker, operation_mode, target_file FROM task_queue WHERE task_id = ?`).get(taskId);
  if (!row) return;
  taskEvents.emit("task", {
    taskId,
    status,
    targetWorker: row.target_worker,
    operationMode: row.operation_mode,
    targetFile: row.target_file,
    at: unixNow()
  });
}
function enqueueTask(db2, input) {
  const taskId = randomUUID();
  if (input.key) {
    const existing = db2.prepare(
      `SELECT task_id FROM task_queue WHERE operation_mode = ? AND target_worker = ? AND prompt_payload LIKE ? LIMIT 1`
    ).get(input.operationMode, input.targetWorker, `%${input.key}%`);
    if (existing) return existing.task_id;
  }
  db2.prepare(
    `INSERT INTO task_queue (task_id, parent_task_id, target_worker, operation_mode, target_file, prompt_payload, source_context, status, retry_count, created_at, updated_at)
     VALUES (@task_id, @parent_task_id, @target_worker, @operation_mode, @target_file, @prompt_payload, @source_context, 'PENDING', @retry_count, @created_at, @updated_at)`
  ).run({
    task_id: taskId,
    parent_task_id: input.parentTaskId ?? null,
    target_worker: input.targetWorker,
    operation_mode: input.operationMode,
    target_file: input.targetFile,
    prompt_payload: input.promptPayload,
    source_context: input.sourceContext ?? null,
    retry_count: input.retryCount ?? 0,
    created_at: unixNow(),
    updated_at: unixNow()
  });
  emit(db2, taskId, "PENDING");
  return taskId;
}
function recoverExpiredLeases(db2) {
  const stale = db2.prepare(
    `SELECT task_id, target_worker, operation_mode, target_file FROM task_queue
       WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?`
  ).all(unixNow());
  const reaped = db2.prepare(
    `UPDATE task_queue
       SET status = 'PENDING', lease_owner = NULL, lease_expires_at = NULL, scheduled_at = unixepoch(), updated_at = ?
       WHERE status = 'IN_FLIGHT' AND lease_expires_at < ?`
  ).run(unixNow(), unixNow()).changes;
  for (const row of stale) {
    taskEvents.emit("task", {
      taskId: row.task_id,
      status: "PENDING_RECOVERED",
      targetWorker: row.target_worker,
      operationMode: row.operation_mode,
      targetFile: row.target_file,
      at: unixNow()
    });
  }
  return { reaped };
}
function checkoutTask(db2, workerId, targetWorker) {
  const tx = db2.transaction(() => {
    recoverExpiredLeases(db2);
    const row = db2.prepare(
      `UPDATE task_queue
         SET status = 'IN_FLIGHT', lease_owner = @worker_id, lease_expires_at = @expires, scheduled_at = NULL, updated_at = @now
         WHERE task_id = (
           SELECT task_id FROM task_queue
           WHERE status = 'PENDING' AND target_worker = @target_worker
             AND (scheduled_at IS NULL OR scheduled_at <= @now)
           ORDER BY retry_count ASC, created_at ASC LIMIT 1
         )
         RETURNING *`
    ).get({
      worker_id: workerId,
      expires: unixNow() + LEASE_SECONDS,
      now: unixNow(),
      target_worker: targetWorker
    });
    return row ?? null;
  });
  const task = tx();
  if (task) emit(db2, task.task_id, "IN_FLIGHT");
  return task;
}
function finalizeTask(db2, taskId, workerId, status) {
  const res = db2.prepare(
    `UPDATE task_queue SET status = @status, lease_owner = NULL, lease_expires_at = NULL, scheduled_at = NULL, updated_at = @now
       WHERE task_id = @task_id AND lease_owner = @worker_id AND status = 'IN_FLIGHT'`
  ).run({ status, now: unixNow(), task_id: taskId, worker_id: workerId });
  if (res.changes > 0) emit(db2, taskId, status);
  return res.changes > 0;
}
function addStagingArtifact(db2, artifact) {
  const artifactId = randomUUID();
  db2.prepare(
    `INSERT INTO staging_ring (artifact_id, task_id, worker_origin, raw_code_payload, screenshot_path, syntax_valid, diagnostics_log, created_at)
     VALUES (@artifact_id, @task_id, @worker_origin, @raw_code_payload, @screenshot_path, @syntax_valid, @diagnostics_log, @created_at)
     ON CONFLICT(task_id) DO UPDATE SET raw_code_payload = excluded.raw_code_payload, screenshot_path = excluded.screenshot_path, syntax_valid = excluded.syntax_valid, diagnostics_log = excluded.diagnostics_log`
  ).run({
    artifact_id: artifactId,
    task_id: artifact.taskId,
    worker_origin: artifact.workerOrigin,
    raw_code_payload: artifact.rawCodePayload,
    screenshot_path: artifact.screenshotPath,
    syntax_valid: artifact.syntaxValid ? 1 : 0,
    diagnostics_log: artifact.diagnosticsLog ?? null,
    created_at: unixNow()
  });
  return artifactId;
}
function queueCounts(db2) {
  const row = db2.prepare(
    `SELECT
         SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) AS pending,
         SUM(CASE WHEN status = 'IN_FLIGHT' THEN 1 ELSE 0 END) AS inflight
       FROM task_queue`
  ).get();
  return { pending: row.pending ?? 0, inflight: row.inflight ?? 0 };
}

// src/db/projects.ts
var PROJECT_NAME_REGEX = /^[a-zA-Z0-9._-]{1,64}$/;
var MAX_PLAN_CHARS = 4e3;
function projectKey(name, masterPlan) {
  const digest = createHash("sha256").update(masterPlan).digest("hex").slice(0, 12);
  return `FRESH:${name}:${digest}`;
}
function createFreshProject(db2, name, masterPlan) {
  if (!PROJECT_NAME_REGEX.test(name)) {
    throw new Error(`invalid project name "${name}": must match /^[a-zA-Z0-9._-]{1,64}$/`);
  }
  const resolved = path2.resolve(WORKSPACE_ROOT, name);
  if (!resolved.startsWith(WORKSPACE_ROOT + path2.sep)) {
    throw new Error(`path traversal detected: project path "${resolved}" escapes workspace root`);
  }
  const key = projectKey(name, masterPlan);
  const existing = db2.prepare(
    `SELECT task_id FROM task_queue
       WHERE operation_mode = 'PLAN_DECOMPOSITION' AND prompt_payload LIKE @key LIMIT 1`
  ).get({ key: `%${key}%` });
  if (existing) {
    return { sessionId: randomUUID2(), planTaskId: existing.task_id, reused: true };
  }
  const sessionId = randomUUID2();
  addJournal(db2, sessionId, "PLAN_INIT", name, `master plan received for ${name}`);
  const isChunked = masterPlan.length > MAX_PLAN_CHARS;
  const decompositionPlan = isChunked ? `${masterPlan.slice(0, MAX_PLAN_CHARS)}

[PLAN_CHUNKED: remaining ${masterPlan.length - MAX_PLAN_CHARS} chars preserved in diagnostics log]` : masterPlan;
  const planTaskId = enqueueTask(db2, {
    targetWorker: "LOCAL_VERIFIER",
    operationMode: "PLAN_DECOMPOSITION",
    targetFile: name,
    promptPayload: JSON.stringify({
      key,
      projectName: name,
      masterPlan: decompositionPlan,
      chunked: isChunked,
      totalLength: masterPlan.length,
      requested: "atomic modules with a dependency graph; one task per module, dependencies linked via parent_task_id"
    }),
    sourceContext: isChunked ? `PLAN_REF:sha256:${createHash("sha256").update(masterPlan).digest("hex")}` : null
  });
  if (isChunked) {
    addStagingArtifact(db2, {
      taskId: planTaskId,
      workerOrigin: "orchestrator_chunker",
      rawCodePayload: "// PLAN_FULL_POINTER",
      screenshotPath: null,
      syntaxValid: true,
      diagnosticsLog: masterPlan
    });
  }
  return { sessionId, planTaskId, reused: false };
}

// src/ipc.ts
import { WebSocketServer, WebSocket } from "ws";
import { createServer as createHttpServer } from "node:http";
import { createServer as createHttpsServer } from "node:https";
import { readFileSync as readFileSync2, existsSync } from "node:fs";

// src/errors.ts
import os from "node:os";
var seq = 0;
function structLog(entry) {
  const payload = {
    ...entry,
    domain: entry.domain ?? "daemon",
    level: entry.level,
    code: entry.code,
    msg: entry.msg,
    t: unixMs(),
    seq: seq++,
    pid: process.pid,
    host: os.hostname()
  };
  const line = JSON.stringify(payload) + "\n";
  if (entry.level === "error" || entry.level === "critical") {
    process.stderr.write(line);
  } else {
    process.stdout.write(line);
  }
}
function marqueeMapping(code) {
  switch (code) {
    case "cdp_connected":
      return { level: "idle", text: "cdp attached \u2014 screencast live" };
    case "cdp_offline":
      return { level: "alert", text: "chrome cdp offline \u2014 run scripts/chrome_launch.sh" };
    case "task_checked_out":
      return { level: "working", text: "task running on worker" };
    case "task_staged":
      return { level: "success", text: "artifact staged \u2014 validation queueing" };
    case "task_failed":
      return { level: "alert", text: "task failed \u2014 retry budget applied" };
    case "task_verified":
      return { level: "success", text: "artifact verified" };
    case "lease_expired":
      return { level: "alert", text: "lease expired \u2014 task reclaimed" };
    case "repo_indexed":
      return { level: "success", text: "repo tree indexed" };
    case "repo_missing":
      return { level: "alert", text: "repo not found in org" };
    case "bad_client_frame":
      return { level: "alert", text: "malformed client message rejected" };
    case "auth_rejected":
      return { level: "alert", text: "ws auth token missing" };
    case "recovered":
      return { level: "success", text: "state recovered \u2014 all systems nominal" };
    case "permission_denied":
      return { level: "alert", text: "filesystem permission error \u2014 check workspace path" };
    case "db_busy":
      return { level: "warning", text: "sqlite contended \u2014 retrying" };
    case "battery_low":
      return { level: "warning", text: "battery low \u2014 stream throttled" };
    default:
      return null;
  }
}

// src/ipc.ts
var IPCChannel = class {
  wss;
  server;
  clients = /* @__PURE__ */ new Set();
  authenticated = /* @__PURE__ */ new WeakSet();
  token;
  snapshot;
  maxClients;
  constructor(port, handler, options = {}) {
    this.token = options.token ?? WS_TOKEN;
    if (IS_PRODUCTION && (!this.token || this.token.trim().length === 0)) {
      throw new Error("SECURITY HALT: ORCH_WS_TOKEN is mandatory when running in production mode (NODE_ENV=production)");
    }
    this.snapshot = options.snapshot ?? (() => []);
    this.maxClients = options.maxClients ?? 16;
    const requestListener = (req, res) => {
      const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "127.0.0.1"}`);
      if (url.pathname === "/metrics" && req.method === "GET") {
        const metrics = options.metricsHandler ? options.metricsHandler() : "# No metrics registered\n";
        res.writeHead(200, { "Content-Type": "text/plain; version=0.0.4" });
        res.end(metrics);
        return;
      }
      if (url.pathname === "/health" && req.method === "GET") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ status: "ok", clients: this.clients.size }));
        return;
      }
      if (req.headers.upgrade?.toLowerCase() !== "websocket") {
        res.writeHead(404, { "Content-Type": "text/plain" });
        res.end("Not Found\n");
      }
    };
    if (WS_TLS_CERT && WS_TLS_KEY && existsSync(WS_TLS_CERT) && existsSync(WS_TLS_KEY)) {
      this.server = createHttpsServer({
        cert: readFileSync2(WS_TLS_CERT),
        key: readFileSync2(WS_TLS_KEY)
      }, requestListener);
    } else {
      this.server = createHttpServer(requestListener);
    }
    this.server.listen(port, "127.0.0.1");
    this.wss = new WebSocketServer({ server: this.server });
    this.wss.on("connection", (socket) => {
      if (this.clients.size >= this.maxClients) {
        socket.close(1013, "server saturated");
        return;
      }
      this.clients.add(socket);
      const reply = (message) => {
        if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
      };
      if (this.token.length === 0) {
        for (const message of this.snapshot()) {
          reply(message);
        }
      }
      const isAuthed = () => this.token.length === 0 || this.authenticated.has(socket);
      socket.on("message", (raw) => {
        const size = Array.isArray(raw) ? raw.reduce((n, b) => n + b.length, 0) : raw instanceof ArrayBuffer ? raw.byteLength : raw.length;
        if (size > WS_MAX_FRAME_BYTES) {
          structLog({ level: "warning", code: "frame_overflow", msg: `frame ${size} bytes rejected` });
          socket.close(1013, "frame overflow");
          return;
        }
        let command;
        try {
          command = JSON.parse(String(raw));
        } catch {
          structLog({ level: "warning", code: "bad_client_frame", msg: "invalid json command" });
          reply({ type: "error", code: "bad_client_frame", detail: "invalid json command" });
          return;
        }
        if (!isAuthed()) {
          if (command.type === "auth" && command.token === this.token) {
            this.authenticated.add(socket);
            for (const message of this.snapshot()) {
              reply(message);
            }
            return;
          }
          structLog({ level: "warning", code: "auth_rejected", msg: "ws client rejected \u2014 token required" });
          socket.close(1008, "auth required");
          return;
        }
        handler(command, reply);
      });
      socket.on("close", () => this.clients.delete(socket));
      socket.on("error", () => this.clients.delete(socket));
    });
  }
  broadcast(message) {
    const payload = JSON.stringify(message);
    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) client.send(payload);
    }
  }
  get clientCount() {
    return this.clients.size;
  }
  close() {
    for (const client of this.clients) {
      if (client.readyState === WebSocket.OPEN) client.close();
    }
    this.clients.clear();
    this.wss.close();
    this.server.close();
  }
};

// src/browser_broker.ts
import puppeteer from "puppeteer-core";
import { mkdirSync as mkdirSync2, rmSync } from "node:fs";
import path3 from "node:path";

// src/mutex.ts
var Mutex = class {
  tail = Promise.resolve();
  acquire(job) {
    const run = this.tail.then(job);
    this.tail = run.then(
      () => void 0,
      () => void 0
    );
    return run;
  }
  acquireSync(job) {
    return this.acquire(async () => job());
  }
};

// src/telemetry.ts
import { execFileSync } from "node:child_process";
var cached = null;
var lastChecked = 0;
var CACHE_MS = 3e4;
function batteryState() {
  const now = Date.now();
  if (cached && now - lastChecked < CACHE_MS) return cached;
  lastChecked = now;
  try {
    const out = execFileSync("pmset", ["-g", "batt"], { encoding: "utf8" });
    cached = out.includes("AC Power") ? "AC" : "BATTERY";
  } catch {
    cached = "AC";
  }
  return cached;
}
function batteryPercentage() {
  try {
    const out = execFileSync("pmset", ["-g", "batt"], { encoding: "utf8" });
    const match = out.match(/(\d+)%/);
    if (match) return parseInt(match[1], 10);
  } catch {
  }
  return 100;
}
function computeTelemetry(pending, inflight, cdp) {
  return {
    battery: batteryState(),
    batteryPercent: batteryPercentage(),
    platform: process.platform,
    uptimeNow: Math.floor(process.uptime()),
    pendingTasks: pending,
    inflightTasks: inflight,
    cdpConnected: cdp
  };
}

// src/browser_broker.ts
function withTimeout(promise, ms, onTimeout) {
  return Promise.race([
    promise,
    new Promise((resolve) => setTimeout(() => resolve(onTimeout()), ms))
  ]);
}
var CDPBroker = class {
  constructor(cdpPort = CDP_PORT) {
    this.cdpPort = cdpPort;
  }
  cdpPort;
  browser = null;
  cdpSession = null;
  screencastTimer = null;
  lastFrameAt = 0;
  workerChains = /* @__PURE__ */ new Map();
  chain(worker) {
    let chain = this.workerChains.get(worker);
    if (!chain) {
      chain = new Mutex();
      this.workerChains.set(worker, chain);
    }
    return chain;
  }
  async checkConnection() {
    try {
      const res = await fetch(`http://127.0.0.1:${this.cdpPort}/json/version`);
      return res.ok;
    } catch {
      return false;
    }
  }
  async connect() {
    this.browser = await puppeteer.connect({
      browserURL: `http://127.0.0.1:${this.cdpPort}`,
      defaultViewport: { width: 1440, height: 900 }
    });
    const version = await fetch(`http://127.0.0.1:${this.cdpPort}/json/version`).then((r) => r.json().catch(() => ({})));
    const userDataDir = version.userDataDir ?? "";
    if (userDataDir) {
      structLog({ level: "debug", code: "cdp_profile", msg: `attached chrome profile ${userDataDir}` });
    }
  }
  async resolvePage(worker) {
    if (!this.browser) throw new Error("browser not connected");
    const targetMatch = (url) => {
      if (worker === "GEMINI_WEB") return url.includes("gemini.google.com");
      if (worker === "KIMI_WEB") return url.includes("kimi.moonshot.cn") || url.includes("kimi.com");
      return url.includes("chat.deepseek.com");
    };
    let page = (await this.browser.pages()).find((p) => targetMatch(p.url())) ?? null;
    if (!page) {
      page = await this.browser.newPage();
      const homeUrl = worker === "GEMINI_WEB" ? "https://gemini.google.com/app" : worker === "KIMI_WEB" ? "https://www.kimi.com" : "https://chat.deepseek.com";
      await page.goto(homeUrl, {
        waitUntil: "domcontentloaded",
        timeout: 3e4
      });
    }
    await page.bringToFront();
    return page;
  }
  async executeTask(worker, prompt, taskId) {
    return this.chain(worker).acquire(async () => {
      let page;
      try {
        page = await this.resolvePage(worker);
      } catch (error) {
        structLog({ level: "error", code: "browser_unreachable", msg: String(error instanceof Error ? error.message : error), taskId });
        throw error;
      }
      this.cdpSession = await page.createCDPSession().catch(() => null);
      const inputSelector = worker === "GEMINI_WEB" ? 'div[role="textbox"], .ql-editor' : worker === "KIMI_WEB" ? 'div.chat-input-editor, div[contenteditable="true"], textarea' : "textarea, #chat-input";
      await page.waitForSelector(inputSelector, { timeout: 15e3 });
      await page.focus(inputSelector);
      const turnMarker = `

\xA7TURN ${taskId}`;
      const stampedPrompt = prompt.includes("\xA7TURN") ? prompt : `${prompt}${turnMarker}`;
      await page.evaluate(
        (sel, text) => {
          const el = document.querySelector(sel);
          if (!el) return;
          if (el.tagName === "TEXTAREA") {
            el.value = text;
          } else {
            el.innerText = text;
          }
          el.dispatchEvent(new Event("input", { bubbles: true }));
        },
        inputSelector,
        stampedPrompt
      );
      await page.keyboard.press("Enter");
      const stopIndicator = worker === "GEMINI_WEB" ? 'button[aria-label*="Stop"], .streaming-active' : worker === "KIMI_WEB" ? 'button[aria-label*="stop" i], button[aria-label*="\u505C\u6B62" i], .stop-icon, button[class*="stop" i]' : '.ds-stop-button, button[aria-label="Stop Generating"]';
      await page.waitForSelector(stopIndicator, { timeout: 1e4 }).catch(() => void 0);
      await withTimeout(
        page.waitForFunction(
          (sel) => !document.querySelector(sel),
          { timeout: 45e3, polling: 500 },
          stopIndicator
        ),
        45e3,
        () => void 0
      ).catch(() => void 0);
      const pageBody = await page.evaluate(() => document.body.innerText.slice(0, 500)).catch(() => "") ?? "";
      if (pageBody.match(/captcha|challenge|access denied|sign in|log in|cloudflare|cf-browser-verification/i)) {
        structLog({ level: "warning", code: "auth_gate", msg: "web session gated at login/captcha/challenge", taskId });
        throw new Error("auth_gate");
      }
      mkdirSync2(SCREENSHOT_ROOT, { recursive: true });
      const screenshotPath = path3.join(SCREENSHOT_ROOT, `${taskId}.png`);
      const layoutBlocks = await this.captureLayoutMap(page).catch(() => []);
      let clipped = false;
      try {
        await page.screenshot({ path: screenshotPath, fullPage: false, clip: this.codeClip(layoutBlocks, page) });
        clipped = true;
      } catch (error) {
        structLog({ level: "warning", code: "screenshot_clip_failed", msg: String(error instanceof Error ? error.message : error) });
        rmSync(screenshotPath, { force: true });
      }
      const code = await page.evaluate((workerType) => {
        const selectors = workerType === "GEMINI_WEB" ? ["pre code", ".code-block-decoration", ".message-content"] : workerType === "KIMI_WEB" ? ["pre code", "pre", "div.markdown", ".segment-content"] : ["pre", ".ds-message-body"];
        for (const sel of selectors) {
          const els = document.querySelectorAll(sel);
          if (els.length > 0) {
            const raw = els[els.length - 1].textContent ?? "";
            return raw.trim();
          }
        }
        return "";
      }, worker).catch(() => "");
      return { code, screenshotPath: clipped ? screenshotPath : null, layoutBlocks };
    });
  }
  codeClip(blocks, page) {
    const biggest = [...blocks].filter((b) => b.tag === "pre" || b.tag === "code").sort((a, b) => b.height - a.height)[0];
    if (biggest && biggest.width > 40 && biggest.height > 40) {
      return {
        x: Math.max(0, biggest.x),
        y: Math.max(0, biggest.y),
        width: Math.min(1440, biggest.width),
        height: Math.min(900, biggest.height)
      };
    }
    return { x: 0, y: 0, width: 1440, height: 900 };
  }
  async captureLayoutMap(page) {
    return page.evaluate(() => {
      const nodes = Array.from(document.querySelectorAll("pre, pre code, h1, h2, h3, .code-block, article"));
      return nodes.slice(0, 64).map((el) => {
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          sample: (el.textContent ?? "").slice(0, 200)
        };
      });
    });
  }
  async attachScreencast(worker, onFrame) {
    await this.detachScreencast();
    const page = await this.resolvePage(worker).catch(() => null);
    if (!page) return;
    this.cdpSession = await page.createCDPSession().catch(() => null);
    if (!this.cdpSession) return;
    await this.cdpSession.send("Page.enable").catch(() => void 0);
    const start = () => {
      let quality = 45;
      let everyNthFrame = 2;
      let maxWidth = 1280;
      try {
        if (batteryState() === "BATTERY" && batteryPercentage() < 30) {
          quality = 30;
          everyNthFrame = 4;
          maxWidth = 960;
        }
      } catch {
      }
      void this.cdpSession?.send("Page.startScreencast", {
        format: "jpeg",
        quality,
        everyNthFrame,
        maxWidth
      }).catch(() => void 0);
    };
    start();
    this.cdpSession.on("Page.screencastFrame", (event) => {
      this.lastFrameAt = Date.now();
      onFrame(event.data);
      void this.cdpSession?.send("Page.screencastFrameAck", { sessionId: event.sessionId }).catch(() => void 0);
    });
    this.screencastTimer = setInterval(async () => {
      if (Date.now() - this.lastFrameAt > 2e4) {
        await this.attachScreencast(worker, onFrame).catch(() => void 0);
      }
    }, 1e4);
  }
  async detachScreencast() {
    if (this.screencastTimer) {
      clearInterval(this.screencastTimer);
      this.screencastTimer = null;
    }
    if (this.cdpSession && this.browser?.connected) {
      await this.cdpSession.send("Page.stopScreencast").catch(() => void 0);
      await this.cdpSession.detach().catch(() => void 0);
    }
    this.cdpSession = null;
  }
  async dispose() {
    await this.detachScreencast();
    if (this.browser?.connected) {
      await this.browser.disconnect().catch(() => void 0);
    }
    this.browser = null;
  }
};

// src/github_sync.ts
import { execFileSync as execFileSync2 } from "node:child_process";
import { createHash as createHash2 } from "node:crypto";
import { existsSync as existsSync2, mkdirSync as mkdirSync3, readFileSync as readFileSync3, statSync } from "node:fs";
import path4 from "node:path";
import Parser from "tree-sitter";
var TOP_LEVELS = 4;
var MAX_FILE_BYTES = 4e5;
var SYNC_CHUNK = 200;
var LANG_BY_EXT = {
  ".ts": "typescript",
  ".tsx": "typescript",
  ".js": "typescript",
  ".mjs": "typescript",
  ".py": "python",
  ".rs": "rust",
  ".go": "go"
};
var GRAMMAR_MODULES = {
  typescript: "tree-sitter-typescript",
  python: "tree-sitter-python",
  rust: "tree-sitter-rust",
  go: "tree-sitter-go"
};
var SYMBOL_NODE_TYPES = {
  typescript: ["function_declaration", "method_definition", "class_declaration", "interface_declaration", "type_alias_declaration", "enum_declaration", "function_signature", "method_signature"],
  python: ["function_definition", "class_definition"],
  rust: ["function_item", "impl_item", "struct_item", "enum_item", "trait_item", "type_item", "mod_item"],
  go: ["function_declaration", "method_declaration", "type_declaration"]
};
var SYMBOL_REGEX = {
  typescript: /^\s*(?:export\s+)?(?:async\s+)?(?:function|class|interface|type|enum|const|let|var)\s+[\w$.]+/,
  python: /^\s*(?:async\s+)?def\s+\w+|^\s*class\s+\w+|^\s*@\w+/,
  rust: /^\s*(?:pub\s+)?(?:async\s+)?fn\s+\w+|^\s*(?:pub\s+)?(?:struct|enum|trait|type|impl|mod)\s+\w+|^\s*pub\s+use\s+/,
  go: /^\s*func\s+(?:\([^)]*\)\s+)?\w+|^\s*type\s+\w+\s+(?:struct|interface|map|slice)|^\s*var\s+\w+|^\s*const\s+\w+/
};
var DEP_REGEX = {
  typescript: /^\s*(?:import|from)\s+['"][^'"]+['"]|^\s*require\(\s*['"][^'"]+['"]\s*\)/,
  python: /^\s*(?:import|from)\s+[\w.]+(?:[\s,]+\w+)?/,
  rust: /^\s*use\s+[\w:]+/,
  go: /^\s*import\s+(?:[("]|[^")]*"?)/
};
function workspacePath(repoId) {
  return path4.join(WORKSPACE_ROOT, repoId.replace("/", "__"));
}
async function listOrgRepos(org) {
  try {
    const out = execFileSync2(
      "gh",
      ["repo", "list", org, "--json", "name,url,defaultBranchRef"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    );
    const rows = JSON.parse(out);
    return rows.map((r) => {
      let branch = "main";
      if (typeof r.defaultBranchRef === "object" && r.defaultBranchRef !== null && r.defaultBranchRef.name) {
        branch = r.defaultBranchRef.name;
      } else if (typeof r.defaultBranchRef === "string" && r.defaultBranchRef.trim()) {
        branch = r.defaultBranchRef.trim();
      }
      return {
        repo_id: `${org}/${r.name}`,
        url: r.url,
        default_branch: branch
      };
    });
  } catch {
    return restList(org);
  }
}
async function restList(org) {
  const token = process.env.GITHUB_TOKEN;
  const headers = { Accept: "application/vnd.github+json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`https://api.github.com/users/${org}/repos?per_page=100&sort=updated`, { headers });
  if (!res.ok) throw new Error(`github api failed: ${res.status}`);
  const rows = await res.json();
  return rows.map((r) => ({
    repo_id: `${org}/${r.name}`,
    url: r.clone_url,
    default_branch: r.default_branch ?? "main"
  }));
}
async function registerRepo(db2, descriptor) {
  const localPath = workspacePath(descriptor.repo_id);
  mkdirSync3(path4.dirname(localPath), { recursive: true });
  if (!existsSync2(localPath)) {
    execFileSync2("git", ["clone", "--depth", "1", "--branch", descriptor.default_branch, descriptor.url, localPath], {
      stdio: "pipe"
    });
  } else {
    execFileSync2("git", ["-C", localPath, "pull", "--ff-only"], { stdio: "pipe" });
  }
  return syncIndex(db2, descriptor.repo_id, localPath, descriptor.default_branch);
}
async function syncIndex(db2, repoId, localPath, defaultBranch = "main") {
  const files = execFileSync2("git", ["-C", localPath, "ls-files"], { encoding: "utf8" }).split("\n").filter(Boolean);
  const tree = buildTree(files);
  const now = unixNow();
  const upsert = db2.prepare(
    `INSERT INTO context_nodes (file_path, repo_id, ast_summary, dependencies, checksum, last_indexed)
     VALUES (@file_path, @repo_id, @ast_summary, @dependencies, @checksum, @last_indexed)
     ON CONFLICT(file_path) DO UPDATE SET
       ast_summary = excluded.ast_summary,
       dependencies = excluded.dependencies,
       checksum = excluded.checksum,
       last_indexed = excluded.last_indexed`
  );
  const entries = [];
  for (const file of files) {
    const absolute = path4.join(localPath, file);
    if (!existsSync2(absolute)) continue;
    const size = statSync(absolute).size;
    if (size === 0 || size > MAX_FILE_BYTES) continue;
    const content = readFileSync3(absolute, "utf8");
    if (content.includes("\0")) continue;
    entries.push({
      file,
      repoId,
      astSummary: await extractSignatures(content, LANG_BY_EXT[path4.extname(file).toLowerCase()] ?? "plain", file),
      dependencies: JSON.stringify(extractDependencies(content, LANG_BY_EXT[path4.extname(file).toLowerCase()] ?? "plain")),
      checksum: createHash2("sha256").update(content).digest("hex"),
      now
    });
  }
  for (let i = 0; i < entries.length; i += SYNC_CHUNK) {
    const chunk = entries.slice(i, i + SYNC_CHUNK);
    const tx = db2.transaction(() => {
      for (const entry of chunk) {
        upsert.run({
          file_path: entry.file,
          repo_id: entry.repoId,
          ast_summary: entry.astSummary,
          dependencies: entry.dependencies,
          checksum: entry.checksum,
          last_indexed: entry.now
        });
      }
    });
    tx();
  }
  db2.prepare(
    `INSERT INTO repo_registry (repo_id, local_path, default_branch, indexed_tree, last_synced)
     VALUES (@repo_id, @local_path, @default_branch, @indexed_tree, @last_synced)
     ON CONFLICT(repo_id) DO UPDATE SET
       indexed_tree = excluded.indexed_tree,
       last_synced = excluded.last_synced`
  ).run({
    repo_id: repoId,
    local_path: localPath,
    default_branch: defaultBranch,
    indexed_tree: JSON.stringify(tree),
    last_synced: now
  });
  return { files: entries.length, tree };
}
function buildTree(files) {
  const root = {};
  for (const file of files) {
    const parts = file.split("/");
    let level = root;
    for (let i = 0; i < parts.length - 1; i++) {
      if (i >= TOP_LEVELS - 1) break;
      level = level[parts[i]] ?? (level[parts[i]] = {});
      level.__kind = "dir";
    }
    level[parts[parts.length - 1]] = { __kind: "file" };
  }
  return root;
}
var grammarCache = /* @__PURE__ */ new Map();
async function loadLanguage(lang) {
  if (grammarCache.has(lang)) return grammarCache.get(lang) ?? null;
  const moduleSpec = GRAMMAR_MODULES[lang];
  if (!moduleSpec) {
    grammarCache.set(lang, null);
    return null;
  }
  try {
    const mod = await import(moduleSpec);
    const container = mod.default ?? mod;
    let language = null;
    if (typeof container.language === "function") language = container.language();
    const nested = container.typescript;
    if (!language && typeof nested?.language === "function") language = nested.language();
    grammarCache.set(lang, language);
    return language;
  } catch {
    grammarCache.set(lang, null);
    return null;
  }
}
async function extractSignatures(content, lang, file) {
  if (lang === "plain") {
    return summarizeRegex(content, SYMBOL_REGEX.typescript, file);
  }
  const language = await loadLanguage(lang);
  if (language) {
    const parser = new Parser();
    parser.setLanguage(language);
    const tree = parser.parse(content);
    const seen = /* @__PURE__ */ new Set();
    const lines = [];
    for (const type of SYMBOL_NODE_TYPES[lang] ?? []) {
      for (const node of tree.rootNode.descendantsOfType(type)) {
        const text = node.text.replace(/\s+/g, " ").trim().slice(0, 120);
        if (!text || text.length < 6 || seen.has(text)) continue;
        seen.add(text);
        lines.push(text);
        if (lines.length >= 80) break;
      }
      if (lines.length >= 80) break;
    }
    if (lines.length > 0) return lines.join("\n").slice(0, 8e3);
  }
  return summarizeRegex(content, SYMBOL_REGEX[lang] ?? SYMBOL_REGEX.typescript, file);
}
function summarizeRegex(content, regex, file) {
  const lines = [];
  for (const line of content.split("\n")) {
    if (regex.test(line)) {
      const clean = line.trim().slice(0, 120);
      if (clean) lines.push(clean);
      if (lines.length >= 80) break;
    }
  }
  if (lines.length === 0) {
    return `${file}: no top-level symbols found (${content.length} bytes)`;
  }
  return lines.join("\n").slice(0, 8e3);
}
function extractDependencies(content, lang) {
  const regex = DEP_REGEX[lang] ?? DEP_REGEX.typescript;
  const deps = /* @__PURE__ */ new Set();
  for (const line of content.split("\n")) {
    if (!regex.test(line)) continue;
    const target = line.replace(/^\s*import\s+|^\s*from\s+|^\s*use\s+|^\s*require\s*\(|["';,)]+$/g, "").trim().replace(/\s+/g, " ");
    if (target.length > 0 && target.length < 120) deps.add(target);
    if (deps.size >= 20) break;
  }
  return [...deps];
}

// src/marquee.ts
var TTL_MS = {
  idle: 1e4,
  success: 8e3,
  working: 15e3,
  warning: 12e3,
  alert: 0
};
var MAX_HISTORY = 8;
var MarqueeDirector = class {
  current = null;
  history = [];
  post(level, text, code) {
    this.current = { level, text, code, ts: unixMs() };
    this.history.push(this.current);
    if (this.history.length > MAX_HISTORY) this.history.shift();
    return this.current;
  }
  snapshot() {
    const active = this.current ? [this.expire(this.current)].filter(Boolean) : [];
    return [...active, ...this.history.slice(-3)].map((m) => this.expire(m)).filter(Boolean);
  }
  currentState() {
    return this.current ? this.expire(this.current) : null;
  }
  expire(state) {
    if (TTL_MS[state.level] === 0) return state;
    if (unixMs() - state.ts > TTL_MS[state.level]) return null;
    return state;
  }
};

// src/index.ts
import { readdirSync, rmSync as rmSync2, statSync as statSync2 } from "node:fs";
import path5 from "node:path";
import { exit } from "node:process";
var db = getDb();
var marquee = new MarqueeDirector();
var channel = null;
var cdpConnected = false;
var lastTelemetry = null;
function marqueeify(code) {
  const mapping = marqueeMapping(code);
  if (!mapping) return;
  const state = marquee.post(mapping.level, mapping.text, code);
  channel?.broadcast({ type: "marquee", level: state.level, text: state.text, code: state.code, ts: state.ts });
}
async function main() {
  channel = new IPCChannel(
    DAEMON_WS_PORT,
    async (command, reply) => {
      switch (command.type) {
        case "org_repos": {
          reply({ type: "org_repos", repos: await listOrgRepos(ORG_NAME) });
          break;
        }
        case "pull_repo": {
          if (!command.repoId) return;
          try {
            const descriptor = (await listOrgRepos(ORG_NAME)).find((r) => r.repo_id === command.repoId);
            if (!descriptor) {
              marqueeify("repo_missing");
              reply({ type: "error", code: "repo_missing", detail: `repo not found: ${command.repoId}` });
              return;
            }
            const result = await registerRepo(db, descriptor);
            ch.broadcast({ type: "repo_registered", repoId: descriptor.repo_id, files: result.files });
            marqueeify("repo_indexed");
            reply({ type: "repo_registered", repoId: descriptor.repo_id, files: result.files });
          } catch (error) {
            structLog({ level: "error", code: "repo_pull_failed", msg: String(error instanceof Error ? error.message : error) });
            reply({ type: "error", code: "repo_pull_failed", detail: String(error instanceof Error ? error.message : error) });
          }
          break;
        }
        case "fresh_project": {
          if (!command.name || !command.masterPlan) {
            reply({ type: "error", code: "bad_command", detail: "name and masterPlan are required" });
            return;
          }
          const { sessionId, planTaskId, reused } = createFreshProject(db, command.name, command.masterPlan);
          ch.broadcast({
            type: "journal",
            sessionId,
            entryType: "PLAN_INIT",
            target: command.name,
            summary: reused ? "decomposition already queued (idempotent)" : "bootstrap decomposition queued"
          });
          reply({ type: "plan_queued", sessionId, taskId: planTaskId, reused });
          break;
        }
        case "journal_query": {
          reply({ type: "journal_entries", entries: listJournal(db, command.sessionId ?? "*") });
          break;
        }
        case "screencast_subscribe": {
          reply({ type: "screencast_subscribed" });
          break;
        }
        case "self_fulfill": {
          if (process.env.ORCH_SELFTEST !== "1") break;
          const task = checkoutTask(db, "self-fulfiller", "LOCAL_VERIFIER");
          if (task) {
            addStagingArtifact(db, {
              taskId: task.task_id,
              workerOrigin: "self-fulfiller",
              rawCodePayload: "// selftest artifact",
              screenshotPath: null,
              syntaxValid: true
            });
            finalizeTask(db, task.task_id, "self-fulfiller", "STAGED");
            reply({ type: "self_fulfilled", taskId: task.task_id });
          } else {
            reply({ type: "self_fulfilled", taskId: null });
          }
          break;
        }
        default:
          reply({ type: "error", code: "bad_command", detail: `unknown command: ${command.type}` });
      }
    },
    {
      token: WS_TOKEN,
      snapshot: () => [
        { type: "marquee_state", states: marquee.snapshot() },
        {
          type: "status",
          key: "cdp",
          state: cdpConnected ? "CONNECTED" : "IDLE",
          detail: cdpConnected ? `127.0.0.1:${CDP_PORT}` : "run scripts/chrome_launch.sh"
        },
        ...lastTelemetry ? [{ type: "telemetry", ...lastTelemetry }] : []
      ],
      metricsHandler: () => {
        const detailedCounts = db.prepare(`
          SELECT status, count(*) as c FROM task_queue GROUP BY status
        `).all();
        const statusMap = {
          PENDING: 0,
          IN_FLIGHT: 0,
          STAGED: 0,
          VERIFIED: 0,
          FAILED: 0
        };
        for (const row of detailedCounts) {
          statusMap[row.status] = row.c;
        }
        const lines = [
          "# HELP orchestrator_daemon_connected_clients Current number of connected WebSocket clients",
          "# TYPE orchestrator_daemon_connected_clients gauge",
          `orchestrator_daemon_connected_clients ${channel?.clientCount ?? 0}`,
          "# HELP orchestrator_daemon_queue_tasks Number of tasks in queue partitioned by status",
          "# TYPE orchestrator_daemon_queue_tasks gauge",
          `orchestrator_daemon_queue_tasks{status="pending"} ${statusMap.PENDING}`,
          `orchestrator_daemon_queue_tasks{status="inflight"} ${statusMap.IN_FLIGHT}`,
          `orchestrator_daemon_queue_tasks{status="staged"} ${statusMap.STAGED}`,
          `orchestrator_daemon_queue_tasks{status="verified"} ${statusMap.VERIFIED}`,
          `orchestrator_daemon_queue_tasks{status="failed"} ${statusMap.FAILED}`,
          "# HELP orchestrator_daemon_cdp_connected Whether Chrome CDP is connected (1) or offline (0)",
          "# TYPE orchestrator_daemon_cdp_connected gauge",
          `orchestrator_daemon_cdp_connected ${cdpConnected ? 1 : 0}`,
          "# HELP orchestrator_daemon_battery_percent System battery percentage if available",
          "# TYPE orchestrator_daemon_battery_percent gauge",
          `orchestrator_daemon_battery_percent ${lastTelemetry?.batteryPercent ?? -1}`,
          "# HELP orchestrator_daemon_uptime_seconds Seconds since daemon process started",
          "# TYPE orchestrator_daemon_uptime_seconds counter",
          `orchestrator_daemon_uptime_seconds ${Math.floor(process.uptime())}`
        ];
        return lines.join("\n") + "\n";
      }
    }
  );
  const ch = channel;
  const broker = new CDPBroker(CDP_PORT);
  cdpConnected = await broker.checkConnection();
  if (cdpConnected) {
    await broker.connect();
    structLog({ level: "info", code: "cdp_connected", msg: `screencast attached to ${CDP_PORT}` });
    marqueeify("cdp_connected");
    broker.attachScreencast("GEMINI_WEB", (frame) => {
      if (frame.length > 512 * 1024) return;
      channel?.broadcast({ type: "screencast_frame", data: frame });
    }).catch(() => marqueeify("cdp_offline"));
  } else {
    structLog({ level: "warning", code: "cdp_offline", msg: "chrome not attached on 9222" });
    marqueeify("cdp_offline");
  }
  taskEvents.on("task", (event) => {
    channel?.broadcast({ type: "task_event", ...event });
    if (event.status === "IN_FLIGHT") marqueeify("task_checked_out");
    if (event.status === "STAGED") marqueeify("task_staged");
    if (event.status === "VERIFIED") marqueeify("task_verified");
    if (event.status === "FAILED") marqueeify("task_failed");
    if (event.status === "PENDING_RECOVERED") marqueeify("lease_expired");
  });
  let sweepInProgress = false;
  const sweep = () => {
    if (sweepInProgress) return;
    sweepInProgress = true;
    try {
      const { reaped } = recoverExpiredLeases(db);
      if (reaped > 0) {
        structLog({ level: "warning", code: "lease_expired", msg: `${reaped} task(s) reclaimed` });
        channel?.broadcast({ type: "marquee", level: "alert", text: "lease expired \u2014 task reclaimed", code: "lease_expired", ts: Date.now() });
      }
    } catch (error) {
      structLog({ level: "error", code: "sweep_failed", msg: String(error instanceof Error ? error.message : error) });
    } finally {
      sweepInProgress = false;
    }
  };
  const telemetryTimer = setInterval(() => {
    const counts = queueCounts(db);
    const t = computeTelemetry(counts.pending, counts.inflight, cdpConnected);
    lastTelemetry = t;
    channel?.broadcast({ type: "telemetry", ...t });
  }, 5e3);
  sweep();
  const sweepTimer = setInterval(sweep, 3e4);
  const prune = () => {
    try {
      const files = readdirSync(SCREENSHOT_ROOT).filter((f) => f.endsWith(".png")).map((f) => ({ f, t: statSync2(path5.join(SCREENSHOT_ROOT, f)).mtimeMs })).sort((a, b) => b.t - a.t);
      for (const entry of files.slice(200)) rmSync2(path5.join(SCREENSHOT_ROOT, entry.f), { force: true });
    } catch (error) {
      structLog({ level: "debug", code: "prune", msg: String(error instanceof Error ? error.message : error) });
    }
  };
  prune();
  const pruneTimer = setInterval(prune, 60 * 60 * 1e3);
  structLog({
    level: "info",
    code: "daemon_ready",
    msg: `ws ${DAEMON_WS_PORT} cdp ${CDP_PORT} org ${ORG_NAME} lease ${LEASE_SECONDS}s retries ${MAX_RETRIES}`
  });
  const shutdown = () => {
    for (const timer of [telemetryTimer, sweepTimer, pruneTimer]) clearInterval(timer);
    void broker.dispose();
    channel?.close();
    structLog({ level: "info", code: "daemon_stopped", msg: "shutdown complete" });
  };
  process.on("SIGINT", () => shutdown());
  process.on("SIGTERM", () => shutdown());
}
process.on("uncaughtException", (error) => {
  structLog({ level: "critical", code: "uncaught", msg: error.stack ?? String(error) });
  exit(1);
});
process.on("unhandledRejection", (error) => {
  structLog({ level: "critical", code: "unhandled_rejection", msg: String(error) });
});
main().catch((error) => {
  structLog({ level: "critical", code: "fatal", msg: String(error instanceof Error ? error.stack : error) });
  exit(1);
});
//# sourceMappingURL=index.mjs.map
