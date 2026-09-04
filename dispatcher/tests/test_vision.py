from __future__ import annotations

import pytest
from src.vision import model_supports_vision, normalize_messages
from src.config import settings


def test_model_supports_vision_detection():
    # Vision capable models
    assert model_supports_vision("llama3.2-vision:11b") is True
    assert model_supports_vision("qwen2.5-vl:7b") is True
    assert model_supports_vision("gemini-2.0-flash") is True
    assert model_supports_vision("llava:latest") is True

    # Pure text models
    assert model_supports_vision("deepseek-coder:6.7b") is False
    assert model_supports_vision("qwen2.5-coder:7b") is False
    assert model_supports_vision("mistral:7b") is False


def test_normalize_messages_strips_images_when_text_only(monkeypatch):
    monkeypatch.setattr(settings, "text_only", True)

    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "Inspect the dashboard interface."},
                {
                    "type": "image_url",
                    "image_url": {"url": "data:image/png;base64,iVBORw0KGgo="},
                    "image_layout_map": "dom layout map: #1 BUTTON@(10,20) 100x40",
                },
            ],
        }
    ]

    normalized = normalize_messages(messages)
    assert len(normalized) == 1
    content = normalized[0]["content"]
    assert isinstance(content, str)
    assert "Inspect the dashboard interface." in content
    assert "dom layout map: #1 BUTTON@(10,20) 100x40" in content
    assert "data:image/png" not in content


def test_normalize_messages_leaves_pure_text_untouched():
    messages = [{"role": "user", "content": "Simple prompt with no multimodal parts."}]
    normalized = normalize_messages(messages)
    assert normalized == messages
