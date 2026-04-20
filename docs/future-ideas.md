# 향후 고려 기능 (현재 활성화 불필요)

코드는 모두 작성돼 있지만 **실사용자 확대 / 팀 도입 / 배포 시점에만 의미**가 있는 기능들.
혼자 `git clone → install.sh`로 쓰는 지금 단계에선 아무것도 켤 필요 없음.

---

## 1. PyPI 배포 (Python 대시보드 공개)

**뭐:** `pip install forge-glow-stats`로 다른 사람이 대시보드만 설치하게 하는 인프라.

**필요 조건:**
- [ ] PyPI 계정 생성 (https://pypi.org/account/register/)
- [ ] API 토큰 발급 → GitHub repo secrets에 `PYPI_API_TOKEN` 등록
- [ ] 태그 푸시(`git tag v0.x.y && git push --tags`) 시 `.github/workflows/release.yml`이 자동 업로드

**지금 언제 필요:**
- 블로그/트위터 공유해서 외부 사용자 유치할 때
- "쉘 설치 부담스러운 사람 위한 Python-only 경로" 제공할 때

**방치해도:** 영향 없음. `stats/` 디렉터리 코드는 `PYTHONPATH=src python3 -m forge_glow_stats`로 본인만 돌려도 됨.

---

## 2. Homebrew tap 배포

**뭐:** `brew install ggombee/tap/forge-glow`로 macOS 사용자가 한 줄로 설치.

**필요 조건:**
- [ ] `ggombee/homebrew-tap` 레포 생성
- [ ] `Formula/forge-glow.rb` 복사 + `sha256`을 실제 릴리즈 tar.gz 해시로 교체
- [ ] `brew audit --strict` 통과 확인

**지금 언제 필요:**
- 친구/팀원에게 "아 brew install 한 줄이야" 수준으로 공유하고 싶을 때
- README에 "쉽게 설치" 뱃지 넣고 싶을 때

**방치해도:** 영향 없음. `git clone + install.sh` 경로로 모든 기능 사용 가능.

---

## 3. OTel L5 레이어 활성화

**뭐:** Claude Code가 OpenTelemetry로 내보내는 **Anthropic 계산 정확값**(`cost_usd`, `duration_ms`) 수집.

**필요 조건:**
- [ ] `CLAUDE_CODE_ENABLE_TELEMETRY=1` + `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`
- [ ] OTel Collector 설치 (`brew install opentelemetry-collector-contrib`)
- [ ] `~/.forge-glow/otel-config.yaml` 작성 (file exporter)
- [ ] collector 상시 백그라운드 실행

**지금 언제 필요:**
- L2 가격표 근사값이 실제 청구서와 눈에 띄게 차이 날 때
- 정확한 세션별 `cost_usd` 리포트 필요할 때

**방치해도:** `parse-transcript.sh`가 가격표로 근사 계산. 현재 오차 <5% 수준으로 충분.

---

## 4. Slack 알림 (Phase 6-2 원격 푸시)

**뭐:** 컨텍스트 80%↑ / 시간당 비용 $5↑ / rate limit 80%↑ 시 Slack 채널로 webhook 전송.

**필요 조건:**
- [ ] Slack workspace incoming webhook URL 발급
- [ ] `export FORGE_GLOW_SLACK_WEBHOOK=https://hooks.slack.com/services/...`

**지금 언제 필요:**
- 긴 작업 돌려놓고 자리 비울 때 원격 감시
- 팀에서 비용 폭증 공지할 때

**방치해도:** 경고 자체는 statusLine 3줄째에 그대로 뜸(🚨). 웹훅만 안 보내는 것.

---

## 5. Admin Analytics API (조직 단위 집계)

**뭐:** Anthropic Console의 조직(회사) 계정에서 **팀 전체 일별 사용량** 집계.

**필요 조건:**
- [ ] Anthropic Console Admin 권한
- [ ] Admin API 키 발급
- [ ] `export ANTHROPIC_ADMIN_API_KEY=...`
- [ ] `forge-glow-stats --org`

**지금 언제 필요:**
- 회사에서 Claude Code 팀 단위 도입해 비용 추적할 때
- 개인 계정으로는 API 권한 없음

**방치해도:** `--org` 플래그 안 쓰면 해당 호출 경로 타지 않음. 코드는 그대로 보관.

---

## 6. Standalone Rust/Node TUI (Phase 5-3 대체안)

현재 Python rich 대시보드로 대체 완료. 더 고성능·단일 바이너리 원하면 나중에:

- Rust + ratatui: 단일 static binary, `brew install` 쉬움
- Node + ink: React 패턴, npm 생태계

현재는 rich로도 충분(1초 이내 렌더, 5초 갱신).

---

## 참고 문서 (이미 작성됨)

| 기능 활성화하려면 | 참조 |
|------------------|------|
| OTel L5 | `docs/otel-setup.md` |
| Grafana 대시보드 | `docs/grafana-setup.md` |
| Homebrew tap 배포 | `Formula/README.md` |
| PyPI 배포 | `stats/pyproject.toml` + `.github/workflows/release.yml` |
| 주간 메트릭 수집 | `tools/metrics-report.sh` |
