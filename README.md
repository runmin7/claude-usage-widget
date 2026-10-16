# Claude 사용량 모니터

Claude 사용량(5시간 세션 한도 / 주간 한도)을 Windows 트레이 아이콘과 바탕화면 위젯으로 보여주는 유틸입니다.
트레이 아이콘에 세션 사용률 숫자가 그려지고, 색으로 등급을 나타내며, 임계치를 넘으면 알림을 띄웁니다.

> Anthropic의 공식 제품이 아닙니다. 문서화되지 않은 비공식 API에 의존하므로 예고 없이 동작하지 않을 수 있습니다.

## 동작 방식

- Claude Code CLI가 로그인할 때 저장한 OAuth 토큰(`%USERPROFILE%\.claude\.credentials.json`)을 **읽기만** 해서
  `GET https://api.anthropic.com/api/oauth/usage`를 호출합니다. 별도 로그인이나 API 키가 필요 없습니다.
- 토큰을 직접 갱신하거나 자격증명 파일에 쓰지 않습니다. Claude Code의 자체 갱신과 부딪혀 로그아웃되는 것을 막기 위해서입니다.
- 표시되는 값은 계정 전체 사용량입니다(데스크톱 앱·claude.ai·Claude Code 합산).
- `CLAUDE_CONFIG_DIR` 환경변수가 있으면 그 위치의 자격증명을 씁니다.

## 요구 사항

| 항목 | 비고 |
|---|---|
| Windows 10 · 11 | Windows PowerShell 5.1, .NET Framework 기본 포함 |
| Claude Code 설치 + 로그인 | 토큰을 여기서 가져옵니다 |
| Claude 구독 | Pro · Max · Team · Enterprise |

## 설치·실행

1. 저장소를 받거나 ZIP을 원하는 폴더에 풉니다. `lib` 폴더가 함께 있어야 합니다.
   ZIP으로 받았다면 압축을 풀기 전에 **우클릭 → 속성 → 차단 해제**에 체크합니다.
2. `start.vbs`를 실행합니다. 콘솔 창 없이 트레이에 아이콘이 나타나면 정상입니다.
   `config.json`은 이때 자동으로 만들어집니다.
3. 트레이 우클릭 → **로그온 시 자동 시작**을 켭니다. 폴더를 옮기면 다시 켜야 합니다.

WSH(.vbs)가 막힌 PC라면 아래 명령으로 바로가기를 만들어 대신 씁니다.

```
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "설치경로\ClaudeUsageMonitor.ps1"
```

## 사용법

- **트레이 아이콘**: 세션 사용률 숫자와 등급 색. 마우스를 올리면 상세 툴팁.
- **위젯**: `Ctrl+Alt+U`(기본값)로 열고 닫습니다. 드래그로 옮기면 위치가 저장됩니다.
- **우클릭 메뉴**: 지금 갱신, 토큰 갱신 시도, 위젯 표시, 주간 한도 표시, 임계치 알림, 단축키 설정, 사용 가이드, 로그온 시 자동 시작, 종료.

자세한 조작법·설정 항목·문제 해결은 [guide.html](guide.html)에 있습니다(트레이 메뉴에서도 열 수 있습니다).

## 설정 (`config.json`)

대부분 우클릭 메뉴로 바뀌므로 직접 열 일은 드뭅니다. 직접 고칠 때는 프로그램을 종료한 뒤 편집하세요.
값이 비정상이면 실행할 때 기본값으로 되돌립니다. PC마다 다른 값이라 git에는 올리지 않습니다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `pollActiveSeconds` | 300 | 사용 중 갱신 간격(초). 줄이면 요청 제한에 걸리기 쉽습니다 |
| `pollIdleSeconds` | 900 | 유휴 시 갱신 간격(초) |
| `idleAfterSeconds` | 300 | 이만큼 입력이 없으면 유휴로 간주 |
| `thresholds` | `[50, 70, 90, 95]` | 알림·색 등급 기준(%) |
| `hotkey` | `Ctrl+Alt+U` | 위젯 토글 단축키 |
| `notifyEnabled` | true | 임계치 알림 사용 |
| `showWeekly` | true | 위젯에 주간 한도 표시 |
| `autoRefreshToken` | false | 토큰 만료 시 `claude`를 자동 실행해 갱신 |
| `refreshCooldownMinutes` | 60 | 자동 갱신 최소 간격(분, 최소 10) |
| `widgetVisible` | false | 시작 시 위젯 표시 |
| `widgetX` · `widgetY` | null | 위젯 위치 |

## 자주 겪는 문제

| 증상 | 대처 |
|---|---|
| 토큰 만료 | 터미널에서 `claude`로 아무 작업이나 한 번 하면 다음 조회에서 복구됩니다. 데스크톱 앱 사용으로는 갱신되지 않습니다 |
| 요청 제한(429) | 표시된 시간만큼 기다리면 자동으로 다시 시도합니다 |
| "자격증명을 읽을 수 없습니다" | 그 PC에서 Claude Code에 로그인한 적이 없는 경우입니다 |
| 실행해도 아무것도 안 뜸 | `start.vbs` 대신 아래 명령으로 직접 실행해 오류를 확인합니다 |

```
powershell -NoProfile -ExecutionPolicy Bypass -File ClaudeUsageMonitor.ps1
```

## 폴더 구조

```
ClaudeUsageMonitor.ps1   진입점 (모듈 로드·시작·종료·메시지 루프)
start.vbs                콘솔 창 없이 실행하는 런처
guide.html               사용자 가이드 (트레이 메뉴에서 열림)
MODULES.md               어떤 변경을 어느 파일에서 하는지 정리한 모듈 지도
lib/                     기능별 모듈 (API·파싱·트레이·위젯·단축키·알림 등)
tools/                   유지보수 스크립트
```

## 개발 시 주의

- **`.ps1` 파일은 UTF-8 BOM으로 저장해야 합니다.** 한글이 들어 있어 BOM이 없으면 PowerShell 5.1이 파싱에 실패합니다.
  편집 후에는 아래 명령으로 BOM 재부착과 구문 검사를 합니다.
- 수정할 파일은 [MODULES.md](MODULES.md)의 표에서 고릅니다.

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1   # BOM 재부착 + 구문 검사
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Restart.ps1        # 실행 중인 모니터 재시작
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Zip.ps1      # dist\ClaudeUsageMonitor.zip 생성
```
