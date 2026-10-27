# Poll.ps1 - status, backoff, poll interval, the 1-second tick
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.

function Set-Status([string]$Status, [string]$Text) {
    $script:Status     = $Status
    $script:StatusText = $Text
}

function Set-NetworkBackoff([string]$message) {
    $script:Backoff = if ($script:Backoff -lt $script:NetworkFirstBackoff) {
        $script:NetworkFirstBackoff
    } else {
        [Math]::Min($script:Backoff * 2, $script:NetworkMaxBackoff)
    }
    $script:ClaudeStatus     = 'error'
    $script:ClaudeStatusText = "갱신 실패: $message"
    Set-Status -Status 'error' -Text $script:ClaudeStatusText
}

function Get-PollInterval {
    if ($script:Backoff -gt 0) { return $script:Backoff }
    if ([NativeUtil]::IdleSeconds() -ge $script:Config.idleAfterSeconds) {
        return [int]$script:Config.pollIdleSeconds
    }
    return [int]$script:Config.pollActiveSeconds
}


function Request-RefreshOnReset {
    # 리셋 시각이 지난 값은 확실히 낡았다(세션이 리셋됐는데 67%를 계속 보여주면 오해를 부른다).
    # 창마다 한 번만 예약한다. 서버가 아직 롤오버되지 않았다면 resets_at이 그대로 오므로,
    # 같은 창을 다시 요청하지 않아 요청 제한을 자극하지 않는다.
    if ($script:Backoff -gt 0) { return }

    foreach ($row in $script:Limits) {
        if (-not $row.ResetsAt) { continue }
        # 서버 시계와의 오차를 감안해 조금 지난 뒤에 요청한다.
        if (((Get-Date) - $row.ResetsAt).TotalSeconds -lt 20) { continue }

        $key = "$($row.Key)|$($row.Window)"
        if ($script:ResetHandled.ContainsKey($key)) { continue }
        $script:ResetHandled[$key] = $true
        $script:ForceFetch = $true
    }

    # 지나간 창의 이력은 들고 있을 이유가 없다.
    if ($script:ResetHandled.Count -gt 32) {
        $live = @($script:Limits | ForEach-Object { "$($_.Key)|$($_.Window)" })
        foreach ($key in @($script:ResetHandled.Keys)) {
            if ($live -notcontains $key) { $script:ResetHandled.Remove($key) }
        }
    }
}

function Invoke-Tick {
    Request-RefreshOnReset

    if ($script:PendingTask) {
        if ($script:PendingTask.IsCompleted) { Complete-UsageRequest }
        elseif (((Get-Date) - $script:PendingSentAt).TotalSeconds -gt 40) {
            # HttpClient 타임아웃이 어떤 이유로 걸리지 않은 경우의 안전장치.
            $script:PendingTask = $null
            Set-NetworkBackoff '응답 시간 초과'
            Sync-CombinedState
        }
    }
    elseif ($script:ForceFetch -or ((Get-Date) - $script:LastAttempt).TotalSeconds -ge (Get-PollInterval)) {
        $script:ForceFetch = $false
        [void](Start-UsageRequest)
    }

    # 폴링은 5~15분에 한 번이지만 타이머는 1초마다 돈다. 매 틱마다 아이콘과 위젯 컨트롤을 전부
    # 재생성하면 값이 그대로인데도 GDI 작업만 쌓인다. 실제로 보이는 내용이 바뀔 때만 다시 그린다.
    # (카운트다운 문자열은 분 단위로 바뀌므로 갱신은 대체로 분당 한 번이다.)
    $signature = Get-RenderSignature
    if ($signature -ne $script:LastRender) {
        $script:LastRender = $signature
        Update-TrayIcon
        Update-Tooltip
        Update-Widget
    }
}
