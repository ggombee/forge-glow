"""Claude transcript/OTel 집계 파서.

실시간 HUD는 현재 세션만 보지만, 이 대시보드는 최근 로컬 로그를
집계하는 분석 뷰다. 파일이 없거나 깨져도 빈 결과로 동작한다.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


# Claude API 가격표 fallback ($/MTok). OTel cost_usd와 이 값은 모두
# 청구 확정값이 아닌 사용량 추정용이다.
PRICES_USD_PER_MTOK: dict[str, dict[str, float]] = {
    "fable": {"input": 10.0, "output": 50.0, "cache_read": 1.0, "cache_write": 12.5},
    "mythos": {"input": 10.0, "output": 50.0, "cache_read": 1.0, "cache_write": 12.5},
    "opus": {"input": 5.0, "output": 25.0, "cache_read": 0.5, "cache_write": 6.25},
    "opus-4.1": {"input": 15.0, "output": 75.0, "cache_read": 1.5, "cache_write": 18.75},
    "sonnet": {"input": 3.0, "output": 15.0, "cache_read": 0.3, "cache_write": 3.75},
    "sonnet-5": {"input": 2.0, "output": 10.0, "cache_read": 0.2, "cache_write": 2.5},
    "haiku": {"input": 1.0, "output": 5.0, "cache_read": 0.1, "cache_write": 1.25},
    "haiku-3.5": {"input": 0.8, "output": 4.0, "cache_read": 0.08, "cache_write": 1.0},
}


def short_model(name: str) -> str:
    """모델 ID에서 표시용 계열명을 추출한다."""
    lowered = (name or "").lower()
    normalized = lowered.replace("_", "-").replace(".", "-").replace(" ", "-")
    if (("opus-4-1-" in normalized or normalized.endswith("opus-4-1"))
            or "opus-4-20" in normalized
            or normalized.endswith("opus-4")):
        return "opus-4.1"
    if "haiku-3-5-" in normalized or normalized.endswith("haiku-3-5"):
        return "haiku-3.5"
    if "sonnet-5-" in normalized or normalized.endswith("sonnet-5"):
        return "sonnet-5"
    for key in ("fable", "mythos", "opus", "sonnet", "haiku"):
        if key in lowered:
            return key
    return "unknown"


@dataclass
class ModelUsage:
    model: str = "unknown"
    input_tokens: int = 0
    output_tokens: int = 0
    cache_read: int = 0
    cache_write: int = 0
    cost_usd: float = 0.0
    request_count: int = 0

    def estimate_cost(self) -> float:
        """OTel cost_usd가 없으면 가격표로 근사한다."""
        if self.cost_usd > 0:
            return self.cost_usd
        prices = PRICES_USD_PER_MTOK.get(self.model)
        if prices is None:
            return 0.0
        return (
            self.input_tokens * prices["input"]
            + self.output_tokens * prices["output"]
            + self.cache_read * prices["cache_read"]
            + self.cache_write * prices["cache_write"]
        ) / 1_000_000


@dataclass
class Snapshot:
    """대시보드 한 프레임의 로컬 집계."""
    models: dict[str, ModelUsage] = field(default_factory=dict)
    total_cost_usd: float = 0.0
    cache_hit_rate: float = 0.0
    tools_used: dict[str, int] = field(default_factory=dict)
    otel_available: bool = False
    update_available_reason: str | None = None

    def add_model(self, usage: ModelUsage) -> None:
        key = usage.model
        if key not in self.models:
            self.models[key] = usage
            return
        current = self.models[key]
        current.input_tokens += usage.input_tokens
        current.output_tokens += usage.output_tokens
        current.cache_read += usage.cache_read
        current.cache_write += usage.cache_write
        current.cost_usd += usage.cost_usd
        current.request_count += usage.request_count


def _iter_jsonl(path: Path, limit: int = 1000) -> Iterable[dict]:
    """JSONL의 마지막 limit줄을 안전하게 순회한다."""
    if not path.exists():
        return
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
    except OSError:
        return
    for line in lines[-limit:]:
        try:
            payload = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        if isinstance(payload, dict):
            yield payload


def _safe_int(value: object) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _safe_float(value: object) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _otel_value(value: object) -> object:
    if not isinstance(value, dict):
        return value
    for key in ("stringValue", "intValue", "doubleValue", "boolValue"):
        if key in value:
            raw = value[key]
            return _safe_int(raw) if key == "intValue" else raw
    return value


def _otel_attributes(items: object) -> dict[str, object]:
    if not isinstance(items, list):
        return {}
    result: dict[str, object] = {}
    for item in items:
        if isinstance(item, dict) and item.get("key"):
            result[str(item["key"])] = _otel_value(item.get("value"))
    return result


def _iter_otel_events(path: Path, limit: int = 2000) -> Iterable[dict]:
    """Flat JSON과 file exporter OTLP/JSON envelope를 하나의 event 형태로 바꿄다."""
    for payload in _iter_jsonl(path, limit=limit):
        if payload.get("name"):
            yield payload
            continue
        for resource_log in payload.get("resourceLogs", []) or []:
            resource = resource_log.get("resource", {}) or {}
            resource_attrs = _otel_attributes(resource.get("attributes"))
            scopes = (resource_log.get("scopeLogs")
                      or resource_log.get("instrumentationLibraryLogs") or [])
            for scope in scopes:
                records = scope.get("logRecords") or scope.get("logs") or []
                for record in records:
                    body = record.get("body", {}) or {}
                    attrs = dict(resource_attrs)
                    attrs.update(_otel_attributes(record.get("attributes")))
                    yield {
                        "name": body.get("stringValue") or record.get("name") or "",
                        "attributes": attrs,
                    }


def parse_otel(log_path: Path | None = None) -> tuple[dict[str, ModelUsage], bool]:
    """OTel api_request를 최근 로그 범위로 집계한다."""
    path = log_path or Path(os.environ.get(
        "FORGE_GLOW_OTEL_LOG", Path.home() / ".forge-glow" / "otel.log"
    ))
    usages: dict[str, ModelUsage] = {}
    if not path.exists():
        return usages, False
    available = False
    for event in _iter_otel_events(path):
        if event.get("name") != "claude_code.api_request":
            continue
        available = True
        attrs = event.get("attributes", {}) or {}
        key = short_model(str(attrs.get("model", "")))
        usage = usages.setdefault(key, ModelUsage(model=key))
        usage.input_tokens += _safe_int(attrs.get("input_tokens"))
        usage.output_tokens += _safe_int(attrs.get("output_tokens"))
        usage.cache_read += _safe_int(attrs.get("cache_read_tokens"))
        usage.cache_write += _safe_int(attrs.get("cache_creation_tokens"))
        usage.cost_usd += _safe_float(attrs.get("cost_usd"))
        usage.request_count += 1
    return usages, available


def parse_transcripts(
    projects_dir: Path | None = None,
) -> tuple[dict[str, ModelUsage], dict[str, int]]:
    """최근 Claude transcript 5개를 집계한다.

    assistant message는 여러 transcript 레코드로 반복될 수 있으므로
    message.id로 토큰 중복을 제거한다. 도구는 message.content[].tool_use를 읽는다.
    """
    root = projects_dir or Path(os.environ.get(
        "CLAUDE_PROJECTS_DIR", Path.home() / ".claude" / "projects"
    ))
    usages: dict[str, ModelUsage] = {}
    tools: dict[str, int] = {}
    if not root.exists():
        return usages, tools

    try:
        jsonls = sorted(root.rglob("*.jsonl"), key=lambda p: p.stat().st_mtime,
                        reverse=True)[:5]
    except OSError:
        return usages, tools

    for path in jsonls:
        seen_messages: set[str] = set()
        seen_tools: set[str] = set()
        for event in _iter_jsonl(path, limit=1000):
            message = event.get("message", {}) or {}
            content = message.get("content", []) or []
            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
                        continue
                    tool_id = str(block.get("id") or "")
                    if tool_id and tool_id in seen_tools:
                        continue
                    if tool_id:
                        seen_tools.add(tool_id)
                    name = str(block.get("name") or "unknown")
                    tools[name] = tools.get(name, 0) + 1

            if event.get("type") != "assistant" or not message.get("usage"):
                continue
            message_id = str(message.get("id") or event.get("uuid") or "")
            if message_id and message_id in seen_messages:
                continue
            if message_id:
                seen_messages.add(message_id)
            raw = message.get("usage", {}) or {}
            key = short_model(str(message.get("model", "")))
            usage = usages.setdefault(key, ModelUsage(model=key))
            usage.input_tokens += _safe_int(raw.get("input_tokens"))
            usage.output_tokens += _safe_int(raw.get("output_tokens"))
            usage.cache_read += _safe_int(raw.get("cache_read_input_tokens"))
            cache_creation = raw.get("cache_creation")
            if isinstance(cache_creation, dict):
                cache_write = (
                    _safe_int(cache_creation.get("ephemeral_5m_input_tokens"))
                    + _safe_int(cache_creation.get("ephemeral_1h_input_tokens"))
                )
            else:
                cache_write = 0
            usage.cache_write += cache_write or _safe_int(
                raw.get("cache_creation_input_tokens")
            )
            usage.request_count += 1
    return usages, tools


def parse_update_flag(state_dir: Path | None = None) -> str | None:
    path = (state_dir or Path(os.environ.get(
        "FORGE_GLOW_STATE_DIR", Path.home() / ".forge-glow"
    ))) / "update-available"
    if not path.exists():
        return None
    try:
        return path.read_text().strip() or "unknown"
    except OSError:
        return None


def build_snapshot() -> Snapshot:
    """OTel을 우선하고 transcript를 fallback으로 사용한다."""
    snapshot = Snapshot()
    otel_usages, snapshot.otel_available = parse_otel()
    if snapshot.otel_available and otel_usages:
        for usage in otel_usages.values():
            snapshot.add_model(usage)
    else:
        transcript_usages, tools = parse_transcripts()
        for usage in transcript_usages.values():
            snapshot.add_model(usage)
        snapshot.tools_used = tools

    if not snapshot.tools_used:
        _, snapshot.tools_used = parse_transcripts()
    snapshot.update_available_reason = parse_update_flag()

    total_input = total_cache_read = 0
    for usage in snapshot.models.values():
        snapshot.total_cost_usd += usage.estimate_cost()
        total_input += usage.input_tokens + usage.cache_read
        total_cache_read += usage.cache_read
    if total_input > 0:
        snapshot.cache_hit_rate = total_cache_read / total_input * 100
    return snapshot
