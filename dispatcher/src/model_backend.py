import json
from typing import Any

import httpx

from .config import settings


def client() -> httpx.AsyncClient:
    headers = {"Authorization": f"Bearer {settings.llm_api_key}"} if settings.llm_api_key else {}
    return httpx.AsyncClient(base_url=settings.llm_base, timeout=600.0, headers=headers)


async def chat_completion(messages: list[dict[str, Any]], stream: bool = False) -> Any:
    payload = {"model": settings.model, "messages": messages, "stream": stream}
    async with client() as http:
        if not stream:
            response = await http.post("/chat/completions", json=payload)
            response.raise_for_status()
            return response.json()
        buffer: list[str] = []
        async with http.stream("POST", "/chat/completions", json=payload) as response:
            response.raise_for_status()
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    data = line[6:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data)
                        delta = chunk.get("choices", [{}])[0].get("delta", {})
                        text = delta.get("content") or ""
                        if text:
                            buffer.append(text)
                    except json.JSONDecodeError:
                        continue
        return {"text": "".join(buffer)}
