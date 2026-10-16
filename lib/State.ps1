# State.ps1 - every mutable $script: value, declared in one place
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


$script:Config      = $null
$script:Scale       = 1.0
$script:UserAgent   = $script:FallbackAgent
$script:HttpClient  = $null
$script:PendingTask = $null
$script:PendingSentAt = $null

$script:Limits      = @()
$script:Status      = 'init'   # init | ok | ratelimited | expired | error
$script:StatusText  = '초기화 중'
$script:LastSuccess = $null
$script:LastAttempt = [DateTime]::MinValue
$script:Backoff     = 0
$script:ForceFetch  = $true
$script:RetriedAuth = $false

# 한도별 알림 발화 이력. 리셋 시각(윈도우 식별자)이 바뀌면 비워 재무장한다.
$script:NotifyState = @{}

# 첫 조회로 기준선을 잡았는지. 프로그램을 58%에서 켰다면 50% 초과는 이미 지난 일이므로 알리지 않는다.
$script:NotifyPrimed = $false

# 리셋 직후 즉시 갱신을 이미 예약한 창들. 같은 창에서 반복 요청하는 것을 막는다.
$script:ResetHandled = @{}

$script:CurrentIcon = $null     # @{ Icon = ...; Handle = ... }

# WinForms 컨트롤은 할당받은 Font의 소유권을 갖지 않는다. Dispose()해도 폰트는 살아 있으므로
# 라벨마다 새로 만들면 GDI 핸들이 쌓인다. 크기·스타일 조합별로 하나만 만들어 공유하고 종료 시 해제한다.
$script:FontCache   = @{}

# 마지막으로 그린 내용의 지문. 값이 그대로면 다시 그리지 않는다.
$script:LastRender  = ''

$script:WidgetForm  = $null
$script:NotifyIcon  = $null
$script:AppContext  = $null
$script:DragOrigin  = $null

# 마지막으로 읽은 자격증명 파일의 수정 시각. 401 재시도가 의미 있는지 판단하는 기준.
$script:CredentialStamp = $null

# 마지막 토큰 갱신 시도 시각. 쿨다운으로 반복 실행을 막는다.
$script:LastRefreshAttempt = $null

$script:HotkeySink   = $null
$script:HotkeySeen   = 0      # 마지막으로 처리한 PressCount
$script:HotkeyText   = ''     # 현재 등록된 조합 (표시용)
$script:HotkeyError  = ''     # 등록 실패 사유. 비어 있으면 정상
$script:HotkeyDraft  = ''     # 설정 대화상자에서 캡처 중인 조합


