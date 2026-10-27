# AI 사용량 통합 모니터 (Claude · Gemini · AGY)

**Claude · Gemini CLI · AGY(Antigravity)** 3개 AI 서비스의 사용량을 하나의 Windows 트레이 아이콘과 바탕화면 위젯으로 통합해 보여주는 유틸리티입니다.
트레이 아이콘에 3단 게이지 심볼과 전체 최고 경고 등급 색상이 표시되며, 우클릭 메뉴에서 원하는 서비스를 개별적으로 숨길 수도 있습니다.

> 상세한 배경지식, 서비스별 API·로그 구조, 유지보수 가이드는 [ARCHITECTURE.md](ARCHITECTURE.md)를 참고하세요.

## 서비스별 동작 방식

1. **Claude (`현재 세션 (5시간)` / `주간 전체 (7일)`)**
   - Claude Code CLI가 로그인할 때 저장한 OAuth 토큰(`%USERPROFILE%\.claude\.credentials.json`, 또는 `$env:CLAUDE_CONFIG_DIR`)을 **읽기만** 해서 `GET https://api.anthropic.com/api/oauth/usage`를 호출합니다.
   - Claude Code의 자체 갱신과 부딪혀 로그아웃되는 것을 막기 위해 `.credentials.json` 파일에 직접 쓰지 않습니다.
2. **Gemini (`Pro (24시간)` / `Flash (24시간)`)**
   - Gemini CLI가 로그인할 때 저장한 OAuth 자격증명(`%USERPROFILE%\.gemini\oauth_creds.json`)을 읽어 `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`를 호출합니다.
   - 액세스 토큰이 만료된 경우 원본 파일을 건드리지 않고 메모리 상에서 `refresh_token`으로 새 액세스 토큰을 발급받아 조회합니다.
   - 구글 서버 정책에 따라 **Pro 계열 일일 한도(%)**와 **Flash 계열 일일 한도(%)** 및 리셋 시각을 표시합니다.
3. **AGY / Antigravity (`주간 (170M)`)**
   - `%USERPROFILE%\.gemini\antigravity\brain\*\transcript.jsonl` 로컬 로그에 기록된 서버 실측 토큰 수(`input_tokens + cache_read_tokens + output_tokens`)를 파일 수정 시각·크기 기준으로 증분 캐싱하여 합산합니다.
   - 주간 누적 사용 토큰 수(`예: 주간 (3.7M / 170M)`), 사용률(`%`), 그리고 **다음 주간 초기화까지 남은 시간 및 만료 일시(`예: 5일 11시간 후 (11/2 00:00 초기화)`)**를 표시합니다.

## 요구 사항

| 항목 | 비고 |
|---|---|
| Windows 10 · 11 | Windows PowerShell 5.1, .NET Framework 기본 포함 |
| Claude Code 로그인 | `%USERPROFILE%\.claude\.credentials.json` |
| Gemini CLI 로그인 | `%USERPROFILE%\.gemini\oauth_creds.json` |
| Antigravity 사용 이력 | `%USERPROFILE%\.gemini\antigravity\brain\*\transcript.jsonl` |

## 설치·실행

1. 저장소를 받거나 ZIP을 원하는 폴더에 풉니다. `lib` 폴더가 함께 있어야 합니다.
   ZIP으로 받았다면 압축을 풀기 전에 **우클릭 → 속성 → 차단 해제**에 체크합니다.
2. `start.vbs`를 실행합니다. 콘솔 창 없이 트레이에 아이콘이 나타나면 정상입니다.
   `config.json`은 이때 자동으로 만들어집니다.
3. 트레이 우클릭 → **로그온 시 자동 시작**을 켭니다. 폴더를 옮기면 다시 켜야 합니다.

WSH(`.vbs`)가 막힌 PC라면 아래 명령으로 바로가기를 만들어 대신 씁니다.

```
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "설치경로\ClaudeUsageMonitor.ps1"
```

## 사용법

