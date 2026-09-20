# 플러그인 배포와 업데이트

forge-glow는 한 저장소에서 Claude Code와 Codex용 배포 메타데이터를 함께
관리하지만, 각 제품의 공식 플러그인 관리자를 그대로 사용합니다. 사용자 설치본은
개발용 clone의 `git pull`에 의존하지 않습니다.

## 배포 경로

| 제품 | 카탈로그 | 설치 단위 | 업데이트 적용 |
|---|---|---|---|
| Claude Code | `.claude-plugin/marketplace.json` | 저장소 루트의 Claude plugin | auto-update 또는 `claude plugin update`, 이후 `/reload-plugins`/재시작 |
| Codex | `.agents/plugins/marketplace.json` | `plugins/forge-glow` | marketplace upgrade + plugin add, 이후 새 세션 |
| 개발용 clone | Git upstream | 저장소 전체 | clean tree에서만 `tools/self-update.sh`가 ff-only 갱신 |
| Homebrew/PyPI | release tag | Formula/Python package | 각 패키지 관리자 |

Claude와 Codex plugin manifest의 버전은 항상 같아야 합니다. Claude는 manifest의
명시적 버전을 cache key로 사용하므로 코드만 push하고 버전을 올리지 않으면 기존
설치본이 새 버전으로 판단하지 않습니다. Codex도 설치 cache를 확실히 교체할 수 있게
같은 버전을 올립니다.

## 릴리스 절차

1. `.claude-plugin/plugin.json`,
   `plugins/forge-glow/.codex-plugin/plugin.json`, `stats/pyproject.toml`,
   `stats/src/forge_glow_stats/__init__.py`, Homebrew Formula URL의 버전을 함께 올립니다.
2. `bash tools/check-release.sh`와 전체 CI를 통과시킵니다.
3. `vX.Y.Z` tag를 push합니다. release workflow는 tag와 manifest 버전이 다르면
   중단하고, 같으면 GitHub release와 선택적 PyPI 배포를 진행합니다.
4. `main`을 추적하는 Claude/Codex marketplace는 새 snapshot을 가져올 수 있습니다.
   이미 열린 프로세스는 plugin 코드를 hot-swap하지 않으므로 reload 또는 새 세션이
   필요합니다.

## 사용자 명령

### Claude Code

```bash
claude plugin marketplace add ggombee/forge-glow
claude plugin install forge-glow@forge-glow
```

서드파티 marketplace의 auto-update는 사용자가 `/plugin` UI에서 켭니다. 수동 갱신은:

```bash
claude plugin marketplace update forge-glow
claude plugin update forge-glow@forge-glow
```

### Codex

```bash
codex plugin marketplace add ggombee/forge-glow --ref main
codex plugin add forge-glow@forge-glow
```

수동 갱신은:

```bash
codex plugin marketplace upgrade forge-glow
codex plugin add forge-glow@forge-glow
```

Codex의 marketplace upgrade는 카탈로그 snapshot을 갱신하고, 두 번째 명령이 설치
cache를 새 snapshot으로 교체합니다. 변경된 skill은 새 Codex 세션부터 로드됩니다.

공식 참고 문서: [OpenAI plugin build and distribution](https://developers.openai.com/plugins/build/plugins),
[Claude Code plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces),
[Claude Code plugin discovery and auto-update](https://code.claude.com/docs/en/discover-plugins)
