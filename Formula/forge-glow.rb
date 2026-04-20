class ForgeGlow < Formula
  desc "Real-time efficiency HUD for Claude Code + Codex CLI"
  homepage "https://github.com/ggombee/forge-glow"
  url "https://github.com/ggombee/forge-glow/archive/refs/tags/v0.5.0.tar.gz"
  # sha256 — release 생성 시 `shasum -a 256 *.tar.gz`로 계산해 교체
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  license "MIT"
  head "https://github.com/ggombee/forge-glow.git", branch: "main"

  depends_on "jq"

  def install
    # 쉘 스크립트 본체
    libexec.install "hud", "tmux", "tools", "install.sh", "uninstall.sh"

    # stats(Python) 설치는 PyPI 경유가 권장이지만 편의 제공
    libexec.install "stats" if File.directory?("stats")

    # wrapper 바이너리 — statusLine / 업데이트 / 상태 제어 진입점
    (bin/"forge-glow").write <<~SH
      #!/usr/bin/env bash
      # Homebrew 설치본 wrapper
      LIBEXEC="#{libexec}"
      case "${1:-help}" in
        install)    shift; exec bash "$LIBEXEC/install.sh" "$@" ;;
        uninstall)  shift; exec bash "$LIBEXEC/uninstall.sh" "$@" ;;
        update)     shift; FORGE_GLOW_DIR="$LIBEXEC" exec bash "$LIBEXEC/tools/self-update.sh" "$@" ;;
        statusline) shift; exec bash "$LIBEXEC/hud/statusline.sh" "$@" ;;
        stats)      shift; exec python3 -m forge_glow_stats "$@" ;;
        help|--help|-h|"")
          cat <<HELP
      forge-glow — Claude Code + Codex CLI efficiency HUD

      USAGE:
        forge-glow install         statusLine + 자동 갱신 스케줄러 등록
        forge-glow uninstall       제거
        forge-glow update          수동 업데이트 (self-update.sh 1회)
        forge-glow statusline      statusLine 단독 실행 (디버깅)
        forge-glow stats           Python rich 대시보드 (pip install forge-glow-stats 권장)

      Files:
        statusLine: $LIBEXEC/hud/statusline.sh
        self-update: $LIBEXEC/tools/self-update.sh
      HELP
          ;;
        *)
          echo "unknown command: $1" >&2
          exit 1
          ;;
      esac
    SH
    chmod 0755, bin/"forge-glow"
  end

  def post_install
    ohai "forge-glow 설치 완료."
    ohai "다음 단계:"
    ohai "  1) forge-glow install       # statusLine 등록 (래핑 모드 선택 가능)"
    ohai "  2) pip install forge-glow-stats  # (선택) Python 대시보드"
    ohai "  3) OTel L5 활성화: #{libexec}/hud 아래 docs/otel-setup.md 참조"
  end

  test do
    system bin/"forge-glow", "help"
    assert_predicate libexec/"hud/statusline.sh", :exist?
    assert_predicate libexec/"tools/self-update.sh", :exist?
  end
end
