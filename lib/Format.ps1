# Format.ps1 - countdown text, DPI scaling, render signature
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


# 폰트 크기는 포인트 단위라 DPI 인식이 켜지면 저절로 커진다. 반면 여백·게이지·창 크기처럼
# 픽셀로 지정한 값은 직접 배율을 곱해야 고배율 화면에서 비율이 맞는다.
function Get-Px([double]$logical) { return [int][Math]::Round($logical * $script:Scale) }

function Format-Countdown($target, [string]$suffix = '후') {
    if (-not $target) { return '리셋 시각 미제공' }
    $span = $target - (Get-Date)
    if ($span.TotalSeconds -le 0) { return '리셋됨' }
    # TimeSpan의 Days/Hours/Minutes는 이미 잘린 구성요소다.
    # [int]$span.TotalDays로 쓰면 PowerShell이 반올림해 4.8일을 "5일"로 만든다.
    if ($span.TotalDays -ge 1) { return "{0}일 {1}시간 {2}" -f $span.Days, $span.Hours, $suffix }
    if ($span.TotalHours -ge 1) { return "{0}시간 {1}분 {2}" -f $span.Hours, $span.Minutes, $suffix }
    return "{0}분 {1}" -f [Math]::Max(1, $span.Minutes), $suffix
}

function Get-RenderSignature {
    # 표시 설정과 각 서비스의 상태도 지문에 넣어야 메뉴 토글 및 개별 상태 변화가 즉시 반영된다.
    $parts = @(
        $script:Status,
        $script:StatusText,
        $script:ClaudeStatus,
        $script:ClaudeStatusText,
        $script:GeminiStatus,
        $script:GeminiStatusText,
        $script:AgyStatus,
        $script:AgyStatusText,
        [string]$script:Config.showWeekly,
        [string]$script:Config.hideClaude,
        [string]$script:Config.hideGemini,
        [string]$script:Config.hideAgy
    )
    foreach ($row in $script:Limits) {
        $detail = if ($row.DetailText) { $row.DetailText } else { Format-Countdown $row.ResetsAt }
        $parts += "$($row.Key)|$($row.Label)|$([int][Math]::Round($row.Percent))|$($row.Severity)|$detail"
    }
    if ($script:LastSuccess) { $parts += $script:LastSuccess.ToString('HH:mm:ss') }
    return ($parts -join ';')
}

function Get-SessionRow {
    if ($script:Limits.Count -eq 0) { return $null }
    $session = $script:Limits | Where-Object { $_.Key -eq 'session' } | Select-Object -First 1
    if ($session) { return $session }
    return $script:Limits[0]
}

function Get-OverallSeverity {
    $max = 0
    foreach ($row in $script:Limits) {
        if ($row.Severity -gt $max) { $max = $row.Severity }
    }
    return $max
}
