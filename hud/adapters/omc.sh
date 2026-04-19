#!/usr/bin/env bash
# forge-glow adapter — oh-my-claudecode (OMC)
# https://github.com/oh-my-claudecode/oh-my-claudecode
#
# 감지: ~/.claude/omc/ 디렉터리 존재
# 출력: OMC 버전 + 활성 프리셋 (statusLine 3줄째에 append)
#
# 어댑터 규약:
#   - 단일 1줄 문자열을 stdout으로 출력 (비어있으면 무시)
#   - 실패 시 조용히 종료 (exit 0)
#   - 10ms 이내 완료 권장
#   - 의존성 최소화 (jq만 허용)

OMC_DIR="$HOME/.claude/omc"

# 감지 실패 시 조용히 종료
[ ! -d "$OMC_DIR" ] && exit 0

# 버전 읽기 (있으면)
VERSION=""
if [ -f "$OMC_DIR/VERSION" ]; then
  VERSION=$(head -1 "$OMC_DIR/VERSION" 2>/dev/null | tr -d ' \n')
fi

# 활성 프리셋 (preset.conf의 active= 라인)
PRESET=""
if [ -f "$OMC_DIR/preset.conf" ]; then
  PRESET=$(grep -E '^active=' "$OMC_DIR/preset.conf" 2>/dev/null | head -1 | sed 's/^active=//' | tr -d ' "')
fi

# 출력 조립
OUT="🎭 OMC"
[ -n "$VERSION" ] && OUT="${OUT} v${VERSION}"
[ -n "$PRESET" ] && OUT="${OUT}:${PRESET}"

echo "$OUT"
