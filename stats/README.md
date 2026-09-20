# forge-glow-stats

`forge-glow-stats`는 최근 로컬 Claude Code transcript 또는 OTel logs를 집계하는
선택적 Rich 대시보드입니다. 현재 세션만 표시하는 `hud/statusline.sh`와
달리, 이 패키지는 여러 최근 로그의 분석 뷰입니다. 표시 비용은 OTel 또는
공개 가격표를 사용한 추정값이며 청구 확정액이 아닙니다.

```bash
python3 -m pip install -e ./stats
forge-glow-stats --once
forge-glow-stats --json
```

전체 설정과 세션 격리 원칙은 상위 [README](../README.md)를 참조하세요.
