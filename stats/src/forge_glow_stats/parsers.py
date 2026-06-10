"""forge-glow-stats — JSONL/OTel/usage 파서 (쉘 버전의 Python 포팅).

L2 transcript + L3 code-forge + L5 OTel 데이터를 Python으로 수집한다.
파일 IO는 실패에 관대하다 — 소스 부재 시 빈 dict/list 반환.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterable

# 2026-04 기준 가격표 ($/MTok). 실제 정확값은 L5(OTel)가 cost_usd를 직접 제공하므로
# L2 fallback 용도.
PRICES_USD_PER_MTOK: dict[str, dict[str, float]] = {
    "opus":   {"input": 5.0,  "output": 25.0, "cache_read": 0.5,  "cache_write": 6.25},
    "sonnet": {"input": 3.0,  "output": 15.0, "cache_read": 0.3,  "cache_write": 3.75},
    "haiku":  {"input": 1.0,  "output": 5.0,  "cache_read": 0.1,  "cache_write": 1.25},
    # Codex 대표 모델 (정확 가격은 OpenAI pricing 참조)
    "gpt-5":  {"input": 5.0,  "output": 25.0, "cache_read": 2.5,  "cache_write": 5.0},
    "gpt-4.1":{"input": 3.0,  "output": 15.0, "cache_read": 1.5,  "cache_write": 3.0},
    "o3":     {"input": 10.0, "output": 40.0, "cache_read": 5.0,  "cache_write": 10.0},
    "mini":   {"input": 1.0,  "output": 4.0,  "cache_read": 0.5,  "cache_write": 1.0},
}


def short_model(name: str) -> str:
    """모델 id/display에서 대표 키워드 추출."""
    n = (name or "").lower()
    for key in ("opus", "sonnet", "haiku", "gpt-5", "gpt-4.1", "o3", "mini"):
        if key in n:
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
        """L5가 없을 때 가격표로 근사 계산."""
        if self.cost_usd > 0:
            return self.cost_usd
        p = PRICES_USD_PER_MTOK.get(self.model, PRICES_USD_PER_MTOK["sonnet"])
        return (
            self.input_tokens * p["input"]
            + self.output_tokens * p["output"]
            + self.cache_read * p["cache_read"]
            + self.cache_write * p["cache_write"]
        ) / 1_000_000


@dataclass
class Snapshot:
    """대시보드 한 프레임의 전체 데이터."""
    models: dict[str, ModelUsage] = field(default_factory=dict)
    total_cost_usd: float = 0.0
    cache_hit_rate: float = 0.0
    tools_used: dict[str, int] = field(default_factory=dict)
    forge_agents: dict[str, int] = field(default_factory=dict)
    forge_skills: dict[str, int] = field(default_factory=dict)
    otel_available: bool = False
    update_available_reason: str | None = None
    codex_active: bool = False
    codex_model: str | None = None
    codex_cost: float = 0.0

    def add_model(self, usage: ModelUsage) -> None:
        key = usage.model
        if key in self.models:
            m = self.models[key]
            m.input_tokens += usage.input_tokens
            m.output_tokens += usage.output_tokens
            m.cache_read += usage.cache_read
            m.cache_write += usage.cache_write
            m.cost_usd += usage.cost_usd
            m.request_count += usage.request_count
        else:
            self.models[key] = usage


def _iter_jsonl(path: Path, limit: int = 1000) -> Iterable[dict]:
    """jsonl을 마지막 limit 줄까지 안전하게 순회."""
    if not path.exists():
        return []
    try:
        with path.open() as f:
            lines = f.readlines()
    except OSError:
        return []
    for line in lines[-limit:]:
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            continue


def parse_otel(log_path: Path | None = None) -> tuple[dict[str, ModelUsage], bool]:
    """L5: OTel file exporter의 claude_code.api_request 이벤트 파싱."""
    path = log_path or Path(os.environ.get("FORGE_GLOW_OTEL_LOG",
                                            Path.home() / ".forge-glow" / "otel.log"))
    usages: dict[str, ModelUsage] = {}
    available = path.exists()
    if not available:
        return usages, False
    for ev in _iter_jsonl(path, limit=2000):
        if ev.get("name") != "claude_code.api_request":
            continue
        attr = ev.get("attributes", {}) or {}
        key = short_model(attr.get("model", ""))
        u = usages.setdefault(key, ModelUsage(model=key))
        u.input_tokens += int(attr.get("input_tokens", 0) or 0)
        u.output_tokens += int(attr.get("output_tokens", 0) or 0)
        u.cache_read += int(attr.get("cache_read_tokens", 0) or 0)
        u.cost_usd += float(attr.get("cost_usd", 0) or 0)
        u.request_count += 1
    return usages, True


def parse_transcripts(projects_dir: Path | None = None) -> tuple[dict[str, ModelUsage], dict[str, int]]:
    """L2: 최근 세션 transcript 병합. OTel 없을 때 fallback."""
    root = projects_dir or Path(os.environ.get("CLAUDE_PROJECTS_DIR",
                                               Path.home() / ".claude" / "projects"))
    usages: dict[str, ModelUsage] = {}
    tools: dict[str, int] = {}
    if not root.exists():
        return usages, tools
    # 최근 5개 jsonl만 (성능)
    jsonls = sorted(root.rglob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:5]
    for jp in jsonls:
        for ev in _iter_jsonl(jp, limit=1000):
            et = ev.get("type")
            if et == "tool_use":
                name = ev.get("name") or "unknown"
                tools[name] = tools.get(name, 0) + 1
            if et == "assistant":
                msg = ev.get("message", {}) or {}
                usage = msg.get("usage", {}) or {}
                key = short_model(msg.get("model", ""))
                u = usages.setdefault(key, ModelUsage(model=key))
                u.input_tokens += int(usage.get("input_tokens", 0) or 0)
                u.output_tokens += int(usage.get("output_tokens", 0) or 0)
                u.cache_read += int(usage.get("cache_read_input_tokens", 0) or 0)
                u.cache_write += int(usage.get("cache_creation_input_tokens", 0) or 0)
                u.request_count += 1
    return usages, tools


def parse_forge_usage(usage_log: Path | None = None) -> tuple[dict[str, int], dict[str, int]]:
    """L3: code-forge bellows usage.jsonl — 에이전트/스킬 카운트 (최근 세션)."""
    path = usage_log or (Path.home() / ".code-forge" / "usage.jsonl")
    agents: dict[str, int] = {}
    skills: dict[str, int] = {}
    if not path.exists():
        return agents, skills
    for ev in _iter_jsonl(path, limit=5000):
        t = ev.get("type")
        name = ev.get("name") or "unknown"
        if t == "agent":
            agents[name] = agents.get(name, 0) + 1
        elif t == "skill":
            skills[name] = skills.get(name, 0) + 1
    return agents, skills


def parse_update_flag(state_dir: Path | None = None) -> str | None:
    path = (state_dir or Path(os.environ.get("FORGE_GLOW_STATE_DIR",
                                             Path.home() / ".forge-glow"))) / "update-available"
    if not path.exists():
        return None
    try:
        return path.read_text().strip() or "unknown"
    except OSError:
        return None


def parse_codex(codex_home: Path | None = None) -> tuple[bool, str | None, float]:
    root = codex_home or Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    sessions = root / "sessions"
    if not sessions.exists():
        return False, None, 0.0
    recent = [p for p in sessions.rglob("*.jsonl")
              if datetime.fromtimestamp(p.stat().st_mtime) > datetime.now() - timedelta(minutes=5)]
    if not recent:
        return False, None, 0.0
    recent.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    latest = recent[0]
    # 검증된 on-disk 스키마(event-schema.md §3): 모델은 turn_context.payload.model,
    # usage 는 payload.type=="token_count" 의 payload.info.total_token_usage (누적 — 마지막 1건만, 합산 X).
    # ⚠ 과거의 turn.completed / ev["model"] 스키마는 디스크에 존재하지 않아 항상 0이었음.
    model = None
    last_usage: dict | None = None
    for ev in _iter_jsonl(latest, limit=500):
        if ev.get("type") == "turn_context":
            m = (ev.get("payload") or {}).get("model")
            if m:
                model = m
        payload = ev.get("payload") or {}
        if payload.get("type") == "token_count":
            ttu = (payload.get("info") or {}).get("total_token_usage")
            if ttu:
                last_usage = ttu
    u = last_usage or {}
    inp = int(u.get("input_tokens", 0) or 0)
    cached = int(u.get("cached_input_tokens", 0) or 0)
    out = int(u.get("output_tokens", 0) or 0)
    key = short_model(model or "")
    p = PRICES_USD_PER_MTOK.get(key, PRICES_USD_PER_MTOK["gpt-4.1"])
    cost = (inp * p["input"] + out * p["output"] + cached * p["cache_read"]) / 1_000_000
    return True, model, round(cost, 2)


def build_snapshot() -> Snapshot:
    """모든 소스 통합 — L5 우선, L2 fallback."""
    snap = Snapshot()

    otel_usages, snap.otel_available = parse_otel()
    if snap.otel_available and otel_usages:
        for m in otel_usages.values():
            snap.add_model(m)
    else:
        l2_usages, tools = parse_transcripts()
        for m in l2_usages.values():
            snap.add_model(m)
        snap.tools_used = tools

    # 항상 tools (L5에서 빈 경우 L2로 보강)
    if not snap.tools_used:
        _, tools = parse_transcripts()
        snap.tools_used = tools

    snap.forge_agents, snap.forge_skills = parse_forge_usage()
    snap.update_available_reason = parse_update_flag()
    snap.codex_active, snap.codex_model, snap.codex_cost = parse_codex()

    # 총 비용 + 캐시 히트율
    total_input = total_cache_read = 0
    for m in snap.models.values():
        snap.total_cost_usd += m.estimate_cost()
        total_input += m.input_tokens + m.cache_read
        total_cache_read += m.cache_read
    if total_input > 0:
        snap.cache_hit_rate = total_cache_read / total_input * 100
    return snap
