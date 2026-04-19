# tmux 통합 — Claude + Codex HUD

Claude Code의 statusLine은 자기 영역에만 표시되지만, Codex CLI는 statusLine이 없습니다. **tmux 하단바**가 두 도구의 상태를 한 곳에서 보는 현실적 통합 지점입니다.

---

## 설정

`~/.tmux.conf`에 추가:

```tmux
set -g status-right-length 150
set -g status-right "#(/Users/YOUR_USER/Desktop/workspace/forge-glow/tmux/status-right.sh)"
set -g status-interval 5
```

`status-interval 5` — 5초마다 갱신. forge-glow statusLine의 refreshInterval과 맞춤.

reload:
```bash
tmux source-file ~/.tmux.conf
```

---

## 표시 예시

### Codex 활성 세션

```
🤖 codex:gpt-5 $0.42 ctx:34% turns:12
```

### Claude Code 활성

```
🧠 claude (statusLine 참조)
```
→ Claude Code 세션은 자체 statusLine을 쓰므로 중복 방지 차원에서 tmux엔 간단 표시만.

### 아무 도구도 최근 5분 내 활동 없음

```
(빈 문자열)
```

---

## 비tmux 환경 대안

### Starship

`~/.config/starship.toml`에 custom module:

```toml
[custom.forge_glow]
command = "/path/to/forge-glow/tmux/status-right.sh"
when = "true"
format = "[$output]($style) "
```

### zsh RPROMPT

`~/.zshrc`:

```bash
forge_glow_status() {
  /path/to/forge-glow/tmux/status-right.sh
}
RPROMPT='$(forge_glow_status)'
```

---

## 동작 원리

1. `~/.claude/projects/**/*.jsonl`과 `~/.codex/sessions/**/*.jsonl`의 mtime을 비교
2. 5분 이내 수정된 파일이 있고, 더 최근인 쪽을 "활성 도구"로 간주
3. Codex면 `parse-codex.sh`로 model/cost/ctx/turns 뽑아 출력
4. Claude면 자체 statusLine이 더 풍부하므로 간단 표시만

---

## 성능

| 작업 | 예상 시간 |
|------|----------|
| find mtime 체크 | <10ms |
| parse-codex.sh (tail -200) | <50ms |
| 총 예산 | <100ms (tmux 5초 간격이라 넉넉) |
