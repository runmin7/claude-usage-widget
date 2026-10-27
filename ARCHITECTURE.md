# AI 사용량 통합 모니터 (Claude · Gemini · AGY) 설계 및 유지보수 문서

이 문서는 **Claude · Gemini · AGY(Antigravity)** 3개 AI 서비스의 토큰/할당량 사용률을 단일 Windows 트레이 아이콘과 바탕화면 위젯에서 통합 모니터링하는 응용프로그램의 **배경지식, 상세 설계, API/로그 명세, 사용법, 그리고 향후 AI 또는 개발자가 유지보수할 때 알아야 할 핵심 규칙**을 정리한 기술 문서입니다.

---

## 1. 추진 배경 및 서비스별 정책 이해

### 1.1 통합 모니터링 배경
- 초기에는 **Claude** 단일 서비스의 5시간 세션/주간 한도만 모니터링하도록 제작되었습니다.
- 이후 사내 정책에 의해 **Claude**, **Gemini CLI**, **Antigravity(AGY)** 3개 도구를 각각 회사 계정(OAuth)으로 로그인해 사용하게 되면서, 서비스마다 서로 다른 한도 정책과 리셋 주기를 한눈에 파악하고 원하는 서비스만 선택해 볼 수 있도록 통합 모니터로 확장했습니다.
- **계정 관계**:
  - **Claude**: 회사 계정으로 Claude Code CLI 로그인 (`%USERPROFILE%\.claude\.credentials.json`)
  - **Gemini CLI & Antigravity(AGY)**: **동일한 회사 구글(Google Workspace) 계정**으로 OAuth 로그인

### 1.2 왜 서비스마다 표기 방식(`%` vs `토큰 수`)과 항목이 다른가?

| 서비스 | 사내/서버 한도 정책 | 갱신 주기 | 데이터 출처 | 위젯 표시 항목 |
|---|---|---|---|---|
| **Claude** | 5시간 세션 한도 + 7일 주간 한도 | 5시간 / 7일 | Anthropic OAuth Usage API | `현재 세션 (5시간) (%)`, `주간 전체 (7일) (%)` + 리셋 시각 |
| **Gemini** | 모델 등급별(`Pro` / `Flash`) 독립 일일 한도 풀 | 24시간 롤링 | Google Cloud Code Assist Quota API | `Pro (24시간) (%)`, `Flash (24시간) (%)` + 리셋 시각 |
| **AGY** | 1인당 주간 약 **170M(1억 7천만) 토큰** | 주간 초기화 (기본: 매주 월요일 00:00) | 로컬 `brain\*\transcript.jsonl` 실측 토큰 합산 | `주간 (X.XM / 170M) (%)` + 남은 시간 및 초기화 일시 |

#### Q1. 왜 Gemini는 '총 토큰 사용량'이 아니라 `Pro` / `Flash` 모델별 한도(%)로 표기되는가?
1. **구글 서버(Code Assist)의 할당량 풀(Pool) 분리 정책**:
   - 구글 OAuth(`standard-tier`)로 Gemini를 사용할 때 구글 서버(`cloudcode-pa.googleapis.com`)는 전체 모델을 합산한 단일 토큰 한도를 두지 않고, **모델 등급(`Pro` 계열 / `Flash` 계열 / `Flash-Lite` 계열)별로 독립된 24시간 할당량 풀**을 운영합니다.
   - 이는 단가가 높은 **Pro 모델**(`gemini-2.5-pro`, `gemini-3-pro` 등)의 일일 한도를 100% 소진하더라도 작업이 중단되지 않고, 별도 한도 풀을 가진 **Flash 모델**(`gemini-2.5-flash`, `gemini-3-flash` 등)로 자동 전환(Fallback)되어 업무를 이어갈 수 있도록 설계되어 있기 때문입니다.
