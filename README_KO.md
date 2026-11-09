# Claude Usage Monitor

[English](README.md)

<img width="376" height="328" alt="image" src="https://github.com/user-attachments/assets/eaa3dc93-b4a1-496d-a7dc-f7e5909d716e" />

Claude (claude.ai) 사용량을 실시간으로 보여주는 가벼운 macOS 메뉴바 앱입니다.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## 설치

### Step 1. 다운로드

**Homebrew (권장)**

```bash
brew tap Dann1y/tap
brew install --cask claude-usage-monitor
```

**또는 수동 설치**

```bash
git clone https://github.com/Dann1y/claude-usage-monitor.git
cd claude-usage-monitor
make install
```

### Step 2. 앱 실행 허용

이 앱은 Apple 공증(notarize)을 받지 않았기 때문에 첫 실행 시 macOS가 차단합니다. 아래 명령어를 한 번 실행해주세요:

```bash
xattr -cr "/Applications/Claude Usage Monitor.app"
```

앱을 열면 메뉴바에 표시됩니다. 설정에서 **로그인 시 실행**을 활성화하면 항상 실행 상태를 유지할 수 있습니다.

## 업데이트

앱이 24시간마다 자동으로 새 버전을 확인하고, 업데이트가 있으면 알림 배지를 표시합니다.

**Homebrew**

```bash
brew upgrade --cask claude-usage-monitor
```

> `brew upgrade`가 새 버전을 감지하지 못하면, 아래 명령어를 한 번 실행해주세요:
> ```bash
> git -C "$(brew --repository dann1y/tap)" config homebrew.forceautoupdate true
> ```

**또는 수동 업데이트**

```bash
cd claude-usage-monitor
git pull
make install
```

## 삭제

```bash
brew uninstall claude-usage-monitor
# 또는
make uninstall
```

## 작동 방식

1. macOS 키체인에서 Claude Code OAuth 토큰을 가져옵니다 (`Claude Code-credentials`) — 사용량은 서버에서 계정 단위로 합산되므로 터미널 CLI / Claude Desktop 앱 / 웹에서 쓴 사용량이 모두 반영됩니다
2. 팝오버를 열 때 Anthropic API에서 사용량 데이터를 온디맨드로 가져오며, 백그라운드에서 30분마다 자동 갱신합니다
3. **OAuth 토큰이 만료되면 저장된 refresh token으로 자동 재발급**합니다 — 터미널에서 `claude`를 계속 실행해 둘 필요가 없습니다. 키체인 항목은 원자적으로(`security add-generic-password -U`) 업데이트하므로 CLI 로그아웃 문제가 발생하지 않습니다
4. 사용량 데이터를 로컬에 캐시하여 API를 사용할 수 없을 때도 앱이 정상적으로 작동합니다

**API 키나 수동 설정이 필요 없습니다!** — Claude Code CLI가 자동으로 저장하는 동일한 자격 증명을 사용합니다.

## 기능

- 메뉴바에 주간 사용량 퍼센트 및 색상 아이콘 표시 (초록 / 주황 / 빨강) — Claude는 이제 5시간 창이 아니라 일주일 단위로 사용량을 계산합니다
- 페이스 표시: 주간 막대 위의 눈금이 이번 주가 얼마나 지났는지 보여 줘서, 주간 한도보다 빨리 쓰고 있는지 한눈에 알 수 있고 남은 기간의 하루 예산도 알려 줍니다
- 모델별 주간 한도 (예: Fable) — API의 `limits` 목록을 읽으므로 새 모델 한도가 생겨도 앱 업데이트 없이 표시됩니다
- "이번 주 앱별 사용" 분포 (Claude Code / Chats / Cowork)
- 추가 사용량(Extra usage) 결제액 표시, 요금제에 5시간 창이 남아 있으면 함께 표시
- 팝오버 열 때 온디맨드 새로고침 (30초 쿨다운)
- 30분 간격 백그라운드 폴링으로 최신 상태 유지
- OAuth 토큰 자동 갱신 — Claude Desktop만 쓰고 터미널을 열지 않아도 동작합니다
- 앱 재시작 시에도 유지되는 로컬 디스크 캐시
- 로그인 시 자동 실행 지원
- GitHub Releases를 통한 자동 업데이트 알림 (24시간마다 확인)

## 요구 사항

- macOS 14.0 (Sonoma) 이상
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — macOS 키체인에 OAuth 자격 증명을 저장하려면 `claude`를 최소 한 번 실행해야 합니다

## 라이선스

MIT
