# Codex 세션별 HUD 설정

Codex CLI는 현재 TUI 세션을 직접 아는 native status line을 제공합니다. forge-glow가 `~/.codex/sessions/`의 가장 최근 파일을 추측하지 않고 native 값을 쓰는 이유는, 동시에 여러 Codex/Claude 세션을 열어도 컨텍스트가 섞이지 않게 하기 위해서입니다.

## 지원 범위

`tui.status_line`은 이름 그대로 **터미널 Codex CLI의 TUI footer 전용**입니다.
Codex 데스크톱 앱, IDE 확장, API 또는 Orca 같은 비-TTY 호스트는 이 footer를
렌더하지 않으므로 이 설정으로 HUD를 주입할 수 없습니다. 해당 화면이 Codex 모델을
사용한다는 사실과 Codex CLI TUI를 실행 중이라는 사실은 서로 다릅니다.

## 권장 설정

forge-glow plugin을 먼저 설치하면 설정·검증 절차를 세션에서 바로 호출할 수 있습니다.

```bash
codex plugin marketplace add ggombee/forge-glow --ref main
codex plugin add forge-glow@forge-glow
```

새 Codex CLI 세션에서 `$forge-glow-statusline`을 호출하거나 다음 명령을 입력하세요.

```text
/statusline
```

다음 항목을 선택하면 실용적인 forge-glow 대응 값을 볼 수 있습니다.

- `model-with-reasoning`: 현재 모델과 reasoning effort
- `context-remaining`: **현재 Codex 세션**의 남은 컨텍스트
- `five-hour-limit`: 계정의 5시간 사용 한도
- `weekly-limit`: 계정의 7일(주간) 사용 한도
- `current-dir`: 현재 작업 디렉터리
- `git-branch`: 현재 Git 브랜치
- `fast-mode`: fast mode 활성 상태

선택값은 `$CODEX_HOME/config.toml`(기본 `~/.codex/config.toml`)에 저장됩니다. 직접 설정하려면 기존 `[tui]` 테이블에 다음을 추가하세요. `[tui]`가 이미 있으면 두 번 만들지 않습니다.

```toml
[tui]
status_line = [
  "model-with-reasoning",
  "context-remaining",
  "five-hour-limit",
  "weekly-limit",
  "current-dir",
  "git-branch",
  "fast-mode",
]
status_line_use_colors = true
```

Codex native footer가 계정에서 특정 사용 한도를 받지 못하면 해당 항목을
생략합니다. 예를 들어 `weekly-limit`만 보인다면 설정 순서 문제가 아니라 현재
계정 응답에 5시간 한도가 없는 경우일 수 있습니다. 또한 `tui.status_line`은
항목 순서만 받으며 라벨 alias/formatter를 받지 않습니다. 따라서 의미는 `7d`지만
현재 Codex 버전이 `weekly`로 렌더하면 forge-glow 설정만으로 그 문자열을 `7d`로
바꿀 수 없습니다.

`/statusline`에서 저장하면 현재 CLI footer가 즉시 갱신됩니다. 외부에서
`config.toml`만 편집했다면 이미 실행 중인 CLI는 설정을 다시 읽지 않을 수 있으므로
새 CLI 세션을 열거나 그 세션 안에서 `/statusline`을 한 번 실행하세요.

## 세션별 값과 계정 공유 값

| 표시 항목 | 범위 |
|---|---|
| 모델, reasoning, 작업 디렉터리, Git 브랜치, 컨텍스트 | 현재 Codex 세션 |
| 5시간/주간 사용 한도 | OpenAI 계정 공유 |

따라서 Codex 세션 A와 B의 `context-remaining`은 각각 다르게 표시되지만, `five-hour-limit`/`weekly-limit`은 같은 계정이면 같은 값이 표시되는 것이 정상입니다.

## 검증

1. Codex 세션을 두 개 열고 각각 서로 다른 작업량을 진행합니다.
2. 각 터미널 하단의 `Context ... left`가 각 세션 상태에 맞게 다른지 확인합니다.
3. 해당 세션에서 `/status`를 실행해 chat ID, context 사용량, rate limit을 교차 확인합니다.

Codex native status line은 현재 built-in 항목 목록을 렌더하며, Claude Code의 `statusLine.command`처럼 외부 쉘 스크립트의 멀티라인 출력이나 사용자 지정 라벨을 그대로 삽입하는 방식은 아닙니다.

## 플러그인 업데이트

```bash
codex plugin marketplace upgrade forge-glow
codex plugin add forge-glow@forge-glow
```

Codex marketplace는 명시적으로 snapshot을 갱신합니다. 갱신된 skill과 manifest는 새
Codex 세션부터 로드됩니다. Claude용 shell HUD는 별도 플러그인 패키지이며 Codex
세션 로그를 읽거나 Codex footer를 대신 렌더하지 않습니다.

Official OpenAI documentation: [Configuration Reference](https://developers.openai.com/codex/config-reference), [Developer commands](https://developers.openai.com/codex/cli/reference)
