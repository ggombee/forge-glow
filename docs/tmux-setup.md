# tmux Codex 계정 배지와 전역 활동 요약

`tmux/status-right.sh`는 `~/.claude/projects` 또는 `~/.codex/sessions`에서 최근
5분 내 갱신된 JSONL이 있는지 확인합니다. Codex launcher가 현재 pane의
`@forge_glow_codex_account` option을 설정하면 `👤 codex:개인` 또는
`👤 codex:회사`를 우선 표시합니다.

계정 배지는 launcher가 선택 직후 전달한 pane-scoped 값만 사용하며 세션 로그에서
계정을 추측하지 않습니다. launcher 연동이 없을 때만 전역 최근 활동 표시로
내려갑니다. 모델, 비용, context 같은 세션별 값은 Claude statusLine과
[Codex native status line](codex-setup.md)이 source of truth입니다.

## 설정

```tmux
set -g status-right-length 120
set -g status-right "#(/absolute/path/to/forge-glow/tmux/status-right.sh '#{pane_id}' '#{pane_current_command}')"
set -g status-interval 5
```

적용:

```bash
tmux source-file ~/.tmux.conf
```

## 출력

```text
👤 codex:개인
👤 codex:회사
🌐 codex active (native status line 참조)  🧠 claude active (statusLine 참조)
```

Codex 계정 전환 launcher는 Codex를 실행하기 전에 다음처럼 현재 pane option을
설정하면 됩니다.

```bash
tmux set-option -p -t "$TMUX_PANE" @forge_glow_codex_account personal
```

지원 값은 `personal`, `company`입니다. badge는 foreground command가 `codex`일 때만
보이므로 Codex를 종료하면 예전 계정 값이 남아 있어도 표시되지 않습니다. 계정
연동 없이 최근 활동만 보이는 경우에는 이를 단지 “어떤 도구가 최근에
활동했다”는 신호로 해석하세요.
