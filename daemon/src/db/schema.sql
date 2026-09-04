PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA foreign_keys = ON;

-- GITHUB WORKSPACE REGISTER
CREATE TABLE IF NOT EXISTS repo_registry (
    repo_id TEXT PRIMARY KEY,            -- e.g., 'shortformstudio/example-repo'
    local_path TEXT NOT NULL,            -- Cloned working directory
    default_branch TEXT DEFAULT 'main',
    indexed_tree JSON NOT NULL,          -- Hierarchical file tree representation
    last_synced INTEGER NOT NULL
);

-- LAYER 1: STRUCTURAL CONTEXT & AST REGISTER
CREATE TABLE IF NOT EXISTS context_nodes (
    file_path TEXT PRIMARY KEY,
    repo_id TEXT NOT NULL,
    ast_summary TEXT NOT NULL,           -- Signatures, classes, and exported interfaces only
    dependencies JSON NOT NULL,          -- Array of imported modules
    checksum TEXT NOT NULL,              -- SHA-256 hash
    last_indexed INTEGER NOT NULL,
    FOREIGN KEY(repo_id) REFERENCES repo_registry(repo_id) ON DELETE CASCADE
);

-- LAYER 2: EPISODIC RECOVERY & PROCEDURAL JOURNAL
CREATE TABLE IF NOT EXISTS session_journal (
    journal_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    entry_type TEXT CHECK(entry_type IN ('ARCH_DECISION', 'LINT_FAILURE', 'PATCH_SUCCESS', 'CONSULTATION_NOTE', 'PLAN_INIT')) NOT NULL,
    target_module TEXT NOT NULL,
    summary TEXT NOT NULL,               -- Max 30 words per record
    created_at INTEGER NOT NULL
);

-- TRANSACTION RING: TASK QUEUE WITH HEARTBEAT LEASING
CREATE TABLE IF NOT EXISTS task_queue (
    task_id TEXT PRIMARY KEY,
    parent_task_id TEXT,
    target_worker TEXT CHECK(target_worker IN ('GEMINI_WEB', 'DEEPSEEK_WEB', 'KIMI_WEB', 'LOCAL_VERIFIER')) NOT NULL,
    operation_mode TEXT CHECK(operation_mode IN ('GENERATION', 'REFACTOR_CONSULTATION', 'ADVERSARIAL_CRITIQUE', 'PLAN_DECOMPOSITION')) NOT NULL,
    target_file TEXT NOT NULL,
    prompt_payload TEXT NOT NULL,
    source_context TEXT,
    status TEXT CHECK(status IN ('PENDING', 'IN_FLIGHT', 'STAGED', 'VERIFIED', 'FAILED')) DEFAULT 'PENDING' NOT NULL,
    retry_count INTEGER DEFAULT 0,
    lease_owner TEXT DEFAULT NULL,
    lease_expires_at INTEGER DEFAULT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

-- STAGING RING: WORKER ARTIFACTS & SCREENSHOT VISION LOGS
CREATE TABLE IF NOT EXISTS staging_ring (
    artifact_id TEXT PRIMARY KEY,
    task_id TEXT UNIQUE NOT NULL,
    worker_origin TEXT NOT NULL,
    raw_code_payload TEXT NOT NULL,
    screenshot_path TEXT,                -- Full disk path to captured DOM render
    syntax_valid INTEGER DEFAULT 0,
    diagnostics_log TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(task_id) REFERENCES task_queue(task_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_task_lease ON task_queue(status, lease_expires_at);
