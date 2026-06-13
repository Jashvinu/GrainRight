from pathlib import Path

import httpx
from PIL import Image

from ai_grain_grade.vision_rag_pipeline import VisionRAGPipeline


class _FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self._payload


def _write_test_image(path: Path) -> Path:
    image = Image.new("RGB", (32, 32), color=(120, 70, 45))
    image.save(path, format="JPEG")
    return path


def test_dashscope_provider_uses_openai_compatible_vision_payload(tmp_path, monkeypatch):
    captured = {}

    class FakeClient:
        def __init__(self, timeout):
            captured["timeout"] = timeout

        def __enter__(self):
            return self

        def __exit__(self, *_exc):
            return False

        def post(self, endpoint, headers=None, json=None):
            captured["endpoint"] = endpoint
            captured["headers"] = headers
            captured["payload"] = json
            return _FakeResponse(
                {
                    "choices": [
                        {
                            "message": {
                                "content": '{"quality_grade":"B","model_confidence":88}'
                            },
                            "finish_reason": "stop",
                        }
                    ]
                }
            )

    monkeypatch.setattr("ai_grain_grade.vision_rag_pipeline.httpx.Client", FakeClient)
    image_path = _write_test_image(tmp_path / "sample.jpg")
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/compatible-mode/v1",
        qwen_api_key="test-secret",
        qwen_timeout_seconds=12,
        feedback_storage_path=str(tmp_path / "feedback"),
        rag_retrieval_mode="lexical",
    )

    result = pipeline._call_qwen_vision(str(image_path), "Return JSON.", max_tokens=42)

    assert result == '{"quality_grade":"B","model_confidence":88}'
    assert captured["endpoint"] == "https://example.test/compatible-mode/v1/chat/completions"
    assert captured["headers"]["Authorization"] == "Bearer test-secret"
    assert captured["timeout"] == 12
    assert captured["payload"]["model"] == "qwen3-vl-plus"
    assert captured["payload"]["max_tokens"] == 42
    assert captured["payload"]["response_format"] == {"type": "json_object"}
    assert captured["payload"]["enable_thinking"] is False

    user_content = captured["payload"]["messages"][1]["content"]
    assert user_content[0]["type"] == "image_url"
    assert user_content[0]["image_url"]["url"].startswith("data:image/jpeg;base64,")
    assert user_content[1] == {"type": "text", "text": "Return JSON."}


def test_text_repair_uses_configured_cloud_provider(tmp_path, monkeypatch):
    captured = {}

    class FakeClient:
        def __init__(self, timeout):
            captured["timeout"] = timeout

        def __enter__(self):
            return self

        def __exit__(self, *_exc):
            return False

        def post(self, endpoint, headers=None, json=None):
            captured["endpoint"] = endpoint
            captured["headers"] = headers
            captured["payload"] = json
            return _FakeResponse(
                {
                    "choices": [
                        {
                            "message": {
                                "content": "",
                                "reasoning_content": '{"quality_grade":"C"}',
                            }
                        }
                    ]
                }
            )

    monkeypatch.setattr("ai_grain_grade.vision_rag_pipeline.httpx.Client", FakeClient)
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/v1",
        qwen_api_key="test-secret",
        feedback_storage_path=str(tmp_path / "feedback"),
        rag_retrieval_mode="lexical",
    )

    result = pipeline._call_text_model("Repair this.", max_tokens=20)

    assert result == '{"quality_grade":"C"}'
    assert captured["endpoint"] == "https://example.test/v1/chat/completions"
    assert captured["payload"]["messages"][1]["content"] == "Repair this."
    assert captured["payload"]["response_format"] == {"type": "json_object"}
    assert captured["payload"]["enable_thinking"] is False


def test_dashscope_provider_defaults_to_qwen3_vl_model(tmp_path):
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_base_url="https://example.test/v1",
        qwen_api_key="test-secret",
        feedback_storage_path=str(tmp_path / "feedback"),
        rag_retrieval_mode="lexical",
    )

    assert pipeline.qwen_model == "qwen3-vl-plus"
    assert pipeline.qwen_provider == "dashscope"


def test_dashscope_invalid_model_tries_fallback_model(tmp_path, monkeypatch):
    captured_models = []
    request = httpx.Request("POST", "https://example.test/v1/chat/completions")

    class FakeClient:
        def __init__(self, timeout):
            self.timeout = timeout

        def __enter__(self):
            return self

        def __exit__(self, *_exc):
            return False

        def post(self, endpoint, headers=None, json=None):
            captured_models.append(json["model"])
            if len(captured_models) == 1:
                response = httpx.Response(
                    400,
                    request=request,
                    text='{"message":"model qwen3-vl-plus not found"}',
                )
                raise httpx.HTTPStatusError("bad request", request=request, response=response)
            return _FakeResponse(
                {
                    "choices": [
                        {
                            "message": {
                                "content": '{"quality_grade":"A","model_confidence":81}'
                            },
                            "finish_reason": "stop",
                        }
                    ]
                }
            )

    monkeypatch.setattr("ai_grain_grade.vision_rag_pipeline.httpx.Client", FakeClient)
    image_path = _write_test_image(tmp_path / "fallback.jpg")
    pipeline = VisionRAGPipeline(
        qwen_provider="dashscope",
        qwen_model="qwen3-vl-plus",
        qwen_base_url="https://example.test/v1",
        qwen_api_key="test-secret",
        feedback_storage_path=str(tmp_path / "feedback"),
        rag_retrieval_mode="lexical",
    )

    response_text, route_meta = pipeline._call_qwen_vision(
        str(image_path),
        "Return JSON.",
        include_route_metadata=True,
    )

    assert response_text == '{"quality_grade":"A","model_confidence":81}'
    assert captured_models == ["qwen3-vl-plus", "qwen3-vl-flash"]
    assert route_meta["route_label"] == "model fallback"
    assert route_meta["model"] == "qwen3-vl-flash"
    assert route_meta["fallback_used"] is True
