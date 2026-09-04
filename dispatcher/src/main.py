from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
import json
import time

from .config import settings
from .model_backend import client
from .vision import normalize_messages, vision_enabled

app = FastAPI(title="orchestrator local dispatcher", version="0.1.0")

_START_TIME = time.time()
_REQUESTS_TOTAL = 0
_ERRORS_TOTAL = 0


def jlog(level: str, code: str, msg: str, **extra: dict) -> None:
    payload = {"domain": "dispatcher", "level": level, "code": code, "msg": msg, **extra}
    line = json.dumps(payload)
    import sys

    print(line, file=sys.stderr if level in ("error", "critical") else sys.stdout, flush=True)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "model": settings.model,
        "vision_capable": vision_enabled(),
        "upstream": settings.llm_base,
        "worker": settings.worker_id,
    }


@app.get("/metrics")
async def metrics() -> PlainTextResponse:
    uptime = int(time.time() - _START_TIME)
    lines = [
        "# HELP dispatcher_requests_total Total number of chat completion requests received",
        "# TYPE dispatcher_requests_total counter",
        f"dispatcher_requests_total {_REQUESTS_TOTAL}",
        "# HELP dispatcher_errors_total Total number of failed requests",
        "# TYPE dispatcher_errors_total counter",
        f"dispatcher_errors_total {_ERRORS_TOTAL}",
        "# HELP dispatcher_vision_capable Whether the active model supports multimodal vision (1 or 0)",
        "# TYPE dispatcher_vision_capable gauge",
        f"dispatcher_vision_capable {1 if vision_enabled() else 0}",
        "# HELP dispatcher_uptime_seconds Seconds since the dispatcher started",
        "# TYPE dispatcher_uptime_seconds counter",
        f"dispatcher_uptime_seconds {uptime}",
    ]
    return PlainTextResponse("\n".join(lines) + "\n", media_type="text/plain; version=0.0.4")


@app.post("/v1/chat/completions")
async def chat(request: Request):
    global _REQUESTS_TOTAL, _ERRORS_TOTAL
    _REQUESTS_TOTAL += 1
    try:
        payload = await request.json()
    except Exception as error:
        _ERRORS_TOTAL += 1
        jlog("error", "malformed_body", str(error))
        return JSONResponse(content={"error": "invalid json body"}, status_code=400)
    if not isinstance(payload, dict) or not isinstance(payload.get("messages"), list):
        _ERRORS_TOTAL += 1
        jlog("error", "malformed_body", "messages must be a list")
        return JSONResponse(content={"error": "messages must be a list"}, status_code=400)
    payload["messages"] = normalize_messages(list(payload["messages"]))
    upstream_url = f"{settings.llm_base}/chat/completions"
    headers = {"Authorization": f"Bearer {settings.llm_api_key}"} if settings.llm_api_key else {}
    if payload.get("stream"):
        return _stream_chat(upstream_url, payload, headers)
    return await _plain_chat(upstream_url, payload, headers)


async def _plain_chat(url: str, payload: dict, headers: dict):
    import httpx

    try:
        async with client() as http:
            response = await http.post("/chat/completions", json=payload)
        return JSONResponse(content=response.json(), status_code=response.status_code)
    except httpx.HTTPError as error:
        jlog("error", "upstream_unreachable", str(error))
        return JSONResponse(content={"error": "upstream model unreachable", "detail": str(error)}, status_code=502)
    except json.JSONDecodeError as error:
        jlog("error", "upstream_malformed", str(error))
        return JSONResponse(content={"error": "upstream returned malformed json"}, status_code=502)


def _stream_chat(url: str, payload: dict, headers: dict) -> StreamingResponse:
    async def event_source():
        import httpx

        try:
            async with client() as http:
                async with http.stream("POST", url, json=payload, headers=headers) as response:
                    if response.status_code != 200:
                        jlog("error", "upstream_malformed", f"upstream status {response.status_code}")
                        yield f"data: {response.status_code}\n\n"
                        return
                    async for chunk in response.aiter_bytes():
                        yield chunk
        except httpx.HTTPError as error:
            jlog("error", "upstream_unreachable", str(error))
            yield 'data: {"error": "upstream model unreachable"}\n\n'

    return StreamingResponse(event_source(), media_type="text/event-stream")
