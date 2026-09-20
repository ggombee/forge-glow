# Claude OTel 모델별 추정값 보강

forge-glow는 Claude Code의 OTel **logs/events** 신호에서 `claude_code.api_request`를
읽어 현재 `session.id`의 모델별 비용·캐시 정보를 보강할 수 있습니다.

`cost_usd`는 Claude가 생성한 **추정값**입니다. API provider의 청구 확정값이
아니며 Pro/Max 구독자의 실제 결제액을 의미하지도 않습니다.

OTel이 없으면 현재 transcript를 `message.id`로 중복 제거한 근사값을 사용하므로
이 설정은 선택사항입니다.

## 1. Collector 설정

macOS 예시:

```bash
brew install opentelemetry-collector-contrib
mkdir -p ~/.forge-glow
```

`~/.forge-glow/otel-config.yaml`:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317
      http:
        endpoint: 127.0.0.1:4318

exporters:
  file/claude_events:
    path: /Users/YOUR_USER/.forge-glow/otel.log
    format: json
    rotation:
      max_megabytes: 10
      max_days: 3
      max_backups: 3

service:
  pipelines:
    logs:
      receivers: [otlp]
      exporters: [file/claude_events]
```

HUD가 사용하는 `api_request`는 metrics나 traces가 아닌
**logs/events protocol**입니다. 따라서 `logs` pipeline이 반드시 있어야 합니다.

실행:

```bash
otelcol-contrib --config ~/.forge-glow/otel-config.yaml
```

## 2. Claude Code 환경변수

`~/.zshrc`, `~/.bashrc` 또는 Claude managed settings에 넣습니다.

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4317
export OTEL_METRICS_INCLUDE_SESSION_ID=1
```

`OTEL_METRICS_INCLUDE_SESSION_ID`의 기본값은 `true`이지만, 세션 격리가 이 연동의
필수 조건임을 명시하기 위해 표시했습니다. 설정 후 Claude Code를 재시작하세요.

metrics나 traces도 필요하면 별도 exporter/pipeline을 추가하세요. forge-glow HUD만
위해서는 `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`가 필요하지 않습니다.

## 3. 형식과 세션 격리

Collector file exporter는 각 줄에 단일 event가 아닌 OTLP/JSON batch envelope를
저장합니다.

```text
resourceLogs[] → scopeLogs[] → logRecords[]
```

forge-glow는 이 표준 envelope의 resource/log-record attributes를 합친 뒤
`session.id == statusLine stdin.session_id`인 event만 집계합니다. statusLine에
`session_id`가 없거나 event에 같은 ID가 없으면 전역 로그를 추측하지 않고
transcript 값으로 fallback합니다.

예전 forge-glow flat JSON (`{"name": ..., "attributes": ...}`)도 호환성을 위해
읽을 수 있습니다.

## 4. 검증

Claude Code를 몇 턴 사용한 뒤:

```bash
ls -lh ~/.forge-glow/otel.log
tail -1 ~/.forge-glow/otel.log | jq '.resourceLogs | length'
tail -1 ~/.forge-glow/otel.log \
  | jq -r '.resourceLogs[]?.scopeLogs[]?.logRecords[]?.body.stringValue'
```

`claude_code.api_request`가 보이면 다음 Claude status line 갱신부터 모델별
추정값을 사용합니다. 다른 경로를 쓰면:

```bash
export FORGE_GLOW_OTEL_LOG=/path/to/otel.log
```

## 보안

Claude OTel 표준 attributes에는 세션 ID 외에도 사용자/조직 식별자가 들어갈 수
있습니다. `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`,
`OTEL_LOG_RAW_API_BODIES`는 HUD에 필요하지 않으므로 켜지 마세요. 로그 디렉터리는
로컬 계정만 읽도록 권한을 제한하는 것이 좋습니다.

## 공식 문서

- [Claude Code Monitoring](https://code.claude.com/docs/en/monitoring-usage)
- [OpenTelemetry Collector file exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/fileexporter)
