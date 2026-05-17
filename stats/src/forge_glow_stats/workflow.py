"""Workflow integration — 다중 프로젝트 작업 컨텍스트(현재/다음 item, 결정 누적, 빌드, 미결정 Q).

Config: ~/.forge-glow/workflow.json (없으면 비활성). sources schema v2.
Parser: section selector 기반 progress 문서 파싱 + 내장 preset 3종(decision-log / simple-todo / kanban-md).

회사 데이터/내부 식별자는 코드 + 예시에 0건. 사용자의 ~/.forge-glow/workflow.json 에만 존재.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


# ─── Config 경로 해결 ────────────────────────────────────────

def _resolve_config_path() -> Path | None:
    candidates = [
        os.environ.get("WORKFLOW_CONFIG_PATH"),
        str(Path.home() / ".forge-glow" / "workflow.json"),
    ]
    for c in candidates:
        if c and Path(c).is_file():
            return Path(c)
    return None


# ─── Preset 로더 ────────────────────────────────────────────

_PRESETS_DIR = Path(__file__).parent / "presets" / "progress"


def _load_preset(name: str) -> dict[str, Any]:
    path = _PRESETS_DIR / f"{name}.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data.get("selectors", {})
    except Exception:
        return {}


def _resolve_selectors(progress: dict[str, Any] | None) -> dict[str, Any]:
    if not progress:
        return {}
    if "selectors" in progress and progress["selectors"]:
        return progress["selectors"]
    if "preset" in progress and progress["preset"]:
        return _load_preset(progress["preset"])
    return {}


# ─── Section 추출 ───────────────────────────────────────────

_PLACEHOLDER_RE = re.compile(r"^[\(（]?(없음|none|n/a|-|—|_)[\)）]?$", re.IGNORECASE)


def _split_section(text: str, section_regex: str) -> str | None:
    m = re.search(section_regex, text, re.MULTILINE)
    if not m:
        return None
    header = m.group(0)
    start = m.end()
    level_m = re.match(r"^#+", header)
    level = len(level_m.group(0)) if level_m else 1
    rest = text[start:]
    next_re = re.compile(rf"\n#{{1,{level}}}\s", re.MULTILINE)
    nxt = next_re.search(rest)
    return rest[: nxt.start()] if nxt else rest


# ─── 포맷별 파서 ───────────────────────────────────────────

def _parse_table(block: str, sel: dict[str, Any]) -> list[dict[str, Any]]:
    id_col = sel.get("idColumn", 0)
    title_col = sel.get("titleColumn", 1)
    extra = sel.get("extraColumns", {})
    id_pattern = re.compile(sel["idPattern"]) if sel.get("idPattern") else None

    rows = []
    for line in block.split("\n"):
        line = line.strip()
        if not line.startswith("|"):
            continue
        if re.match(r"^\|\s*[-:]+\s*\|", line):
            continue
        cols = [c.strip() for c in line.split("|")[1:-1]]
        if len(cols) <= max(id_col, title_col):
            continue
        item_id = cols[id_col]
        if not item_id:
            continue
        if re.match(r"^(#|항목|id|item)$", item_id, re.IGNORECASE):
            continue
        if id_pattern and not id_pattern.search(item_id):
            continue
        if _PLACEHOLDER_RE.match(item_id):
            continue
        row = {"id": item_id, "title": cols[title_col] if title_col < len(cols) else ""}
        for key, col_idx in extra.items():
            if isinstance(col_idx, int) and col_idx < len(cols):
                row[key] = cols[col_idx]
        rows.append(row)
    return rows


def _parse_checkbox(block: str, sel: dict[str, Any]) -> list[dict[str, Any]]:
    want_checked = sel.get("stateFilter") == "checked"
    want_open = sel.get("stateFilter") == "open"
    items = []
    n = 1
    for m in re.finditer(r"^\s*-\s*\[(.)\]\s*(.+)$", block, re.MULTILINE):
        checked = m.group(1).strip().lower() == "x"
        if want_checked and not checked:
            continue
        if want_open and checked:
            continue
        items.append({"id": f"#{n}", "title": m.group(2).strip(), "checked": checked})
        n += 1
    return items


def _parse_bullet(block: str, _sel: dict[str, Any]) -> list[dict[str, Any]]:
    items = []
    n = 1
    for m in re.finditer(r"^\s*[-*]\s+(.+)$", block, re.MULTILINE):
        text = m.group(1).strip()
        if re.match(r"^\[.\]", text):
            continue
        items.append({"id": f"#{n}", "title": text})
        n += 1
    return items


_PARSERS = {
    "table": _parse_table,
    "checkbox": _parse_checkbox,
    "bullet": _parse_bullet,
}


def _parse_block(block: str | None, sel: dict[str, Any]) -> list[dict[str, Any]]:
    if not block:
        return []
    fmt = sel.get("format")
    fn = _PARSERS.get(fmt)
    return fn(block, sel) if fn else []


# ─── Progress 파싱 ──────────────────────────────────────────

def _parse_progress(text: str, selectors: dict[str, Any]) -> dict[str, Any]:
    result = {
        "last_updated": None,
        "pending_urgent": [],
        "pending_hold": [],
        "decisions": [],
    }
    if not text or not selectors:
        return result
    for key, sel in selectors.items():
        if sel.get("regex"):
            m = re.search(sel["regex"], text)
            if m and key == "lastUpdated":
                result["last_updated"] = (m.group(1) if m.lastindex else m.group(0)).strip()
            continue
        if sel.get("section"):
            block = _split_section(text, sel["section"])
            items = _parse_block(block, sel)
            if key == "pending_urgent":
                result["pending_urgent"] = items
            elif key == "pending_hold":
                result["pending_hold"] = items
            elif key == "decisions":
                result["decisions"] = items
    return result


# ─── Git 메타 ──────────────────────────────────────────────

def _git_branch(repo: Path) -> str | None:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo), "rev-parse", "--abbrev-ref", "HEAD"],
            stderr=subprocess.DEVNULL, encoding="utf-8", timeout=2,
        )
        return out.strip() or None
    except Exception:
        return None


# ─── 빌드 리포트 ───────────────────────────────────────────

def _collect_builds(repo: Path, rel_dir: str | None) -> list[dict[str, Any]]:
    if not rel_dir:
        return []
    abs_dir = repo / rel_dir
    if not abs_dir.is_dir():
        return []
    builds = []
    for ent in abs_dir.iterdir():
        if not ent.is_dir() or ent.name == "figma":
            continue
        meta_path = ent / "meta.json"
        if not meta_path.is_file():
            continue
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        builds.append({
            "sha": ent.name,
            "subject": (meta.get("commit") or {}).get("subject"),
            "date": (meta.get("commit") or {}).get("date"),
            "case_count": len(meta.get("cases") or []),
            "commit_url": meta.get("commitUrl"),
            "index_html": str(ent / "index.html"),
        })
    builds.sort(key=lambda b: b.get("date") or "", reverse=True)
    return builds


# ─── Tracker URL ──────────────────────────────────────────

def _build_url(tracker: dict[str, Any] | None, item_id: str) -> str | None:
    if not tracker or not tracker.get("browseUrl"):
        return None
    return tracker["browseUrl"].replace("{id}", item_id)


# ─── Snapshot 모델 ────────────────────────────────────────

def _expand(p: str) -> Path:
    if p.startswith("~/"):
        return Path.home() / p[2:]
    return Path(p)


@dataclass
class WorkflowItem:
    id: str
    title: str = ""
    status: str = "ready"
    kind: str = "next"
    url: str | None = None
    commits: int | None = None
    depends_on: str | None = None


@dataclass
class WorkflowProject:
    id: str
    display_name: str
    repo_path: str
    branch: str | None = None
    epic_id: str | None = None
    epic_title: str | None = None
    epic_url: str | None = None
    items: list[WorkflowItem] = field(default_factory=list)
    builds: list[dict[str, Any]] = field(default_factory=list)
    pending_urgent: list[dict[str, Any]] = field(default_factory=list)
    pending_hold: list[dict[str, Any]] = field(default_factory=list)
    decisions: list[dict[str, Any]] = field(default_factory=list)
    last_updated: str | None = None
    links: dict[str, str] = field(default_factory=dict)
    repo_exists: bool = True


@dataclass
class WorkflowSnapshot:
    available: bool = False
    config_path: str | None = None
    error: str | None = None
    projects: list[WorkflowProject] = field(default_factory=list)


# ─── Snapshot 빌더 ────────────────────────────────────────

def _collect_project(proj: dict[str, Any], trackers: dict[str, Any]) -> WorkflowProject:
    repo = _expand(proj.get("path", "."))
    tracker = trackers.get(proj.get("trackerRef")) if proj.get("trackerRef") else None

    epic = proj.get("epic") or {}
    project = WorkflowProject(
        id=proj.get("id", "unknown"),
        display_name=proj.get("displayName") or proj.get("id", "unknown"),
        repo_path=str(repo),
        epic_id=epic.get("id"),
        epic_title=epic.get("title"),
        epic_url=_build_url(tracker, epic["id"]) if epic.get("id") else None,
        links=proj.get("links", {}),
        repo_exists=repo.is_dir(),
    )

    for raw in proj.get("items", []) or []:
        project.items.append(WorkflowItem(
            id=raw.get("id", "?"),
            title=raw.get("title", ""),
            status=raw.get("status", "ready"),
            kind=raw.get("kind", "next"),
            url=_build_url(tracker, raw["id"]) if raw.get("id") else None,
            commits=raw.get("commits"),
            depends_on=raw.get("dependsOn"),
        ))

    if not project.repo_exists:
        return project

    project.branch = _git_branch(repo)

    sources = proj.get("sources") or {}
    project.builds = _collect_builds(repo, sources.get("buildReportsDir"))

    progress_cfg = proj.get("progress")
    if progress_cfg and progress_cfg.get("file"):
        progress_file = repo / progress_cfg["file"]
        if progress_file.is_file():
            try:
                text = progress_file.read_text(encoding="utf-8")
                selectors = _resolve_selectors(progress_cfg)
                parsed = _parse_progress(text, selectors)
                project.pending_urgent = parsed["pending_urgent"]
                project.pending_hold = parsed["pending_hold"]
                project.decisions = parsed["decisions"]
                project.last_updated = parsed["last_updated"]
            except Exception:
                pass

    return project


def build_workflow_snapshot() -> WorkflowSnapshot:
    """Config 자동 감지 후 WorkflowSnapshot 생성. 없으면 available=False 반환."""
    config_path = _resolve_config_path()
    if not config_path:
        return WorkflowSnapshot(available=False)

    try:
        sources = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception as e:
        return WorkflowSnapshot(available=False, config_path=str(config_path), error=f"config parse error: {e}")

    trackers = sources.get("trackers") or {}
    snap = WorkflowSnapshot(available=True, config_path=str(config_path))

    for proj in sources.get("projects") or []:
        try:
            snap.projects.append(_collect_project(proj, trackers))
        except Exception as e:
            # 개별 프로젝트 실패는 전체 비활성화로 이어지지 않음.
            snap.projects.append(WorkflowProject(
                id=proj.get("id", "?"),
                display_name=proj.get("displayName") or proj.get("id", "?"),
                repo_path=str(_expand(proj.get("path", "."))),
                repo_exists=False,
                last_updated=f"error: {e}",
            ))
    return snap
