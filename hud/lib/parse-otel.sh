#!/usr/bin/env bash
# forge-glow — parse-otel.sh
# Claude Code OTel logs/events를 현재 session.id로 격리해 보강한다.
# shellcheck disable=SC2034  # G_OTEL_* 변수는 statusline.sh가 sourcing 후 사용
#
# OTel Collector file exporter의 표준 OTLP/JSON envelope(resourceLogs/scopeLogs/logRecords)와
# 구버전 forge-glow의 flat JSON 형식을 모두 읽는다. cost_usd는 Claude가 생성한
# 추정값이며 청구 확정값이 아니다.

parse_otel() {
  local session_id="${1:-}"

  G_OTEL_AVAILABLE=false
  G_OTEL_MODEL_COSTS=""
  G_OTEL_CACHE_HIT_PCT=""

  # session_id가 없으면 전역 이벤트를 현재 세션으로 추측하지 않는다.
  [ -z "$session_id" ] && return

  local log_file="${FORGE_GLOW_OTEL_LOG:-$HOME/.forge-glow/otel.log}"
  [ ! -f "$log_file" ] && return
  command -v jq >/dev/null 2>&1 || return

  local parsed
  parsed=$(tail -500 "$log_file" 2>/dev/null | jq -rs --arg sid "$session_id" '
    def otel_value:
      if type != "object" then .
      elif has("stringValue") then .stringValue
      elif has("intValue") then (.intValue | tonumber? // .)
      elif has("doubleValue") then .doubleValue
      elif has("boolValue") then .boolValue
      else .
      end;

    def attr_map($items):
      reduce (($items // [])[]) as $item ({}; .[$item.key] = ($item.value | otel_value));

    def events:
      .[]
      | if ((.resourceLogs? // null) | type) == "array" then
          .resourceLogs[]? as $resource_log
          | attr_map($resource_log.resource.attributes) as $resource_attrs
          | ($resource_log.scopeLogs // $resource_log.instrumentationLibraryLogs // [])[]?
          | (.logRecords // .logs // [])[]?
          | {
              name: (.body.stringValue // .name // ""),
              attributes: ($resource_attrs + attr_map(.attributes))
            }
        elif .name? then
          {name: .name, attributes: (.attributes // {})}
        else empty
        end;

    def number($value): ($value | tonumber? // 0);
    def short_model($m):
      ($m | ascii_downcase) as $n
      | if ($n | contains("fable")) then "fable"
        elif ($n | contains("mythos")) then "mythos"
        elif ($n | contains("opus")) then "opus"
        elif ($n | contains("sonnet")) then "sonnet"
        elif ($n | contains("haiku")) then "haiku"
        else "unknown"
        end;
    def money:
      (. * 100 + 0.5 | floor) as $c
      | (($c / 100 | floor | tostring) + "." +
         (($c % 100 | floor | tostring) | if length == 1 then "0" + . else . end));

    [events | select((.attributes["session.id"] // .attributes.session_id // "") == $sid)] as $events
    | [
        $events[]
        | select(.name == "claude_code.api_request")
          | {
            model: (.attributes.model // "unknown"),
            input: number(.attributes.input_tokens),
            cache_read: number(.attributes.cache_read_tokens),
            cache_create: number(.attributes.cache_creation_tokens),
            cost: number(.attributes.cost_usd)
          }
      ] as $api
    | [
        "AVAILABLE\t\(($api | length) > 0)",
        "CACHE\t\(if ($api | map(.input + .cache_read + .cache_create) | add // 0) > 0
                    then (($api | map(.cache_read) | add // 0) /
                          ($api | map(.input + .cache_read + .cache_create) | add) * 100 | round)
                    else 0 end)",
        ($api
          | group_by(short_model(.model))
          | map({name: short_model(.[0].model), cost: (map(.cost) | add)})
          | map(select(.cost > 0.001))
          | sort_by(-.cost)
          | .[]
          | "MODEL\t\(.name)\t\(.cost | money)")
      ]
    | .[]
  ' 2>/dev/null)

  [ -z "$parsed" ] && return

  local kind value amount
  while IFS=$'\t' read -r kind value amount; do
    case "$kind" in
      AVAILABLE) G_OTEL_AVAILABLE="$value" ;;
      CACHE) G_OTEL_CACHE_HIT_PCT="$value" ;;
      MODEL) G_OTEL_MODEL_COSTS+="${value}:\$${amount} " ;;
    esac
  done <<< "$parsed"
}
