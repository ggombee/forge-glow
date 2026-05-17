#!/usr/bin/env bash
# forge-glow one-line installer (curl | bash 진입점).
#
# 한 줄 설치:
#   curl -fsSL https://raw.githubusercontent.com/ggombee/forge-glow/main/tools/curl-install.sh | bash
#
# 동작:
#   1. 임시 dir에 git clone (또는 tarball)
#   2. 영구 위치(~/.local/share/forge-glow)로 복사
#   3. ./install.sh 실행 (settings.json statusLine 등록)
#
# 환경 변수:
#   FORGE_GLOW_REPO     — github repo (기본: ggombee/forge-glow)
#   FORGE_GLOW_REF      — branch/tag (기본: main)
#   FORGE_GLOW_PREFIX   — 설치 위치 (기본: ~/.local/share/forge-glow)
#   FORGE_GLOW_FORCE    — "1" 이면 기존 설치 덮어쓰기
#
# 권장: Claude Code 사용자라면 마켓플레이스가 더 간단함:
#   claude plugin marketplace add https://github.com/ggombee/forge-market.git
#   claude plugin install forge-glow

set -e

REPO="${FORGE_GLOW_REPO:-ggombee/forge-glow}"
REF="${FORGE_GLOW_REF:-main}"
PREFIX="${FORGE_GLOW_PREFIX:-$HOME/.local/share/forge-glow}"
FORCE="${FORGE_GLOW_FORCE:-}"

say() { printf '  %s\n' "$1"; }
die() { printf '❌ %s\n' "$1" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl 필요."
command -v tar >/dev/null 2>&1 || die "tar 필요."
command -v jq >/dev/null 2>&1 || die "jq 필요. brew install jq"

if [ -d "$PREFIX" ]; then
  if [ -z "$FORCE" ] && [ -t 0 ]; then
    read -r -p "  기존 설치 발견: $PREFIX — 덮어쓸까요? [y/N] " ans
    case "$ans" in y|Y|yes) ;; *) die "취소됨." ;; esac
  fi
  rm -rf "$PREFIX"
fi

TARBALL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${REF}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "📥 다운로드: $TARBALL"
curl -fsSL "$TARBALL" -o "$TMP/src.tar.gz" || die "다운로드 실패. repo/ref 확인: $REPO@$REF"

mkdir -p "$PREFIX"
tar -xzf "$TMP/src.tar.gz" -C "$TMP"
SRC_DIR="$(find "$TMP" -maxdepth 1 -type d -name "${REPO##*/}-*" | head -1)"
[ -n "$SRC_DIR" ] || die "tarball 구조 예상과 다름"
cp -R "$SRC_DIR"/. "$PREFIX/"

say "🔧 install.sh 실행 (statusLine 등록)"
cd "$PREFIX"
bash ./install.sh

cat <<EOF

✅ forge-glow 설치 완료
   위치: $PREFIX

📋 다음 단계
   - Python 대시보드(선택): pip install rich requests
                            python3 -m forge_glow_stats
   - Workflow 패널: ~/.forge-glow/workflow.json 작성 후 자동 활성
   - tmux: $PREFIX/docs/tmux-setup.md
   - 업데이트: bash $PREFIX/tools/self-update.sh
EOF
