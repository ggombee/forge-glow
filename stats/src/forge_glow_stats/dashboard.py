"""forge-glow-stats 대시보드 렌더링 (rich 기반).

rich.live.Live + Layout으로 자동 갱신되는 5초 refresh 대시보드.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any

from rich.align import Align
from rich.columns import Columns
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.progress_bar import ProgressBar
from rich.table import Table
from rich.text import Text

from .admin import OrgReport, fetch_org_report
from .parsers import Snapshot, build_snapshot


def _header(snap: Snapshot) -> Panel:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    flags = []
    if snap.otel_available:
        flags.append("[green]L5:OTel[/]")
    else:
        flags.append("[yellow]L5:off (근사값)[/]")
    if snap.forge_agents or snap.forge_skills:
        flags.append("[cyan]L3:code-forge[/]")
    if snap.codex_active:
        flags.append(f"[magenta]Codex:{snap.codex_model or '?'}[/]")
    if snap.update_available_reason:
        flags.append(f"[red]⬆︎ update:{snap.update_available_reason}[/]")
    title = Text.from_markup(f"forge-glow stats  •  {now}  •  " + "  ".join(flags))
    return Panel(Align.center(title), border_style="bright_blue")


def _cost_table(snap: Snapshot) -> Panel:
    table = Table(title="모델별 비용 / 토큰", show_lines=False, expand=True)
    table.add_column("모델")
    table.add_column("요청", justify="right")
    table.add_column("input", justify="right")
    table.add_column("output", justify="right")
    table.add_column("cache_read", justify="right")
    table.add_column("cost", justify="right", style="bold green")
    for m in sorted(snap.models.values(), key=lambda x: x.estimate_cost(), reverse=True):
        table.add_row(
            m.model,
            f"{m.request_count}",
            f"{m.input_tokens:,}",
            f"{m.output_tokens:,}",
            f"{m.cache_read:,}",
            f"${m.estimate_cost():.3f}",
        )
    if not snap.models:
        table.add_row("—", "0", "0", "0", "0", "$0.000")
    total = f"[bold]total: ${snap.total_cost_usd:.3f}  •  cache_hit: {snap.cache_hit_rate:.0f}%[/]"
    return Panel(Group(table, Text.from_markup(total)), title="Cost", border_style="green")


def _tools_panel(snap: Snapshot) -> Panel:
    table = Table(show_header=True, header_style="bold", expand=True)
    table.add_column("Tool")
    table.add_column("Count", justify="right")
    for name, cnt in sorted(snap.tools_used.items(), key=lambda kv: kv[1], reverse=True)[:8]:
        table.add_row(name, str(cnt))
    if not snap.tools_used:
        table.add_row("—", "0")
    return Panel(table, title="Tool activity (L2)", border_style="cyan")


def _forge_panel(snap: Snapshot) -> Panel:
    lines = []
    if snap.forge_agents:
        top = sorted(snap.forge_agents.items(), key=lambda kv: kv[1], reverse=True)[:5]
        lines.append("Agents: " + "  ".join(f"{k}×{v}" for k, v in top))
    if snap.forge_skills:
        top = sorted(snap.forge_skills.items(), key=lambda kv: kv[1], reverse=True)[:5]
        lines.append("Skills: " + "  ".join(f"/{k}×{v}" for k, v in top))
    if not lines:
        lines.append("[dim]code-forge usage 없음 (~/.code-forge/usage.jsonl 비어있음)[/]")
    return Panel(Text.from_markup("\n".join(lines)), title="code-forge (L3)", border_style="magenta")


def _tips_panel(snap: Snapshot) -> Panel:
    tips = []
    if snap.cache_hit_rate < 40 and snap.models:
        tips.append("🔥 캐시 히트율 40% 미만 — /compact 타이밍 조정 권장")
    opus_cost = snap.models.get("opus")
    if opus_cost and opus_cost.estimate_cost() > snap.total_cost_usd * 0.6:
        tips.append("💡 opus가 전체 비용의 60% 이상 — 단순 Read/Grep은 haiku 위임 고려")
    if snap.codex_active and snap.codex_cost > 2:
        tips.append(f"💰 Codex 세션 ${snap.codex_cost} — 큰 작업이면 Claude로 분할 고려")
    if snap.update_available_reason == "dirty":
        tips.append("⬆︎ forge-glow 업데이트 가능 — 현재 로컬 변경으로 스킵됨. commit/stash 후 수동 pull")
    if not tips:
        tips.append("[dim]현재 경고 없음. 지표 모두 정상 범위.[/]")
    return Panel(Text.from_markup("\n".join(f"• {t}" for t in tips)),
                 title="Savings tips", border_style="yellow")


def _org_panel(report: OrgReport | None) -> Panel:
    if not report:
        body = Text.from_markup("[dim]--org 플래그로 활성화. ANTHROPIC_ADMIN_API_KEY 필요.[/]")
        return Panel(body, title="Org usage (Admin Analytics, Phase 6-1)", border_style="dim")
    if not report.available:
        return Panel(Text.from_markup(f"[red]{report.error}[/]"),
                     title="Org usage (Admin Analytics)", border_style="red")

    table = Table(show_header=True, expand=True)
    table.add_column("날짜")
    table.add_column("비용 USD", justify="right")
    table.add_column("토큰", justify="right")
    for d in report.days[-14:]:
        table.add_row(d.date, f"${d.total_cost_usd:.2f}", f"{d.total_tokens:,}")
    if not report.days:
        table.add_row("—", "$0.00", "0")
    return Panel(table, title="Org usage (최근 14일, Admin Analytics)", border_style="blue")


def render(snap: Snapshot, org: OrgReport | None) -> Group:
    top = Columns([_cost_table(snap), _tools_panel(snap)], equal=True, expand=True)
    mid = Columns([_forge_panel(snap), _tips_panel(snap)], equal=True, expand=True)
    bottom = _org_panel(org)
    return Group(_header(snap), top, mid, bottom)


def run(refresh: float = 5.0, org_days: int = 7, include_org: bool = False,
        console: Console | None = None, once: bool = False) -> None:
    console = console or Console()
    org_report: OrgReport | None = fetch_org_report(days=org_days) if include_org else None

    if once:
        snap = build_snapshot()
        console.print(render(snap, org_report))
        return

    with Live(console=console, refresh_per_second=1, screen=False) as live:
        try:
            import time
            while True:
                snap = build_snapshot()
                if include_org and not org_report:
                    org_report = fetch_org_report(days=org_days)
                live.update(render(snap, org_report))
                time.sleep(refresh)
        except KeyboardInterrupt:
            pass
