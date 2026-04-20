"""Phase 6-1: Admin Analytics API 통합.

/v1/organizations/usage_report/claude_code 호출 → 조직 단위 일별 usage.
requests 의존.

환경변수:
    ANTHROPIC_ADMIN_API_KEY  - Admin API 키 (없으면 비활성)
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta


@dataclass
class OrgDayUsage:
    date: str
    total_cost_usd: float = 0.0
    total_tokens: int = 0
    per_model: dict[str, float] = field(default_factory=dict)


@dataclass
class OrgReport:
    available: bool = False
    days: list[OrgDayUsage] = field(default_factory=list)
    error: str | None = None


def fetch_org_report(days: int = 7) -> OrgReport:
    """최근 N일 조직 usage report. 키 없으면 available=False."""
    api_key = os.environ.get("ANTHROPIC_ADMIN_API_KEY", "").strip()
    if not api_key:
        return OrgReport(available=False, error="ANTHROPIC_ADMIN_API_KEY 미설정")

    try:
        import requests  # type: ignore
    except ImportError:
        return OrgReport(available=False, error="requests 미설치")

    end = datetime.utcnow().date()
    start = end - timedelta(days=days)
    try:
        resp = requests.get(
            "https://api.anthropic.com/v1/organizations/usage_report/claude_code",
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
            },
            params={
                "starting_at": start.isoformat(),
                "ending_at": end.isoformat(),
            },
            timeout=5,
        )
        resp.raise_for_status()
    except Exception as exc:  # noqa: BLE001
        return OrgReport(available=False, error=f"API 호출 실패: {exc}")

    data = resp.json() if resp.content else {}
    items = data.get("data") or data.get("usage") or []
    report = OrgReport(available=True)

    for item in items:
        day = OrgDayUsage(date=item.get("date") or item.get("day") or "")
        day.total_cost_usd = float(item.get("total_cost_usd") or 0)
        day.total_tokens = int(item.get("total_tokens") or 0)
        per_model = item.get("per_model") or {}
        if isinstance(per_model, dict):
            day.per_model = {k: float(v) for k, v in per_model.items()}
        report.days.append(day)

    return report
