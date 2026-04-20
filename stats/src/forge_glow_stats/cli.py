"""forge-glow-stats CLI 진입점."""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict

from . import __version__
from .admin import fetch_org_report
from .parsers import build_snapshot
# dashboard는 rich 의존이므로 --json 경로에선 로드하지 않도록 lazy import.


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="forge-glow-stats",
        description="Dashboard for Claude Code + Codex CLI efficiency",
    )
    parser.add_argument("--version", action="version", version=f"forge-glow-stats {__version__}")
    parser.add_argument("--refresh", type=float, default=5.0,
                        help="자동 갱신 주기(초). 기본 5. --once면 무시")
    parser.add_argument("--once", action="store_true", help="한 번만 렌더 후 종료")
    parser.add_argument("--json", action="store_true", help="rich 렌더 대신 JSON 출력")
    parser.add_argument("--org", action="store_true",
                        help="Admin Analytics API 조직 리포트 포함 (ANTHROPIC_ADMIN_API_KEY 필요)")
    parser.add_argument("--org-days", type=int, default=14,
                        help="Org 리포트 기간(일). 기본 14")
    args = parser.parse_args(argv)

    if args.json:
        snap = build_snapshot()
        payload = {
            "snapshot": {
                "total_cost_usd": snap.total_cost_usd,
                "cache_hit_rate": snap.cache_hit_rate,
                "otel_available": snap.otel_available,
                "update_available_reason": snap.update_available_reason,
                "codex_active": snap.codex_active,
                "codex_model": snap.codex_model,
                "codex_cost_usd": snap.codex_cost,
                "models": {k: asdict(v) for k, v in snap.models.items()},
                "tools_used": snap.tools_used,
                "forge_agents": snap.forge_agents,
                "forge_skills": snap.forge_skills,
            }
        }
        if args.org:
            report = fetch_org_report(days=args.org_days)
            payload["org"] = {
                "available": report.available,
                "error": report.error,
                "days": [asdict(d) for d in report.days],
            }
        json.dump(payload, sys.stdout, default=str, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    try:
        try:
            from .dashboard import run
        except ImportError as exc:
            print(f"rich 패키지 필요: pip install rich\n세부: {exc}", file=sys.stderr)
            return 1
        run(refresh=args.refresh, org_days=args.org_days,
            include_org=args.org, once=args.once)
    except Exception as exc:  # noqa: BLE001
        print(f"forge-glow-stats error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
