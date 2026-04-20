# Grafana 대시보드 — forge-glow

`docs/grafana-dashboard.json`을 Grafana에 임포트하면 OTel 이벤트 기반 5패널 대시보드가 생성됩니다.

## 전제조건

1. `docs/otel-setup.md`에 따라 Claude Code OTel 활성화 완료
2. OTel Collector의 **Prometheus exporter**가 scrape 엔드포인트 노출
3. Prometheus가 해당 엔드포인트를 수집 중

OTel Collector 설정 예시:
```yaml
exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [prometheus]
```

Prometheus `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'claude-code'
    scrape_interval: 15s
    static_configs:
      - targets: ['localhost:8889']
```

## 임포트

1. Grafana UI → Dashboards → Import
2. `forge-glow/docs/grafana-dashboard.json` 업로드
3. Datasource로 Prometheus 선택

## 패널

| 패널 | 설명 |
|------|------|
| 모델별 누적 비용 | `claude_code_api_request_cost_usd_total` 모델별 rate |
| 캐시 히트율 | `cache_read_tokens / (input_tokens + cache_read_tokens) × 100` |
| 평균 응답 시간 | `duration_ms_sum / duration_ms_count` |
| 도구 호출 성공률 | `claude_code.tool_result`의 `success=true` 비율 (tool_name별) |
| 모델별 토큰 사용량 (24h) | input/output separate, 모델 필터 지원 |

## 주의

- metric 이름 규칙은 Collector 설정에 따라 다를 수 있음 (점을 언더스코어로 변환 등). 필요 시 `expr`의 metric 이름을 환경에 맞게 조정.
- Admin Analytics API (조직 단위 집계)는 TUI Phase에서 별도 패널로 합류 예정.
