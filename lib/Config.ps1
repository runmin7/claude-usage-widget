# Config.ps1 - config.json: defaults, validation, save, retry-after
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


function Get-DefaultConfig {
    [pscustomobject]@{
        pollActiveSeconds = 300
        pollIdleSeconds   = 900
        idleAfterSeconds  = 300
        thresholds        = @(50, 70, 90, 95)
        hotkey            = 'Ctrl+Alt+U'
        showWeekly        = $true

        # 서비스별 숨김 여부 (최소 1개는 반드시 false여야 함)
        hideClaude        = $false
        hideGemini        = $false
        hideAgy           = $false

        # AGY(Antigravity) 주간 토큰 한도 (단위: 백만 토큰, 기본 170M)
        agyWeeklyLimitMillion = 170

        # AGY 주간 초기화 기준 요일 (0=일, 1=월[기본], ..., 6=토, -1=첫 사용 시점부터 7일 롤링)
        agyResetDay       = 1
        agyResetHour      = 0

        # 토큰이 만료됐을 때 claude CLI를 대신 실행해 갱신을 유도한다.
        # 기본은 꺼둔다 — 회당 약 10초가 걸리고 사용량을 소량 쓴다(실측 약 4만 토큰, $0.02).
        autoRefreshToken       = $false
        refreshCooldownMinutes = 60
        widgetVisible     = $false
        widgetX           = $null
        widgetY           = $null
    }
}

function Get-SaneInt($value, [int]$fallback, [int]$minimum, [int]$maximum) {
    $parsed = 0
    if (-not [int]::TryParse([string]$value, [ref]$parsed)) { return $fallback }
    if ($parsed -lt $minimum) { return $minimum }
    if ($parsed -gt $maximum) { return $maximum }
    return $parsed
}

