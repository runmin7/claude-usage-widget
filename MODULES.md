# 모듈 지도

이 파일은 **어떤 변경을 어느 파일에서 하는지** 알려주기 위한 것이다. 코드를 고치기 전에 이 표만
보고 대상 파일을 고르면, 나머지 파일은 열지 않아도 된다.
배경지식과 3개 서비스(Claude · Gemini · AGY)의 API/로그 상세 스펙은 [ARCHITECTURE.md](ARCHITECTURE.md)를 참고하라.

## 이런 변경은 이 파일

| 하려는 일 | 파일 |
|---|---|
| 색 바꾸기 (등급색 · 서비스별 섹션 헤더색) | `lib/Constants.ps1` |
| 임계치 기본값·라벨 이름 바꾸기 | `lib/Constants.ps1` |
| 위젯 배치·섹션 구분·글자 크기·줄 간격 | `lib/WidgetLayout.ps1` |
| 위젯 창 자체(폭·위치·드래그·Alt+Tab) | `lib/Widget.ps1` |
| 트레이 아이콘 모양(3단 게이지)·툴팁 | `lib/Tray.ps1` |
| 메뉴 항목 추가·순서·서비스별 숨김 토글 | `lib/Menu.ps1` |
| 설정 항목 추가(`agyWeeklyLimitMillion`, `agyResetDay` 등)·검증 규칙 | `lib/Config.ps1` |
| 폴링 주기·백오프 | `lib/Poll.ps1` |
| Claude / Gemini API 응답 파싱·단위 포맷 | `lib/Parse.ps1` |
| Claude 요청·Gemini 할당량 조회·AGY 로컬 로그 집계 및 만료일 산출 | `lib/Api.ps1` |
| Claude 토큰 읽기·갱신 유도 / Gemini OAuth 리프레시 | `lib/Credential.ps1` |
| 남은 시간 문구·최고 등급 산출·표시 지문 | `lib/Format.ps1` |
| 단축키 조합·설정 창 | `lib/Hotkey.ps1` |
| 로그온 자동 시작 | `lib/Autostart.ps1` |
| Win32 API 추가 | `lib/Native.ps1` |
| 시작 순서·종료 정리 | `ClaudeUsageMonitor.ps1` |

## 파일 목록

| 파일 | 줄 | 내용 |
|---|---|---|
| `ClaudeUsageMonitor.ps1` | 약 190 | 진입점. 모듈 로드, 시작 순서, 종료, 메시지 루프 |
| `lib/Native.ps1` | 약 120 | 런타임 컴파일 C# 2개 — Win32 P/Invoke, 단축키 수신 창 |
| `lib/Constants.ps1` | 약 100 | URL·경로·색(서비스별 헤더/등급)·임계치·한도 라벨 |
| `lib/State.ps1` | 약 75 | 실행 중 변하는 `$script:` 값 전부 (서비스별 상태·캐시 포함) |
| `lib/Config.ps1` | 약 165 | `config.json` 읽기·검증·저장, 서비스 숨김 및 요청 제한 대기 보존 |
| `lib/Credential.ps1` | 약 190 | Claude 토큰 읽기·CLI 갱신 유도, Gemini OAuth 메모리 리프레시 |
| `lib/Api.ps1` | 약 420 | Claude 비동기 요청, Gemini 할당량 API 호출, AGY 로컬 로그 증분 집계 및 만료일 계산 |
| `lib/Parse.ps1` | 약 190 | Claude / Gemini 응답 JSON → 표시 행, 창 식별자, 등급 판정 |
| `lib/Format.ps1` | 약 60 | 카운트다운 문구, DPI 배율, 전체 최고 등급, 표시 지문 |
| `lib/Poll.ps1` | 약 85 | 상태·백오프·폴링 간격·1초 틱 |
| `lib/Tray.ps1` | 약 155 | 상징형 3단 게이지 아이콘 렌더링, 서비스 요약 툴팁 |
| `lib/Widget.ps1` | 약 115 | 위젯 창 생성·위치·드래그·표시·숨김 |
| `lib/WidgetLayout.ps1` | 약 250 | 위젯이 그리는 내용 — Claude · Gemini · AGY 섹션 동적 배치 |
| `lib/Hotkey.ps1` | 약 190 | 조합 해석·등록, 설정 대화상자 |
| `lib/Menu.ps1` | 약 170 | 트레이 컨텍스트 메뉴 및 서비스 숨김 토글 가드 |
| `lib/Autostart.ps1` | 약 40 | 시작 폴더 바로가기 |

## 알아야 할 규칙 세 가지

**1. UTF-8 BOM이 필수다.** 한글이 들어 있어서, BOM이 없으면 PowerShell 5.1이 ANSI로 읽어
파싱조차 실패한다. 편집기가 BOM을 떼는 경우가 많으니 **고친 뒤에는 반드시** 실행한다.

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1
```

**2. `$script:`는 진입점 스코프를 가리킨다.** `lib/` 파일은 dot-source(`.`)로 읽히므로 별도
스코프가 생기지 않는다. 그래서 파일이 나뉘어 있어도 `$script:Config` 같은 값을 어디서나 쓴다.
새 상태가 필요하면 `lib/State.ps1`에 선언을 추가한다.

**3. 로드 순서는 셋만 지키면 된다.** `Native` → `Constants` → `State` 가 먼저다(코드를 실행하는
파일이기 때문이다). 나머지는 함수만 정의하므로 순서가 무관하다. `Menu.ps1`은 예외로, `$menu`를
만들어 트레이 아이콘에 바로 붙이므로 시작 순서 중간에서 읽어들인다.

## 자주 쓰는 명령

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1   # BOM 재부착 + 구문 검사
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Restart.ps1        # 재시작
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Zip.ps1      # 배포 ZIP 생성
```

오류를 눈으로 보려면 런처(`start.vbs`) 대신 직접 실행한다. 평소에는 창이 숨겨져 오류가 보이지 않는다.

```
powershell -NoProfile -ExecutionPolicy Bypass -File ClaudeUsageMonitor.ps1
```

아키텍처 및 상세 기술 명세는 [ARCHITECTURE.md](ARCHITECTURE.md)에 있다.