2. **API 응답 스펙**:
   - Claude API와 마찬가지로 구글 공식 할당량 API(`retrieveUserQuota`)도 절대 토큰 숫자를 내려주지 않고, 각 모델 풀의 **잔여 비율(`remainingFraction`: `0.0 ~ 1.0`)과 리셋 시각(`resetTime`)만 반환**합니다.

#### Q2. AGY(Antigravity)의 '주간 170M 토큰'과 '만료일(초기화 시각)'은 어떻게 계산되는가?
1. **추정 공식(Tokenizer)이 아닌 '서버 실측 영수증' 합산**:
   - 프로그램이 글자 수를 세어 토큰을 어림잡는 공식을 내장한 것이 **아닙니다**.
   - Antigravity는 모델 서버로부터 응답을 받을 때마다 서버가 실제로 차감한 정확한 토큰 수(`input_tokens`, `cache_read_tokens`, `output_tokens`)를 로컬 로그 파일(`%USERPROFILE%\.gemini\antigravity\brain\<대화ID>\.system_generated\logs\transcript.jsonl`)에 JSON 숫자로 기록합니다.
2. **왜 주간 한도가 170M(1억 7천만) 단위로 큰가?**:
   - 에이전트가 코드를 분석하고 수정할 때 매 턴(Step)마다 이전 대화 및 파일 컨텍스트를 캐시에서 읽어오는데(`cache_read_tokens`), 한 턴당 수만 토큰의 캐시 읽기가 발생합니다.
   - 따라서 `입력 토큰 + 캐시 읽기 토큰 + 출력 토큰`을 모두 합산하면 약 50~60번의 응답만으로도 3M~4M 토큰이 소모되며, 1주일간의 업무량이 약 170M 토큰 규모가 됩니다.