function Repair-Config {
    # JSON 파싱은 성공했지만 개별 값이 비정상인 경우를 걸러낸다. 특히 폴링 간격이 0이나 음수가 되면
    # 매 틱(1초)마다 조건이 참이 되어, 요청 제한이 사나운 엔드포인트에 초당 요청을 보내게 된다.
    $defaults = Get-DefaultConfig

    # 이전 이름(agtWeeklyLimitMillion)이 있으면 새 이름(agyWeeklyLimitMillion)으로 이관한다.
    $oldAgtLimit = Get-JsonProperty $script:Config 'agtWeeklyLimitMillion'
    if ($null -ne $oldAgtLimit -and -not $script:Config.PSObject.Properties.Match('agyWeeklyLimitMillion').Count) {
        $script:Config | Add-Member -NotePropertyName 'agyWeeklyLimitMillion' -NotePropertyValue $oldAgtLimit
    }

    # 없는 키부터 채운다.
    foreach ($prop in $defaults.PSObject.Properties) {
        if (-not $script:Config.PSObject.Properties.Match($prop.Name).Count) {
            $script:Config | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }

    $script:Config.pollActiveSeconds     = Get-SaneInt $script:Config.pollActiveSeconds     $defaults.pollActiveSeconds     60 86400
    $script:Config.pollIdleSeconds       = Get-SaneInt $script:Config.pollIdleSeconds       $defaults.pollIdleSeconds       60 86400
    $script:Config.idleAfterSeconds      = Get-SaneInt $script:Config.idleAfterSeconds      $defaults.idleAfterSeconds      30 86400
    $script:Config.agyWeeklyLimitMillion = Get-SaneInt $script:Config.agyWeeklyLimitMillion $defaults.agyWeeklyLimitMillion 1  10000
    $script:Config.agyResetDay           = Get-SaneInt $script:Config.agyResetDay           $defaults.agyResetDay          -1  6
    $script:Config.agyResetHour          = Get-SaneInt $script:Config.agyResetHour          $defaults.agyResetHour          0  23

    $clean = @()
    foreach ($threshold in @($script:Config.thresholds)) {
        $parsed = 0
        if ([int]::TryParse([string]$threshold, [ref]$parsed) -and $parsed -gt 0 -and $parsed -le 100) {
            $clean += $parsed
        }
    }
    $clean = @($clean | Sort-Object -Unique)
    if ($clean.Count -eq 0) { $clean = @($defaults.thresholds) }
    $script:Config.thresholds = $clean

    # 해석할 수 없는 조합을 들고 있으면 단축키가 조용히 죽는다. 기본값으로 되돌린다.
    if (-not (ConvertFrom-HotkeyString ([string]$script:Config.hotkey))) {
        $script:Config.hotkey = $defaults.hotkey
    }

    if ($script:Config.showWeekly -isnot [bool]) { $script:Config.showWeekly = $defaults.showWeekly }
    if ($script:Config.hideClaude -isnot [bool]) { $script:Config.hideClaude = $defaults.hideClaude }
    if ($script:Config.hideGemini -isnot [bool]) { $script:Config.hideGemini = $defaults.hideGemini }
    if ($script:Config.hideAgy    -isnot [bool]) { $script:Config.hideAgy    = $defaults.hideAgy }

    # 3개 서비스가 모두 숨김 상태가 되지 않도록 최소 1개는 표시한다.
    if ($script:Config.hideClaude -and $script:Config.hideGemini -and $script:Config.hideAgy) {
        $script:Config.hideClaude = $false
    }

    if ($script:Config.autoRefreshToken -isnot [bool]) { $script:Config.autoRefreshToken = $defaults.autoRefreshToken }

    # 쿨다운이 0이면 갱신을 연달아 띄워 사용량을 태운다. 하한을 강제한다.
    $script:Config.refreshCooldownMinutes = Get-SaneInt `
        $script:Config.refreshCooldownMinutes $defaults.refreshCooldownMinutes 10 1440
    if ($script:Config.widgetVisible -isnot [bool]) { $script:Config.widgetVisible = $defaults.widgetVisible }
}

function Import-Config {
    $defaults = Get-DefaultConfig
    if (-not (Test-Path $script:ConfigPath)) {
        $script:Config = $defaults
        Export-Config
        return
    }
    try {
        $loaded = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        try { Copy-Item $script:ConfigPath "$($script:ConfigPath).bad" -Force } catch { }
        $script:Config = $defaults
        return
    }
    $script:Config = $loaded
    Repair-Config
}

function Export-Config {
    try {
        $temp = "$($script:ConfigPath).tmp"
        $script:Config | ConvertTo-Json -Depth 5 | Set-Content $temp -Encoding UTF8
        Move-Item $temp $script:ConfigPath -Force
    }
    catch { }
}


# 429 대기를 설정 파일에 남겨 재시작에도 살아남게 한다.
function Save-RetryAfter([int]$seconds) {
    try {
        $until = (Get-Date).AddSeconds($seconds).ToString('o')
        if ($script:Config.PSObject.Properties.Match('retryAfter').Count) {
            $script:Config.retryAfter = $until
        }
        else {
            $script:Config | Add-Member -NotePropertyName 'retryAfter' -NotePropertyValue $until
        }
        Export-Config
    }
    catch { }
}

# 시작 시 남아 있는 대기를 복원한다. 지난 값이면 무시한다.
function Restore-RetryAfter {
    $saved = Get-JsonProperty $script:Config 'retryAfter'
    if (-not $saved) { return }

    try { $until = [datetime]::Parse([string]$saved, [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { return }

    $remaining = [int]($until - (Get-Date)).TotalSeconds
    if ($remaining -le 0) { return }

    $script:Backoff = [Math]::Min($remaining, $script:RateLimitMaxBackoff)
    $script:ForceFetch = $false
    $script:ClaudeStatus = 'ratelimited'
    $script:ClaudeStatusText = (
        "요청 제한 대기 중 — {0}분 남음" -f [int][Math]::Ceiling($script:Backoff / 60))
    Set-Status -Status 'ratelimited' -Text $script:ClaudeStatusText
}
