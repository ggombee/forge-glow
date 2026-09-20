# forge-glow 로드맵

## 현재 목표

Claude Code와 Codex의 **각 세션이 자기 컨텍스트만 표시**하게 한다.
통합 대시보드와 세션 HUD를 구분하고, 추측한 세션 ID나 시세가 내장된
비용을 확정값처럼 표시하지 않는다.

## 완료된 기반

- [x] Claude statusLine stdin에서 모델, 레포/브랜치, context, 비용, rate limit 수집
- [x] 현재 `transcript_path`의 nested `message.content[].tool_use` 집계
- [x] 반복 assistant 레코드를 `message.id`로 중복 제거
- [x] 모델별 비용은 `~` 추정값으로 표시
- [x] `COLUMNS` 100 미만 터미널에서 context bar/도구 요약 축소
- [x] 근거 없는 auto-compact 시점 표기를 제거하고 임계값을 경고 용도로 한정
- [x] OTel file exporter의 OTLP/JSON envelope 파싱
- [x] OTel event를 현재 `session.id`로 격리
- [x] Slack alert 쿨다운 상태도 현재 `session_id`별로 격리
- [x] Codex native `tui.status_line` 설정 가이드
- [x] Claude HUD에서 전역 Codex 로그 결합 제거
- [x] tmux는 세션 값 대신 전역 활동 여부만 표시
- [x] 다른 status line을 플러그인 훅이 자동 래핑하지 않도록 충돌 처리
- [x] 전역 설치 여부만 보던 어댑터 계층 제거
- [x] 로컬 Claude 로그 집계용 Python dashboard/workflow 패널
- [x] golden render, Codex 누수, flat/OTLP OTel 세션 격리 회귀 테스트

## 설계 경계

| 기능 | source of truth | 범위 |
|---|---|---|
| Claude HUD | Claude statusLine stdin + 현재 transcript | 현재 Claude 세션 |
| Claude OTel 보강 | 현재 stdin `session_id`와 같은 event | 현재 Claude 세션 |
| Codex HUD | Codex native status line | 현재 Codex 세션 |
| Codex 앱/IDE/API 호스트 | custom TUI footer 미지원 | HUD 주입 안 함 |
| tmux summary | 최근 로그 mtime | 전역 활동 여부만 |
| Python dashboard | 최근 로컬 로그 | 집계 분석, 세션 HUD 아님 |

## 다음 개선 우선순위

### P1 — 정확성과 회귀

- [ ] 실제 Claude transcript에서 익명화한 스키마 fixture를 더 추가
- [ ] 모델 가격표를 코드에서 분리하고 갱신일/출처 메타데이터 표시
- [ ] fast mode, 1h cache write, data residency 가격 보정 fixture
- [ ] OTel rotation 파일을 포함한 세션 누적 집계 테스트

### P2 — 렌더링과 성능

- [ ] 터미널 `COLUMNS`에 따라 프로젝트/브랜치 안전 줄임 처리
- [ ] 60/80/100/160칸 golden snapshot 테스트
- [ ] 대용량 transcript/OTLP 기준 p50/p95 벤치마크를 CI에 추가
- [ ] 현재 `tail -N` 스냅샷을 byte offset cache로 바꾸는 것이 실제로 이득인지 측정

### P3 — 설치/운영

- [x] install/uninstall을 임시 HOME/settings.json으로 통합 테스트
- [x] 플러그인 캐시 경로 변경과 다른 HUD 충돌 fixture
- [ ] Windows/Git Bash에서 CRLF, `stat`, ANSI width 검증
- [x] 사용자가 직접 편집한 status line 옵션을 플러그인 훅이 보존하는지 검증
- [x] 직접 설치본과 활성 marketplace 캐시의 경로 충돌 진단
- [x] Codex CLI TUI와 앱/IDE/API 호스트의 지원 범위 명시
- [x] Claude 직접 marketplace와 Codex repo marketplace 동시 배포 구조
- [x] 두 plugin manifest와 패키지 버전의 release-time 동기화 검사
- [x] Claude/Codex 설치·업데이트·상태 확인 통합 명령
- [ ] clean Python 3.8/3.11 환경에서 sdist/wheel 빌드·설치 검증
- [ ] v0.9.0 release tarball SHA 반영 후 `brew audit --strict` 검증

## 비판적 평가

1. **두 제품의 HUD가 시각적으로 같지 않다.** Claude는 외부 command의 멀티라인
   렌더링을 허용하지만 Codex는 native built-in field만 제공한다. 현재 구조는 세션
   정확성은 지키지만, “동일 HUD”라는 기대를 만들면 제품 경험이 어긋난다.
2. **Claude plugin의 첫 SessionStart가 사용자 전역 `settings.json`을 수정한다.**
   기존 HUD는 보존하고 lock/atomic rename을 쓰지만, 설치 동작이 표시 설정 변경까지
   포함된다는 사실을 더 명확히 보여줘야 한다.
3. **비용·모델별 분해는 추정치다.** 총 context와 rate limit은 호스트 입력을
   따르지만 transcript 가격 계산은 모델명 정규화와 가격표 최신성에 민감하다.
4. **현재 성능 수치는 작은 fixture 중심이다.** refresh마다 shell/jq가 실행되고
   transcript tail을 다시 파싱하므로 긴 세션과 느린 디스크의 p95는 아직 보장하지 못한다.
5. **업데이트 확인과 실행 중 반영은 다르다.** Claude는 auto-update가 가능하지만
   reload가 필요하고, Codex는 marketplace snapshot 갱신과 새 세션이 필요하다. 이를
   숨기고 “즉시 hot update”로 표현하면 잘못된 약속이 된다.

## 개선 실행 순서

- **P0:** CI의 `tools/check-release.sh`/manifest 검사를 필수 gate로 유지하고,
  release candidate는 Claude marketplace와 Codex plugin 공식 validator도 통과시킨다.
- **P0:** 설치 문구와 진단 출력에서 현재 host가 CLI TUI인지 먼저 구분하고,
  non-TTY에서는 HUD가 보이지 않는 이유를 즉시 제시한다.
- **P1:** 가격표를 데이터 파일로 분리하고 출처·갱신일·confidence를 HUD/진단에 노출한다.
- **P1:** 60/80/100/160칸과 10MB 이상 transcript/OTel fixture로 렌더 정확도와
  p95 성능을 CI에서 측정한다.
- **P2:** Claude 설정 변경을 install/configure 단계로 더 분리하고, plugin manager가
  공식 설정 API를 제공하면 SessionStart의 직접 파일 수정을 교체한다.
- **P2:** Codex가 custom renderer 또는 자동 marketplace 갱신을 공식 지원할 때만
  native footer 이상의 시각적 parity/자동 반영을 추가한다.

## 성능 예산

| 경로 | 목표 |
|---|---:|
| transcript 없음 | p95 < 75ms |
| transcript 500줄 | p95 < 100ms |
| OTel 활성 | p95 < 150ms |

2026-08-18 로컬 smoke baseline은 transcript 없음 p95 42.8ms, 실제 transcript
tail 500 p95 43.1ms, OTLP fixture p95 47.4ms였습니다. 각각 20~30회 측정값이며
CI의 대용량 부하 벤치마크를 대신하지는 않습니다.

새로 등록한 status line은 Claude 이벤트 즉시 갱신 + 15초 refresh를 사용합니다.
기존 설치의 refresh/padding 사용자 옵션은 그대로 보존합니다. 성능을 높이려고 세션
격리나 표시 정확성을 포기하지 않습니다.
