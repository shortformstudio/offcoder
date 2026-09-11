import os
from pathlib import Path


class Settings:
    llm_base: str = os.environ.get("ORCH_LLM_BASE", "http://lockfort.local:8080/v1")
    llm_api_key: str = os.environ.get("ORCH_LLM_API_KEY", "")
    model: str = os.environ.get(
        "ORCH_MODEL",
        "C:\\Users\\radio\\Documents\\DesktopArchive\\Radial Zone\\models\\HauhauCS\\Huihui-Qwythos-9B-Claude-Mythos-5-1M-abliterated-Q4_K.gguf",
    )
    text_only: bool = os.environ.get("ORCH_TEXT_ONLY", "").lower() in {"1", "true", "yes"}
    port: int = int(os.environ.get("ORCH_PORT", "8000"))
    worker_id: str = os.environ.get("ORCH_WORKER_ID", "LOCAL_VERIFIER")
    orch_root: Path = Path(os.environ.get("ORCH_ROOT", Path.home() / ".local_orchestrator"))


settings = Settings()