3. **AGY 주간 만료일(초기화 시각) 산출 방식 ([`Get-AgyWeeklyCycle`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1#L76-L99))**:
   - `config.json`의 `agyResetDay`(기본값 `1` = 월요일) 및 `agyResetHour`(기본값 `0` = `00:00`)를 기준으로 **이번 주 주간 시작 시각(`$cycleStart`)과 다음 초기화 시각(`$resetsAt = $cycleStart.AddDays(7)`)**을 계산합니다.
   - 만약 `agyResetDay`를 `-1`로 설정하면 **최근 7일 롤링(Rolling 7d) 모드**로 동작하여, 최근 7일 내 가장 오래된 대화 스텝 시각으로부터 `+7일`을 초기화 시작 시각으로 표시합니다.
   - 위젯에는 상단 라벨에 `주간 (3.7M / 170M)`과 퍼센트(`2%`), 하단에 `5일 11시간 후  (11/2 00:00 초기화)` 형태로 남은 시간과 만료 일시가 함께 표시됩니다.

---

## 2. 시스템 아키텍처 및 데이터 흐름

```
[ClaudeUsageMonitor.ps1] (진입점 · 1초 타이머 루프 · DPI · Mutex)
   │
   ├─► [lib/Poll.ps1] Invoke-Tick
   │      ├─► [lib/Api.ps1] Start-UsageRequest (폴링 주기 도래 시, 숨김 처리되지 않은 서비스만 조회)
   │      │      ├─► 1) Update-AgyUsage    : 로컬 brain\*\transcript.jsonl 증분 캐시 합산 + 주간 만료일 산출
   │      │      ├─► 2) Update-GeminiUsage : oauth_creds.json(메모리 리프레시) + retrieveUserQuota 호출
   │      │      └─► 3) Claude 비동기 요청 : GET api.anthropic.com/api/oauth/usage
   │      │
   │      ├─► [lib/Api.ps1] Complete-UsageRequest (Claude 응답 완료 시)
   │      │      └─► Sync-CombinedState    : 표시 중인 서비스의 Limits 통합 및 전체 상태 결정
   │      │
   │      └─► Get-RenderSignature 비교 (화면에 표시할 값이나 숨김 설정이 바뀐 경우에만 렌더링)
   │             ├─► [lib/Tray.ps1]         Update-TrayIcon (3단 게이지 심볼 + 최고 경고색)
   │             ├─► [lib/Tray.ps1]         Update-Tooltip  (63자 제한 이내 표시 중인 서비스 요약)
   │             └─► [lib/WidgetLayout.ps1] Update-Widget   (표시 중인 서비스 섹션만 동적 렌더링)
```

### 2.1 장애 격리(Fault Isolation) 및 서비스별 숨김 설계
- 각 서비스는 고유한 상태 변수와 한도 배열을 가집니다([lib/State.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/State.ps1)):
  - Claude: `$script:ClaudeLimits`, `$script:ClaudeStatus`, `$script:ClaudeStatusText`
  - Gemini: `$script:GeminiLimits`, `$script:GeminiStatus`, `$script:GeminiStatusText`
  - AGY: `$script:AgyLimits`, `$script:AgyStatus`, `$script:AgyStatusText`
- 우클릭 메뉴(`클로드 숨김`, `제미나이 숨김`, `AGY 숨김`)를 통해 원하는 서비스를 개별적으로 숨길 수 있습니다.
  - 숨김 처리된 서비스는 API/로그 폴링과 트레이/위젯 표시에서 제외됩니다.
  - **최소 1개 서비스 유지 가드 ([`Invoke-ToggleServiceHide`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Menu.ps1#L8-L39))**: 현재 1개의 서비스만 표시 중일 때 마지막 남은 서비스까지 숨기려 하면 숨김을 차단하고 `"최소 하나의 서비스는 모니터링해야 합니다."` 트레이 풍선 알림을 띄웁니다.

---

## 3. 서비스별 상세 구현 명세 (유지보수 참고용)

### 3.1 Claude 모니터링 ([lib/Credential.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Credential.ps1), [lib/Api.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1), [lib/Parse.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Parse.ps1))
- **자격증명 파일**: `%USERPROFILE%\.claude\.credentials.json` (`$env:CLAUDE_CONFIG_DIR` 우선)
  - 내부 `claudeAiOauth.accessToken` 및 `claudeAiOauth.expiresAt`(Unix ms)을 **읽기 전용**으로 참조합니다.
  - **절대 금지**: Claude의 `.credentials.json` 파일을 직접 수정하거나 OAuth refresh endpoint를 직접 호출해 덮어쓰면 Claude Code CLI의 자체 토큰 갱신과 충돌하여 로그아웃됩니다.
- **API 호출**:
  - `GET https://api.anthropic.com/api/oauth/usage`
  - 헤더: `Authorization: Bearer <token>`, `User-Agent: claude-code/<version>`
  - `User-Agent`가 `claude-code/x.y.z` 형식이 아니면 서버에서 훨씬 빠르게 `429 Too Many Requests`를 반환하므로 [`Resolve-UserAgent`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1#L6-L38)를 유지해야 합니다.

### 3.2 Gemini 모니터링 ([lib/Credential.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Credential.ps1), [lib/Api.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1), [lib/Parse.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Parse.ps1))
- **자격증명 및 메모리 토큰 리프레시 ([`Get-GeminiCredential`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Credential.ps1#L72-L135))**:
  - `%USERPROFILE%\.gemini\oauth_creds.json`에서 `access_token`, `refresh_token`, `expiry_date`(Unix ms)를 읽습니다.
  - `expiry_date`가 지났다면 `POST https://oauth2.googleapis.com/token`에 `refresh_token`과 Gemini CLI 공개 OAuth Client ID/Secret(`$script:GeminiClientId`, `$script:GeminiClientSecret`)을 보내 새 `access_token`을 발급받습니다.
  - 발급받은 토큰은 파일에 쓰지 않고 **`$script:GeminiAccessToken` 및 `$script:GeminiTokenExpiry` 메모리 변수에 보관**하여 재사용합니다.
- **프로젝트 ID 확인 및 할당량 API 호출 ([`Update-GeminiUsage`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1#L79-L159))**:
  1. `$env:GOOGLE_CLOUD_PROJECT` 환경변수가 있으면 이를 프로젝트 ID로 사용합니다.
  2. 없으면 `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`를 1회 호출해 응답의 `cloudaicompanionProject` 값을 `$script:GeminiProjectId`에 캐싱합니다.
  3. `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` (Body: `{"project": "<projectId>"}`)를 호출합니다.

### 3.3 AGY (Antigravity) 모니터링 ([`Update-AgyUsage`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1#L186-L269))
- **로그 파일 위치**:
  - `%USERPROFILE%\.gemini\antigravity\brain\<conversation-id>\.system_generated\logs\transcript.jsonl`
- **로그 라인 구조 (JSONL)**:
  - 에이전트 응답(`PLANNER_RESPONSE`) 줄마다 아래 필드가 포함됩니다:
    ```json
    {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-10-27T02:30:48.555326200Z","input_tokens":8103,"cache_read_tokens":28500,"output_tokens":480}
    ```
- **고속 증분 캐싱 알고리즘**:
  - `transcript.jsonl` 파일은 크기가 수 MB에 달할 수 있으므로 전체 JSON 파싱(`ConvertFrom-Json`) 대신 `[System.IO.File]::ReadLines()` 스트리밍과 정규식 매칭을 사용합니다.
  - `$script:AgyFileCache` 해시테이블에 `파일 전체 경로 → @{ Stamp = LastWriteTimeUtc; Length = 파일크기; Entries = @(시각·토큰 배열) }`을 저장합니다.
  - 매 폴링 시 **수정 시각과 파일 크기가 변하지 않은 파일은 디스크에서 다시 읽지 않고 메모리 캐시를 즉시 사용**합니다.
- **토큰 합산식 및 만료일 계산**:
  - `StepTokens = input_tokens + cache_read_tokens + output_tokens`
  - [`Get-AgyWeeklyCycle`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1#L161-L184)이 반환한 주간 시작 시각(`CutoffUtc`) 이후의 `StepTokens` 총합을 `$script:Config.agyWeeklyLimitMillion * 1,000,000`으로 나누어 퍼센트를 산출하고, 다음 주간 리셋 시각(`ResetsAt`)을 함께 기록합니다.

---

## 4. 공통 데이터 모델 (`$script:Limits` 행 스키마)

모든 서비스의 한도 데이터는 아래 속성을 가진 `[pscustomobject]` 배열로 표준화되어 `$script:Limits`에 저장됩니다:

| 속성명 | 타입 | 설명 | 예시 |
|---|---|---|---|
| `Provider` | `string` | 서비스 식별자 (`claude` \| `gemini` \| `agy`) | `'agy'` |
| `Key` | `string` | 전체 고유 키 (리셋 감지용) | `'session'`, `'gemini_pro'`, `'agy_weekly'` |
| `Label` | `string` | 위젯 섹션 내부 표시 이름 | `'현재 세션 (5시간)'`, `'Pro (24시간)'`, `'주간 (3.7M / 170M)'` |
| `NotifyLabel` | `string` | 서비스 구분용 라벨 | `'Claude 현재 세션 (5시간)'`, `'Gemini Pro'`, `'AGY 주간'` |
| `Percent` | `double` | 사용률 (`0.0 ~ 100.0+`) | `24.5` |
| `Window` | `string` | 리셋 주기 식별자 | `'1410642'` 또는 `'2026-11-02-00'` |
| `ResetsAt` | `DateTime?` | 로컬 리셋(초기화) 시각 | `2026-11-02 00:00:00` |
| `Severity` | `int` | 경고 등급 (`0`: 정상 녹색, `1`: 주의 황색, `2`: 경고 주황, `3`: 위험 적색) | `0` |
| `DetailText` | `string?` | 카운트다운 대신 표시할 커스텀 상세 문구 (기본 `$null`) | `$null` |

---

## 5. 사용법 및 설정 (`config.json`)

### 5.1 실행 및 조작
- **실행**: 폴더 내 `start.vbs` 더블클릭 (콘솔 창 없이 백그라운드 실행)
- **위젯 열기/닫기**: 트레이 아이콘 **좌클릭** 또는 단축키 **`Ctrl+Alt+U`**
- **우클릭 메뉴**:
  - `지금 갱신 (HH:mm:ss)`: 표시 중인 서비스 즉시 재조회 (Claude가 429 제한 중이면 Gemini·AGY만 즉시 갱신)
  - `Claude 토큰 갱신 시도`: Claude 토큰 만료 시 백그라운드에서 `claude` CLI를 짧게 호출해 토큰 갱신 유도
  - `Claude 토큰 만료 시 자동 갱신`: 만료 시 자동으로 CLI를 호출해 토큰 갱신
  - `위젯 표시`: 바탕화면 통합 위젯 표시/숨김
  - `보조 한도(주간·Flash) 상세 표시`: 켜면 모든 행을 게이지 바로 표시하고, 끄면 서비스별 대표 한도(`Claude 5시간`, `Gemini Pro`, `AGY 주간`)만 게이지로 보여주고 나머지(`Claude 주간`, `Gemini Flash`)는 한 줄 텍스트로 접어 위젯 높이를 줄입니다.
  - `단축키 설정`: 위젯 토글 전역 단축키 변경
  - `클로드 숨김` / `제미나이 숨김` / `AGY 숨김`: 원하는 서비스를 위젯 및 트레이 모니터링에서 숨김 (최소 1개 서비스는 반드시 유지)
  - `로그온 시 자동 시작`: Windows 시작프로그램 등록/해제

### 5.2 `config.json` 주요 설정 키 ([lib/Config.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Config.ps1))

| 설정 키 | 기본값 | 범위 | 설명 |
|---|---|---|---|
| `pollActiveSeconds` | `300` | `60 ~ 86400` | PC 사용 중 폴링 주기 (5분) |
| `pollIdleSeconds` | `900` | `60 ~ 86400` | PC 유휴 시 폴링 주기 (15분) |
| `idleAfterSeconds` | `300` | `30 ~ 86400` | 마우스/키보드 입력이 없을 때 유휴 상태로 전환하는 시간(초) |
| `thresholds` | `[50, 70, 90, 95]` | `1 ~ 100` | 색상 등급 변화 기준(%) |
| `hideClaude` | `false` | `bool` | Claude 섹션 숨김 여부 |
| `hideGemini` | `false` | `bool` | Gemini 섹션 숨김 여부 |
| `hideAgy` | `false` | `bool` | AGY 섹션 숨김 여부 |
| `agyWeeklyLimitMillion` | `170` | `1 ~ 10000` | **AGY 주간 토큰 한도 (단위: 백만 토큰, 기본 170M)** |
| `agyResetDay` | `1` | `-1 ~ 6` | **AGY 주간 초기화 요일 (`0`=일, `1`=월[기본], ..., `6`=토, `-1`=최근 7일 롤링)** |
| `agyResetHour` | `0` | `0 ~ 23` | **AGY 주간 초기화 시각 (`0 ~ 23`시, 기본 `0`시 자정)** |
| `showWeekly` | `true` | `bool` | 보조 한도(`Claude 주간`, `Gemini Flash`) 게이지 상세 표시 여부 |
| `autoRefreshToken` | `false` | `bool` | Claude 토큰 만료 시 자동으로 `claude` CLI를 실행해 갱신할지 여부 |
| `hotkey` | `"Ctrl+Alt+U"` | 문자열 | 위젯 열기/닫기 전역 단축키 |

---

## 6. AI 및 개발자를 위한 유지보수 가이드 (Maintenance Playbook)

다음 개발이나 수정 작업을 AI 에이전트에게 지시하거나 직접 수행할 때 **반드시 지켜야 할 규칙**입니다.

### 6.1 필수 불변 규칙 3가지
1. **모든 `.ps1` 파일은 반드시 `UTF-8 with BOM`으로 저장해야 합니다.**
   - Windows PowerShell 5.1은 BOM이 없는 UTF-8 파일 내 한글 문자열을 CP949(ANSI)로 잘못 읽어 구문 오류(Syntax Error)를 일으킵니다.
   - **코드 수정 후에는 반드시 아래 스크립트를 실행**하여 BOM을 자동 부착하고 구문 검사를 통과해야 합니다:
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1
     ```
2. **`Set-StrictMode -Version Latest` 및 `$ErrorActionPreference = 'Stop'` 준수**:
   - JSON 응답 객체에서 존재하지 않을 수 있는 속성을 `$obj.prop`으로 직접 읽으면 `PropertyNotFoundException`으로 앱이 멈춥니다. 반드시 [`Get-JsonProperty $obj 'prop'`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Parse.ps1#L10-L14) 헬퍼를 사용하세요.
   - 파이프라인 결과가 0개 또는 1개일 때 `.Count` 참조가 깨지지 않도록 항상 `@(...)` 배열 래퍼로 감싸세요.
3. **트레이 툴팁(`NotifyIcon.Text`) 63자 제한 엄수**:
   - .NET `System.Windows.Forms.NotifyIcon.Text`는 63자를 넘기면 즉시 예외가 발생합니다. [`Update-Tooltip`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Tray.ps1#L98-L154)을 수정할 때는 줄별 텍스트를 짧게 유지하고 `$script:TooltipMaxLength` 절단 루프를 유지하세요.

### 6.2 자주 발생할 수 있는 유지보수 시나리오별 수정 위치

#### 시나리오 A: AGY 주간 한도량이 170M에서 다른 값(예: 200M)으로 변경된 경우
- 사용자 PC의 `config.json`에서 `"agyWeeklyLimitMillion": 200`으로 수정하거나,
- 기본값을 영구 변경하려면 [lib/Config.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Config.ps1)의 `Get-DefaultConfig` 내 `agyWeeklyLimitMillion = 170`과 [lib/Constants.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Constants.ps1)의 `agy_weekly` 기본 라벨만 변경하면 됩니다.

#### 시나리오 B: AGY 주간 초기화 요일·시각을 변경하거나 7일 롤링 모드로 바꾸고 싶은 경우
- 코드를 수정할 필요 없이 `config.json`의 설정값만 바꾸면 됩니다:
  - 예: 매주 월요일 오전 9시 초기화 → `"agyResetDay": 1, "agyResetHour": 9`
  - 예: 매주 일요일 자정 초기화 → `"agyResetDay": 0, "agyResetHour": 0`
  - 예: 첫 사용 시각으로부터 7일 롤링 → `"agyResetDay": -1`

#### 시나리오 C: AGY 토큰 집계에서 캐시 읽기(`cache_read_tokens`)를 제외하고 순수 입출력만 계산하고 싶은 경우
- [lib/Api.ps1](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1)의 [`Update-AgyUsage`](file:///c:/재무그룹웨어/7.%20유틸/클로드사용량알림/lib/Api.ps1#L186-L269) 내부에서 `Tokens = ($inTok + $cacheTok + $outTok)` 부분을 `Tokens = ($inTok + $outTok)`으로 바꾸고 `$script:AgyFileCache`가 새로고침되도록 재시작(`tools\Restart.ps1`)하면 됩니다.

### 6.3 수정 후 검증 및 재시작 명령어
```powershell
# 1. UTF-8 BOM 부착 및 전체 파일 PowerShell 구문(Syntax) 검사
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1

# 2. 실행 중인 백그라운드 모니터 종료 후 재시작 (PID 확인 포함)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Restart.ps1

# 3. 배포용 ZIP 패키지 생성 (dist\ClaudeUsageMonitor.zip)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Zip.ps1
```
