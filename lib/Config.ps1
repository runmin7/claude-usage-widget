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
        notifyEnabled     = $true
        showWeekly        = $true

        # 토큰이 만료됐을 때 claude CLI를 대신 실행해 갱신을 유도한다.
        # 기본은 꺼둔다 — 회당 약 10초가 걸리고 사용량을 소량 쓴다(실측 약 4만 토큰, $0.02).
        # 사용량을 보는 도구가 사용량을 쓰는 것이므로 사용자가 켜는 선택이어야 한다.
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

    # 없는 키부터 채운다. 이전에는 Import-Config가 먼저 채워준다고 가정했는데, 그러면 이 함수를
    # 단독으로 부를 수 없다(없는 속성에 대입하면 예외가 난다). 자체적으로 완결되게 둔다.
    # 새 버전에서 설정 항목이 추가된 경우도 여기서 흡수된다.
    foreach ($prop in $defaults.PSObject.Properties) {
        if (-not $script:Config.PSObject.Properties.Match($prop.Name).Count) {
            $script:Config | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }

    $script:Config.pollActiveSeconds = Get-SaneInt $script:Config.pollActiveSeconds $defaults.pollActiveSeconds 60 86400
    $script:Config.pollIdleSeconds   = Get-SaneInt $script:Config.pollIdleSeconds   $defaults.pollIdleSeconds   60 86400
    $script:Config.idleAfterSeconds  = Get-SaneInt $script:Config.idleAfterSeconds  $defaults.idleAfterSeconds  30 86400

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

    if ($script:Config.notifyEnabled -isnot [bool]) { $script:Config.notifyEnabled = $defaults.notifyEnabled }
    if ($script:Config.showWeekly -isnot [bool]) { $script:Config.showWeekly = $defaults.showWeekly }
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
        # 손상된 설정 때문에 프로그램이 뜨지 않는 것보다 기본값으로 사는 편이 낫다.
        # 다만 이후의 Export-Config가 기본값으로 사용자 설정을 덮어쓰게 되므로, 읽지 못한 원본을
        # 먼저 남겨 되돌릴 수 있게 한다.
        try { Copy-Item $script:ConfigPath "$($script:ConfigPath).bad" -Force } catch { }
        $script:Config = $defaults
        return
    }
    # 없는 키 보충과 값 검증은 Repair-Config가 함께 처리한다.
    $script:Config = $loaded
    Repair-Config
}

function Export-Config {
    try {
        # 곧바로 목적지에 쓰면 다른 인스턴스가 반쯤 쓰인 파일을 읽어 파싱에 실패할 수 있다.
        # 그 인스턴스는 기본값으로 살아난 뒤 나중에 그 기본값을 다시 저장해 사용자 설정을 지운다.
        # 임시 파일에 다 쓴 다음 한 번에 갈아치워 그 틈을 없앤다.
        $temp = "$($script:ConfigPath).tmp"
        $script:Config | ConvertTo-Json -Depth 5 | Set-Content $temp -Encoding UTF8
        Move-Item $temp $script:ConfigPath -Force
    }
    catch {
        # 설정 저장 실패는 기능 손실이 아니다. 조용히 넘긴다.
    }
}


# 429 대기를 설정 파일에 남겨 재시작에도 살아남게 한다.
# 값은 "이 시각 이후에 다시 시도해도 된다"는 로컬 시각의 ISO 문자열이다.
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

    # 남은 시간만큼 물러난 상태로 시작한다. 상한은 백오프 상한과 같다.
    $script:Backoff = [Math]::Min($remaining, $script:RateLimitMaxBackoff)
    $script:ForceFetch = $false
    Set-Status -Status 'ratelimited' -Text (
        "요청 제한 대기 중 — {0}분 남음. 껐다 켜도 빨라지지 않습니다" -f `
        [int][Math]::Ceiling($script:Backoff / 60))
}

