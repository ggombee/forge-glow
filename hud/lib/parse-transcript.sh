#!/usr/bin/env bash
# forge-glow — parse-transcript.sh
# 현재 Claude 세션 transcript.jsonl 보강 파서.
# shellcheck disable=SC2034  # G_* 변수는 statusline.sh가 sourcing 후 사용
#
# Claude Code는 하나의 assistant message를 thinking/tool/text 레코드로 여러 번
# 저장할 수 있다. message.id로 중복 제거하지 않으면 토큰과 비용이 과대
# 계산된다. 도구 호출은 top-level 이벤트가 아닌 message.content[].tool_use다.

parse_transcript() {
  local transcript="$1"

  G_TOOL_SUMMARY=""
  G_MODEL_COSTS=""
  G_CACHE_HIT_PCT=""

  [ -z "$transcript" ] || [ ! -f "$transcript" ] && return
  command -v jq >/dev/null 2>&1 || return

  local top_tools=5
  if [ "${G_COLUMNS:-0}" -gt 0 ] 2>/dev/null && [ "${G_COLUMNS:-0}" -lt 100 ] 2>/dev/null; then
    top_tools=3
  fi

  # tail/jq를 각각 반복하지 않고 한 번의 스냅샷으로 도구·비용·캐시를 모두 집계한다.
  local parsed
  parsed=$(tail -500 "$transcript" 2>/dev/null | jq -rs --argjson top "$top_tools" '
    def short_model($m):
      ($m | ascii_downcase) as $n
      | if ($n | contains("fable")) then "fable"
        elif ($n | contains("mythos")) then "mythos"
        elif ($n | test("opus[-_ ]4([._-]1)?($|[-_]20[0-9]{6})")) then "opus-4.1"
        elif ($n | contains("opus")) then "opus"
        elif ($n | test("haiku[-_ ]3[._-]5($|[-_]20[0-9]{6})")) then "haiku-3.5"
        elif ($n | test("sonnet[-_ ]5($|[-_])")) then "sonnet-5"
        elif ($n | contains("sonnet")) then "sonnet"
        elif ($n | contains("haiku")) then "haiku"
        else "unknown"
        end;

    # Claude API 가격표 fallback. 청구 확정값이 아니므로 HUD는 ~로 표시한다.
    def price($model):
      ($model | ascii_downcase) as $m
      | if ($m | test("fable|mythos")) then {i:10, o:50, cr:1}
        elif ($m | test("opus[-_ ]4([._-]1)?($|[-_]20[0-9]{6})")) then {i:15, o:75, cr:1.5}
        elif ($m | contains("opus")) then {i:5, o:25, cr:0.5}
        elif ($m | test("sonnet[-_ ]5($|[-_])")) then {i:2, o:10, cr:0.2}
        elif ($m | contains("sonnet")) then {i:3, o:15, cr:0.3}
        elif ($m | test("haiku[-_ ]3[._-]5($|[-_]20[0-9]{6})")) then {i:0.8, o:4, cr:0.08}
        elif ($m | contains("haiku")) then {i:1, o:5, cr:0.1}
        else null
        end;

    def money:
      (. * 100 + 0.5 | floor) as $c
      | (($c / 100 | floor | tostring) + "." +
         (($c % 100 | floor | tostring) | if length == 1 then "0" + . else . end));

    . as $events
    | [
        $events
        | to_entries[]
        | . as $entry
        | $entry.value
        | select(.type == "assistant" and (.message.usage? != null))
        | {
            id: (.message.id // .uuid // ("row:" + ($entry.key | tostring))),
            model: (.message.model // "unknown"),
            input: (.message.usage.input_tokens // 0),
            output: (.message.usage.output_tokens // 0),
            cache_read: (.message.usage.cache_read_input_tokens // 0),
            cache_5m: (.message.usage.cache_creation.ephemeral_5m_input_tokens // 0),
            cache_1h: (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0),
            cache_fallback: (.message.usage.cache_creation_input_tokens // 0)
          }
      ]
    | group_by(.id)
    | map(last)
    | map(.cache_5m = (if (.cache_5m + .cache_1h) == 0 then .cache_fallback else .cache_5m end))
    as $messages
    | [
        $events
        | to_entries[]
        | . as $event
        | (($event.value.message.content // []) | to_entries[])
        | . as $block
        | $block.value
        | select(.type == "tool_use")
        | {
            id: (.id // ("row:" + ($event.key | tostring) + ":" + ($block.key | tostring))),
            name: (.name // "unknown")
          }
      ]
    | unique_by(.id)
    | group_by(.name)
    | map({name: .[0].name, count: length})
    | sort_by([-.count, .name])
    | .[0:$top]
    | map("\(.name)×\(.count)")
    | join(" ")
    as $tools
    | [
        $messages[]
        | (price(.model)) as $p
        | select($p != null)
        | {
            name: short_model(.model),
            cost: (((.input * $p.i) + (.output * $p.o) + (.cache_read * $p.cr)
                    + (.cache_5m * $p.i * 1.25) + (.cache_1h * $p.i * 2)) / 1000000)
          }
      ]
    | group_by(.name)
    | map({name: .[0].name, cost: (map(.cost) | add)})
    | map(select(.cost > 0.001))
    | sort_by(-.cost)
    as $models
    | ($messages | map(.input + .cache_read + .cache_5m + .cache_1h) | add // 0) as $cache_total
    | ($messages | map(.cache_read) | add // 0) as $cache_read
    | [
        "TOOLS\t\($tools)",
        "CACHE\t\(if $cache_total > 0 then (($cache_read / $cache_total * 100) | round) else 0 end)",
        ($models[] | "MODEL\t\(.name)\t\(.cost | money)")
      ]
    | .[]
  ' 2>/dev/null)

  [ -z "$parsed" ] && return

  local kind value amount
  while IFS=$'\t' read -r kind value amount; do
    case "$kind" in
      TOOLS) G_TOOL_SUMMARY="$value" ;;
      CACHE) G_CACHE_HIT_PCT="$value" ;;
      MODEL) G_MODEL_COSTS+="${value}:\$${amount} " ;;
    esac
  done <<< "$parsed"
}
