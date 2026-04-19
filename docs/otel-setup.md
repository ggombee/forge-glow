# OTel 셋업 — L5 레이어 활성화

forge-glow의 **L5 레이어**는 Claude Code의 OpenTelemetry 이벤트를 직접 소비합니다.
활성화하면 L2 transcript 파싱의 **근사 계산**을 Anthropic이 계산한 **정확값**으로 대체합니다.

| 레이어 | 데이터 소스 | 정확도 |
|--------|------------|--------|
| L2 (기본) | `transcript.jsonl` 파싱 + forge-glow 가격표 곱셈 | 근사값 (모델 가격 변경 시 수동 업데이트 필요) |
| **L5 (OTel)** | `claude_code.api_request` 이벤트의 `cost_usd`, `duration_ms` | **정확값** (Anthropic 계산) |

---

## 1. Claude Code 텔레메트리 활성화

```bash
# ~/.zshrc 또는 ~/.bashrc에 추가
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1   # traces beta (분산 트레이싱)
```

rstart Claude Code 세션.

---

## 2. OTLP collector — file exporter 설정

forge-glow는 JSONL 파일 한 줄당 하나의 이벤트를 소비합니다. OTel Collector의 **file exporter**를 사용하세요.

### 설치 (macOS)

```bash
brew install opentelemetry-collector-contrib
```

### 설정 파일 `~/.forge-glow/otel-config.yaml`

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

exporters:
  file:
    path: /Users/YOUR_USER/.forge-glow/otel.log
    rotation:
      max_megabytes: 10
      max_days: 3
      max_backups: 3

service:
  pipelines:
    metrics:
      receivers: [otlp]
      exporters: [file]
    traces:
      receivers: [otlp]
      exporters: [file]
```

### 실행 (백그라운드)

```bash
otelcol-contrib --config ~/.forge-glow/otel-config.yaml &
```

---

## 3. Claude Code → OTLP endpoint 지정

```bash
# ~/.zshrc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
```

---

## 4. forge-glow에서 로그 경로 인식

기본값은 `$HOME/.forge-glow/otel.log`. 다른 경로를 쓰면:

```bash
export FORGE_GLOW_OTEL_LOG=/path/to/otel.log
```

---

## 5. 검증

```bash
# Claude Code 몇 턴 사용 후
ls -lh ~/.forge-glow/otel.log   # 파일 크기 증가 확인
tail -1 ~/.forge-glow/otel.log | jq   # 이벤트 JSON 확인
```

forge-glow 재시작하면 statusLine 3줄째의 모델별 비용/캐시 히트율이 L5 정확값으로 표시됩니다 (이전과 수치가 다를 수 있음).

---

## 소비 이벤트 참조

| 이벤트 | attributes | forge-glow 용도 |
|--------|-----------|-----------------|
| `claude_code.api_request` | `model`, `duration_ms`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cost_usd` | 모델별 비용 + 캐시 히트율 |
| `claude_code.tool_result` | `tool_name`, `duration_ms`, `success` | 도구 성공률 (L5 전용) |

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `otel.log`에 이벤트 0개 | `CLAUDE_CODE_ENABLE_TELEMETRY` 미설정 | shell 재시작 후 `echo $CLAUDE_CODE_ENABLE_TELEMETRY` 확인 |
| statusLine이 L2 값 그대로 | `FORGE_GLOW_OTEL_LOG` 경로 불일치 | `ls $FORGE_GLOW_OTEL_LOG` 존재 확인 |
| collector 실행 실패 | 포트 4317/4318 점유 | `lsof -i :4317` 확인 후 다른 포트 사용 |

---

## 공식 문서

- [Claude Code Monitoring / OTel](https://code.claude.com/docs/en/monitoring-usage)
- [OpenTelemetry Collector file exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/fileexporter)
