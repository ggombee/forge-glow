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
#   claude plugin marketplace add ggombee/forge-glow
#   claude plugin install forge-glow@forge-glow

set -e

REPO="${FORGE_GLOW_REPO:-ggombee/forge-glow}"
REF="${FORGE_GLOW_REF:-main}"
PREFIX="${FORGE_GLOW_PREFIX:-$HOME/.local/share/forge-glow}"
FORCE="${FORGE_GLOW_FORCE:-}"
PREFIX="${PREFIX%/}"
BACKUP=""

say() { printf '  %s\n' "$1"; }
die() { printf '❌ %s\n' "$1" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl 필요."
command -v tar >/dev/null 2>&1 || die "tar 필요."
command -v jq >/dev/null 2>&1 || die "jq 필요. brew install jq"

case "$PREFIX" in
  /*/forge-glow) ;;
  *) die "FORGE_GLOW_PREFIX는 절대 경로이고 forge-glow로 끝나야 합니다: $PREFIX" ;;
esac

if [ -e "$PREFIX" ] || [ -L "$PREFIX" ]; then
  if [ "$FORCE" != "1" ]; then
    if [ -t 0 ]; then
      read -r -p "  기존 설치 발견: $PREFIX — 백업 후 교체할까요? [y/N] " ans
      case "$ans" in y|Y|yes) ;; *) die "취소됨." ;; esac
    else
      die "기존 설치가 있습니다. 교체하려면 FORGE_GLOW_FORCE=1을 지정하세요: $PREFIX"
    fi
  fi
  BACKUP="${PREFIX}.backup.$(date +%Y%m%d%H%M%S).$$"
  mv "$PREFIX" "$BACKUP" || die "기존 설치 백업 실패: $BACKUP"
  say "📦 기존 설치 백업: $BACKUP"
fi

TARBALL="https://codeload.github.com/${REPO}/tar.gz/${REF}"
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
                            PYTHONPATH=$PREFIX/stats/src python3 -m forge_glow_stats
   - Workflow 패널: ~/.forge-glow/workflow.json 작성 후 자동 활성
   - tmux: $PREFIX/docs/tmux-setup.md
   - 업데이트: 같은 curl 설치 명령을 FORGE_GLOW_FORCE=1로 다시 실행
   - 플러그인 배포본: bash $PREFIX/tools/plugin-manager.sh install all
EOF

[ -n "$BACKUP" ] && say "이전 설치는 필요 없을 때 직접 삭제하세요: $BACKUP"