- **트레이 아이콘**: 3단 수평 게이지 심볼과 전체 최고 경고 등급 색상. 마우스를 올리면 표시 중인 서비스 요약 툴팁이 표시됩니다.
- **통합 위젯**: 트레이 아이콘 **좌클릭** 또는 `Ctrl+Alt+U`(기본값)로 열고 닫습니다. 드래그로 옮기면 위치가 저장됩니다.
- **우클릭 메뉴**:
  - `지금 갱신`
  - `Claude 토큰 갱신 시도` / `Claude 토큰 만료 시 자동 갱신`
  - `위젯 표시` / `보조 한도(주간·Flash) 상세 표시` / `단축키 설정`
  - `클로드 숨김` / `제미나이 숨김` / `AGY 숨김` (최소 1개 서비스는 반드시 표시 유지)
  - `로그온 시 자동 시작` / `종료`

자세한 조작법·설정 항목·문제 해결은 [ARCHITECTURE.md](ARCHITECTURE.md)에 있습니다.

## 설정 (`config.json`)

대부분 우클릭 메뉴로 바뀌므로 직접 열 일은 드뭅니다. 직접 고칠 때는 프로그램을 종료한 뒤 편집하세요.
값이 비정상이면 실행할 때 기본값으로 되돌립니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `pollActiveSeconds` | 300 | 사용 중 갱신 간격(초). 줄이면 요청 제한에 걸리기 쉽습니다 |
| `pollIdleSeconds` | 900 | 유휴 시 갱신 간격(초) |
| `idleAfterSeconds` | 300 | 이만큼 입력이 없으면 유휴로 간주 |
| `thresholds` | `[50, 70, 90, 95]` | 색 등급 기준(%) |
| `hideClaude` | false | 클로드 모니터링 및 위젯 섹션 숨김 |
| `hideGemini` | false | 제미나이 모니터링 및 위젯 섹션 숨김 |
| `hideAgy` | false | AGY 모니터링 및 위젯 섹션 숨김 |
| `agyWeeklyLimitMillion` | 170 | AGY 주간 토큰 한도 (단위: 백만 토큰, 기본 170M) |
| `agyResetDay` | 1 | AGY 주간 초기화 요일 (`0`=일, `1`=월[기본], ..., `6`=토, `-1`=7일 롤링) |
| `agyResetHour` | 0 | AGY 주간 초기화 시각 (`0~23`시, 기본 `0`시 자정) |
| `hotkey` | `Ctrl+Alt+U` | 위젯 토글 단축키 |
| `showWeekly` | true | 위젯에 보조 한도(Claude 주간 · Gemini Flash) 게이지 함께 표시 |
| `autoRefreshToken` | false | Claude 토큰 만료 시 `claude`를 자동 실행해 갱신 |
| `refreshCooldownMinutes` | 60 | 자동 갱신 최소 간격(분, 최소 10) |
| `widgetVisible` | false | 시작 시 위젯 표시 |
| `widgetX` · `widgetY` | null | 위젯 위치 |

## 폴더 구조

```
ClaudeUsageMonitor.ps1   진입점 (모듈 로드·시작·종료·메시지 루프)
start.vbs                콘솔 창 없이 실행하는 런처
ARCHITECTURE.md          배경지식·서비스별 명세·유지보수 상세 설계서 (AI/개발자용)
MODULES.md               어떤 변경을 어느 파일에서 하는지 정리한 모듈 지도
lib/                     기능별 모듈 (API·파싱·트레이·위젯·단축키·메뉴 등)
tools/                   유지보수 스크립트
```

## 개발 및 유지보수 시 주의

- **`.ps1` 파일은 반드시 UTF-8 BOM으로 저장해야 합니다.** 한글이 들어 있어 BOM이 없으면 PowerShell 5.1이 파싱에 실패합니다.
- 수정할 파일은 [MODULES.md](MODULES.md)의 표에서 고르고, 상세 동작 원리는 [ARCHITECTURE.md](ARCHITECTURE.md)를 참고하세요.

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1   # BOM 재부착 + 구문 검사
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Restart.ps1        # 실행 중인 모니터 재시작
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Zip.ps1      # dist\ClaudeUsageMonitor.zip 생성
```
