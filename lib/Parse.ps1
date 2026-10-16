# Parse.ps1 - response JSON to display rows; window key; severity
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


# StrictMode에서는 없는 속성에 접근하면 값을 비교하기도 전에 PropertyNotFoundException이 난다.
# 즉 `$null -eq $obj.foo` 같은 널 체크로는 방어되지 않는다. 비공식 API가 필드를 빼고 보내도
# 파싱이 통째로 실패하지 않도록 모든 하위 필드는 이 함수를 통해 읽는다.
function Get-JsonProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    if (-not $obj.PSObject.Properties.Match($name).Count) { return $null }
    return $obj.$name
}

# 알림 이력을 붙여둘 "창" 식별자.
#
# resets_at 원문을 그대로 쓰면 안 된다. 서버가 이 값을 요청 시점에 계산해 소수점 이하가 매번 달라지고
# (09:00:00.114767 → 09:00:00.440269), 심지어 같은 경계를 정시 직전(03:59:59.52)과 직후(09:00:00.11)로
# 번갈아 표현한다. 원문을 키로 쓰면 갱신마다 새 창으로 보여 이력이 초기화되고,
# 이미 지나간 임계치가 다시 발화한다.
#
# 그래서 10분 단위로 반올림해 흔들림을 흡수한다. 세션 창은 5시간, 주간은 7일 간격이므로
# 이 정도 뭉개도 서로 다른 창이 같은 키를 갖는 일은 없다.
function Get-LimitWindow([string]$iso) {
    $when = ConvertTo-LocalTime $iso
    if (-not $when) { return 'none' }

    # 날짜와 시각을 따로 다루면 자정 경계에서 23:59:59.9와 00:00:00.1이 다른 키가 되어
    # 같은 문제가 되돌아온다. 고정 기준점부터의 절대 슬롯 번호로 매긴다.
    $minutes = ($when - [datetime]'2000-01-01').TotalMinutes
    return [string][int64][Math]::Round($minutes / 10.0)
}

function ConvertTo-LocalTime([string]$iso) {
    if ([string]::IsNullOrWhiteSpace($iso)) { return $null }
    try {
        # 오프셋 표기가 없는 타임스탬프는 UTC로 간주한다. 없으면 로컬 시간으로 해석되어
        # 카운트다운이 시차만큼 틀어진다.
        return [System.DateTimeOffset]::Parse(
            $iso,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal).LocalDateTime
    }
    catch { return $null }
}

function Get-LimitLabel([string]$kind) {
    if ($script:LimitLabel.ContainsKey($kind)) { return $script:LimitLabel[$kind] }
    if ($kind -like 'weekly_*') { return "주간 $($kind.Substring(7))" }
    return $kind
}

function Get-EffectiveSeverity([double]$percent, $serverSeverity) {
    # 서버가 준 severity와 사용자 임계치에서 도출한 severity 중 높은 쪽을 쓴다.
    # 서버는 59%에서도 normal을 주므로, 사용자가 50%를 첫 경고선으로 지정했다면 서버 값만 믿을 수 없다.
    $rank = 0
    if ($serverSeverity -and $script:SeverityRank.ContainsKey([string]$serverSeverity)) {
        $rank = $script:SeverityRank[[string]$serverSeverity]
    }

    # 넘어선 임계치 중 가장 높은 것의 순서가 곧 등급이다(1부터, 위험 등급 3에서 포화).
    $sorted = @($script:Config.thresholds | Sort-Object)
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ($percent -ge $sorted[$i]) {
            $rank = [Math]::Max($rank, [Math]::Min($i + 1, 3))
        }
    }

    return $rank
}

function ConvertFrom-UsagePayload($payload) {
    $rows = @()

    foreach ($entry in @(Get-JsonProperty $payload 'limits')) {
        $percent = Get-JsonProperty $entry 'percent'
        if ($null -eq $percent) { continue }

        $kind = [string](Get-JsonProperty $entry 'kind')
        if ([string]::IsNullOrWhiteSpace($kind)) { continue }

        $resets = [string](Get-JsonProperty $entry 'resets_at')
        $rows += [pscustomobject]@{
            Key      = $kind
            Label    = Get-LimitLabel $kind
            Percent  = [double]$percent
            Window   = Get-LimitWindow $resets
            ResetsAt = ConvertTo-LocalTime $resets
            Severity = Get-EffectiveSeverity ([double]$percent) (Get-JsonProperty $entry 'severity')
        }
    }

    # limits[]가 사라지거나 비어 오는 경우를 대비한 평면 필드 경로.
    if ($rows.Count -eq 0) {
        foreach ($pair in @(
            @{ Key = 'session';    Field = 'five_hour' },
            @{ Key = 'weekly_all'; Field = 'seven_day' }
        )) {
            $bucket = Get-JsonProperty $payload $pair.Field
            $percent = Get-JsonProperty $bucket 'utilization'
            if ($null -eq $percent) { continue }

            $resets = [string](Get-JsonProperty $bucket 'resets_at')
            $rows += [pscustomobject]@{
                Key      = $pair.Key
                Label    = Get-LimitLabel $pair.Key
                Percent  = [double]$percent
                Window   = Get-LimitWindow $resets
                ResetsAt = ConvertTo-LocalTime $resets
                Severity = Get-EffectiveSeverity ([double]$percent) $null
            }
        }
    }

    return @($rows | Sort-Object `
        @{ Expression = { if ($script:LimitRank.ContainsKey($_.Key)) { $script:LimitRank[$_.Key] } else { 9 } } },
        @{ Expression = { $_.Key } })
}


