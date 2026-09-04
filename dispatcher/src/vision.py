from __future__ import annotations

from typing import Any

from .config import settings

VISION_MARKERS = (
    "llava",
    "bakllava",
    "qwen2-vl",
    "qwen2.5-vl",
    "gemma3",
    "moondream",
    "minicpm-v",
    "internvl",
    "llama3.2-vision",
    "phi3.5-vision",
    "gemini",
)


def model_supports_vision(model: str) -> bool:
    lowered = model.lower()
    return any(marker in lowered for marker in VISION_MARKERS)


def vision_enabled() -> bool:
    return not settings.text_only and model_supports_vision(settings.model)


def normalize_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if vision_enabled():
        return messages
    out: list[dict[str, Any]] = []
    for message in messages:
        content = message.get("content")
        if isinstance(content, list):
            parts: list[str] = []
            layout_hint: str | None = None
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "text":
                    parts.append(str(part.get("text", "")))
                elif part.get("type") == "image_url":
                    hint = part.get("image_layout_map")
                    if hint:
                        layout_hint = str(hint)
            merged = "\n\n".join(parts) or str(content)
            if layout_hint:
                merged = f"{merged}\n\n{layout_hint}"
            out.append({**message, "content": merged})
        else:
            out.append(message)
    return out
