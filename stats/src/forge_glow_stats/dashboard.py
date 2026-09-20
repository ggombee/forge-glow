"""forge-glow-stats Claude 로컬 집계 대시보드 (rich 기반).

rich.live.Live로 자동 갱신되는 최근 로컬 로그 집계 대시보드.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

from rich.align import Align
from rich.columns import Columns
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from .admin import OrgReport, fetch_org_report
from .parsers import Snapshot, build_snapshot
from .workflow import WorkflowSnapshot, build_workflow_snapshot


def _header(snap: Snapshot) -> Panel:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    flags = []
    if snap.otel_available:
        flags.append("[green]source:OTel (추정값)[/]")
    else:
        flags.append("[yellow]source:transcript (근사값)[/]")
    if snap.update_available_reason:
        flags.append(f"[red]⬆︎ update:{snap.update_available_reason}[/]")
    title = Text.from_markup(f"forge-glow stats  •  {now}  •  " + "  ".join(flags))
    return Panel(Align.center(title), border_style="bright_blue")


def _cost_table(snap: Snapshot) -> Panel:
    table = Table(title="모델별 추정비용 / 토큰", show_lines=False, expand=True)
    table.add_column("모델")
    table.add_column("요청", justify="right")
    table.add_column("input", justify="right")
    table.add_column("output", justify="right")
    table.add_column("cache_read", justify="right")
    table.add_column("~cost", justify="right", style="bold green")
    for m in sorted(snap.models.values(), key=lambda x: x.estimate_cost(), reverse=True):
        table.add_row(
            m.model,
            f"{m.request_count}",
            f"{m.input_tokens:,}",
            f"{m.output_tokens:,}",
            f"{m.cache_read:,}",
            f"~${m.estimate_cost():.3f}",
        )
    if not snap.models:
        table.add_row("—", "0", "0", "0", "0", "~$0.000")
    total = f"[bold]estimated total: ~${snap.total_cost_usd:.3f}  •  cache_hit: {snap.cache_hit_rate:.0f}%[/]"
    return Panel(Group(table, Text.from_markup(total)), title="Estimated cost", border_style="green")


def _tools_panel(snap: Snapshot) -> Panel:
    table = Table(show_header=True, header_style="bold", expand=True)
    table.add_column("Tool")
    table.add_column("Count", justify="right")
    for name, cnt in sorted(snap.tools_used.items(), key=lambda kv: kv[1], reverse=True)[:8]:
        table.add_row(name, str(cnt))
    if not snap.tools_used:
        table.add_row("—", "0")
    return Panel(table, title="Tool activity (recent transcript)", border_style="cyan")


def _org_panel(report: OrgReport | None) -> Panel:
    if not report:
        body = Text.from_markup("[dim]--org 플래그로 활성화. ANTHROPIC_ADMIN_API_KEY 필요.[/]")
        return Panel(body, title="Org usage (Admin Analytics)", border_style="dim")
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


_ITEM_MARK = {"done": "✅", "in_progress": "🔄", "blocked": "🚧"}
_KIND_LABEL = {"current": "현재", "next": "다음", "blocked": "대기"}


def _workflow_panel(wf: WorkflowSnapshot) -> Panel:
    if wf.error:
        return Panel(Text.from_markup(f"[red]workflow config error: {wf.error}[/]"),
                     title="Workflow", border_style="red")

    lines: list[str] = []
    for proj in wf.projects:
        head = f"[bold]{proj.display_name}[/]"
        if proj.epic_id:
            epic_link = f"[link={proj.epic_url}]{proj.epic_id}[/link]" if proj.epic_url else proj.epic_id
            head += f"  •  epic: {epic_link}"
        if proj.branch:
            head += f"  •  [cyan]{proj.branch}[/]"
        lines.append(head)

        if not proj.repo_exists:
            lines.append(f"  [yellow]⚠ repo missing: {proj.repo_path}[/]")
            lines.append("")
            continue

        for item in proj.items:
            mark = _ITEM_MARK.get(item.status, "⏸")
            kind = _KIND_LABEL.get(item.kind, item.kind)
            id_str = f"[link={item.url}]{item.id}[/link]" if item.url else item.id
            commits = f" [dim]({item.commits} commits)[/]" if item.commits else ""
            dep = f" [dim](deps: {item.depends_on})[/]" if item.depends_on else ""
            lines.append(f"  {mark} [magenta]{kind}[/] {id_str}  {item.title}{commits}{dep}")

        if proj.pending_urgent or proj.pending_hold:
            urgent = ", ".join(q["id"] for q in proj.pending_urgent)
            hold = ", ".join(q["id"] for q in proj.pending_hold)
            parts = []
            if urgent:
                parts.append(f"[red]🔴 {urgent}[/]")
            if hold:
                parts.append(f"[yellow]🟡 {hold}[/]")
            lines.append(f"  미결정: {'  '.join(parts)}")

        if proj.decisions:
            recent = [d["id"] for d in proj.decisions[-3:][::-1]]
            lines.append(f"  최근 결정: [green]{', '.join(recent)}[/]")

        if proj.builds:
            shas = [b["sha"][:8] for b in proj.builds[:3]]
            lines.append(f"  빌드: [dim]{' · '.join(shas)}[/]")

        if proj.last_updated:
            lines.append(f"  [dim]progress: {proj.last_updated}[/]")
        lines.append("")

    if not lines:
        lines = ["[dim]workflow config 없음 또는 projects 비어있음.[/]"]

    title = f"Workflow ({Path(wf.config_path).name})" if wf.config_path else "Workflow"
    return Panel(Text.from_markup("\n".join(lines).rstrip()),
                 title=title, border_style="bright_magenta")


def render(snap: Snapshot, org: OrgReport | None,
           workflow: WorkflowSnapshot | None = None) -> Group:
    top = Columns([_cost_table(snap), _tools_panel(snap)], equal=True, expand=True)
    bottom = _org_panel(org)
    parts = [_header(snap), top, bottom]
    if workflow and workflow.available:
        parts.append(_workflow_panel(workflow))
    return Group(*parts)


def run(refresh: float = 5.0, org_days: int = 7, include_org: bool = False,
        console: Console | None = None, once: bool = False,
        include_workflow: bool = True) -> None:
    console = console or Console()
    org_report: OrgReport | None = fetch_org_report(days=org_days) if include_org else None
    wf: WorkflowSnapshot | None = build_workflow_snapshot() if include_workflow else None

    if once:
        snap = build_snapshot()
        console.print(render(snap, org_report, wf))
        return

    with Live(console=console, refresh_per_second=1, screen=False) as live:
        try:
            import time
            while True:
                snap = build_snapshot()
                if include_org and not org_report:
                    org_report = fetch_org_report(days=org_days)
                if include_workflow:
                    wf = build_workflow_snapshot()
                live.update(render(snap, org_report, wf))
                time.sleep(refresh)
        except KeyboardInterrupt:
            pass
