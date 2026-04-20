# Homebrew Formula

이 디렉터리의 `forge-glow.rb`는 **Homebrew Formula**입니다.

## 빠른 설치 (tap 경유)

```bash
brew tap ggombee/forge-glow https://github.com/ggombee/forge-glow.git
brew install forge-glow
```

또는 별도 tap 레포(`ggombee/homebrew-tap`)를 만들어 거기 복사하면:

```bash
brew tap ggombee/tap
brew install forge-glow
```

## head 버전 (최신 main)

```bash
brew install --head forge-glow
```

## 배포 체크리스트

1. `git tag -a v0.5.0 -m "..."` + push tag
2. GitHub Release 자동 생성 (release.yml 워크플로우)
3. `.tar.gz` 자산의 sha256 계산:
   ```bash
   curl -L https://github.com/ggombee/forge-glow/archive/refs/tags/v0.5.0.tar.gz | shasum -a 256
   ```
4. `Formula/forge-glow.rb`의 `sha256 "REPLACE_WITH_RELEASE_SHA256"`을 실제 값으로 교체 후 커밋
5. `brew audit --strict forge-glow` 통과 확인 (로컬)

## 구성

- 쉘 스크립트 본체(statusLine + self-update)는 이 Formula로 설치
- Python stats 대시보드는 **PyPI(`pip install forge-glow-stats`)** 권장
  - 이유: Python 패키징 관례 + 가상환경 친화
  - Homebrew에 Python 의존성 넣는 건 다른 사용자 환경과 충돌 위험
