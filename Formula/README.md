# Homebrew Formula

이 디렉터리의 `forge-glow.rb`는 **Homebrew Formula**입니다.

## 현재 개발본 설치

v0.9.0 release tarball의 SHA를 Formula에 반영하기 전에는 stable 설치를 안내하지
않습니다. 저장소의 최신 개발본은 다음처럼 설치합니다.

```bash
brew tap ggombee/forge-glow https://github.com/ggombee/forge-glow.git
brew install --head forge-glow
```

## 릴리즈 후 stable 설치

```bash
brew tap ggombee/forge-glow https://github.com/ggombee/forge-glow.git
brew install forge-glow
```

또는 별도 tap 레포(`ggombee/homebrew-tap`)를 만들어 거기 복사하면:

```bash
brew tap ggombee/tap
brew install forge-glow
```

## 배포 체크리스트

1. `bash tools/check-release.sh`로 Claude/Codex/Python/Formula 버전 동기화 확인
2. `git tag -a v0.9.0 -m "..."` + push tag
3. GitHub Release 자동 생성 (release.yml 워크플로우)
4. `.tar.gz` 자산의 sha256 계산:
   ```bash
   curl -L https://github.com/ggombee/forge-glow/archive/refs/tags/v0.9.0.tar.gz | shasum -a 256
   ```
5. `Formula/forge-glow.rb`의 `sha256 "REPLACE_WITH_RELEASE_SHA256"`을 실제 값으로 교체 후 커밋
6. `brew audit --strict forge-glow` 통과 확인 (로컬)

## 구성

- 쉘 스크립트 본체(statusLine)는 이 Formula로 설치하며 업데이트는 `brew upgrade`가 담당
- Python stats 대시보드는 **PyPI(`pip install forge-glow-stats`)** 권장
  - 이유: Python 패키징 관례 + 가상환경 친화
  - Homebrew에 Python 의존성 넣는 건 다른 사용자 환경과 충돌 위험
