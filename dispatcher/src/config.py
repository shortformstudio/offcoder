import os
from pathlib import Path


class Settings:
    llm_base: str = os.environ.get("ORCH_LLM_BASE", "http://127.0.0.1:11434/v1")
    llm_api_key: str = os.environ.get("ORCH_LLM_API_KEY", "")
    model: str = os.environ.get("ORCH_MODEL", "qwen2.5-coder:7b")
    text_only: bool = os.environ.get("ORCH_TEXT_ONLY", "").lower() in {"1", "true", "yes"}
    port: int = int(os.environ.get("ORCH_PORT", "8000"))
    worker_id: str = os.environ.get("ORCH_WORKER_ID", "LOCAL_VERIFIER")
    orch_root: Path = Path(os.environ.get("ORCH_ROOT", Path.home() / ".local_orchestrator"))


settings = Settings()
