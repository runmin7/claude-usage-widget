# Constants.ps1 - paths, colours, thresholds, limit labels
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


$script:UsageUrl           = 'https://api.anthropic.com/api/oauth/usage'
$script:GeminiTokenUrl     = 'https://oauth2.googleapis.com/token'
$script:GeminiLoadUrl      = 'https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist'
$script:GeminiQuotaUrl     = 'https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota'

# -File로 실행하면 $PSScriptRoot가 채워진다. 점 소싱이나 -Command로 불러온 경우엔 비어 있는데,
# StrictMode에서 그때 $MyInvocation.MyCommand.Path에 손대면 예외가 난다.
# $script:ScriptDir 은 진입점이 미리 정해준다.
#
# 여기서 $PSScriptRoot 를 쓰면 안 된다 — dot-source된 파일 안에서 그 값은 "그 파일이 있는
# 디렉터리"(즉 lib/)를 가리킨다. 그러면 설정·런처 경로가 모두 lib/ 아래를 보게 되어,
# 설정이 lib/config.json 에 쓰이고 자동 시작 바로가기가 깨진다.
if (-not $script:ScriptDir) { throw 'ScriptDir이 설정되지 않았습니다. 진입점에서 먼저 지정해야 합니다.' }

$script:ConfigPath    = Join-Path $script:ScriptDir 'config.json'
$script:LauncherPath  = Join-Path $script:ScriptDir 'start.vbs'
$script:ShortcutName  = 'Claude 사용량 모니터.lnk'
$script:AppTitle      = 'AI 사용량 모니터'
$script:FallbackAgent = 'claude-code/2.1.267'

# NotifyIcon.Text는 63자를 넘기면 예외가 난다.
$script:TooltipMaxLength = 63

# 429는 한 번 걸리면 잘 안 풀리는 엔드포인트다. 첫 백오프를 폴링 간격보다 크게 잡는다.
$script:RateLimitFirstBackoff = 600
$script:RateLimitMaxBackoff   = 1800
$script:NetworkFirstBackoff   = 60
$script:NetworkMaxBackoff     = 600

# 0 정상 → 1 주의 → 2 경고 → 3 위험. 넘어선 임계치의 순서가 등급이 되고 3에서 포화한다.
$script:SeverityRank = @{ normal = 0; warning = 2; critical = 3; exceeded = 3 }

# 이벤트 핸들러에서도 써야 하므로 함수 지역 변수가 아니라 스크립트 범위에 둔다.
# 회색은 쓰지 않는다 — 어두운 배경에서 너무 안 읽힌다. 색을 쓰는 곳은 세 군데뿐이다:
# 퍼센트와 게이지는 severity 색, 세션 남은 시간은 전용 강조색, 갱신 실패는 적색. 나머지 글자는 모두 흰색.
$script:ColorBright = [System.Drawing.Color]::FromArgb(238, 240, 244)

# 세션 남은 시간 및 상세 강조색. severity가 녹·황·주황·적을 다 쓰므로 그 계열을 피해야 하고,
# 어두운 배경에서 흰색과도 뚜렷이 갈라져야 한다. 그 조건을 만족하는 청색 계열로 잡았다.
$script:ColorTime   = [System.Drawing.Color]::FromArgb(86, 208, 244)

# 보조 한도를 접었을 때의 한 줄 요약에서 한도 부분에만 쓴다. 뒤따르는 시간은 흰색이라,
# 게이지가 없는 줄에서도 두 정보가 색으로 갈라져 읽힌다.
$script:ColorSummary = [System.Drawing.Color]::FromArgb(95, 220, 192)

# 서비스 섹션 헤더 구분색 (Claude / Gemini / AGY)
$script:ProviderColor = @{
    claude = [System.Drawing.Color]::FromArgb(240, 154, 108)
    gemini = [System.Drawing.Color]::FromArgb(108, 180, 255)
    agy    = [System.Drawing.Color]::FromArgb(186, 145, 255)
}

$script:ProviderTitle = @{
    claude = 'Claude'
    gemini = 'Gemini'
    agy    = 'AGY'
}

# RegisterHotKey 수정자 플래그. MOD_NOREPEAT는 키를 누르고 있을 때 반복 발화를 막는다.
$script:HotkeyModifier = @{ alt = 0x1; ctrl = 0x2; control = 0x2; shift = 0x4; win = 0x8; windows = 0x8 }
$script:HotkeyNoRepeat = 0x4000

$script:SeverityColor = @{
    0 = [System.Drawing.Color]::FromArgb( 46, 158,  91)
    1 = [System.Drawing.Color]::FromArgb(198, 160,  30)
    2 = [System.Drawing.Color]::FromArgb(224, 122,   0)
    3 = [System.Drawing.Color]::FromArgb(214,  69,  69)
}

# limits[].kind → 표시 이름. 없는 kind는 원문을 그대로 쓴다(새 한도 유형이 생겨도 표시된다).
$script:LimitLabel = @{
    session           = '5시간 세션'
    weekly_all        = '주간 한도'
    weekly_opus       = '주간 Opus'
    weekly_sonnet     = '주간 Sonnet'
    weekly_cowork     = '주간 Cowork'
    weekly_oauth_apps = '주간 외부 앱'
    gemini_pro        = 'Pro (일간)'
    gemini_flash      = 'Flash (일간)'
    agy_weekly        = '주간 (170M)'
}

# 표시 순서: 세션 → 주간 전체 → 나머지 주간 → 그 외
$script:LimitRank = @{ session = 0; weekly_all = 1; gemini_pro = 2; gemini_flash = 3; agy_weekly = 4 }
