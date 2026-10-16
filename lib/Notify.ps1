# Notify.ps1 - threshold balloons and the per-window fire history
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


function Send-ThresholdNotifications {
    # 첫 조회 결과는 기준선으로만 쓴다. 프로그램을 58%에서 켰다면 50% 초과는 이미 지난 일이고,
    # 그 시점에 알려도 사용자가 할 수 있는 것이 없다. 앞으로 넘어서는 구간만 알린다.
    # 알림을 꺼둔 상태에서도 기준선은 잡아야 한다 — 나중에 켰을 때 지난 구간이 쏟아지면 안 된다.
    $priming = -not $script:NotifyPrimed

    foreach ($row in $script:Limits) {
        $state = if ($script:NotifyState.ContainsKey($row.Key)) { $script:NotifyState[$row.Key] } else { $null }

        # 리셋 시각이 바뀌면 새 윈도우다. 발화 이력을 비워 같은 임계치를 다시 알릴 수 있게 한다.
        if (-not $state -or $state.Window -ne $row.Window) {
            $state = @{ Window = $row.Window; Fired = @() }
            $script:NotifyState[$row.Key] = $state
        }

        $crossed = @($script:Config.thresholds |
            Where-Object { $row.Percent -ge $_ -and $state.Fired -notcontains $_ })
        if ($crossed.Count -eq 0) { continue }

        if ($priming) {
            # 알리지 않고 발화 처리만 한다.
            $state.Fired = @($state.Fired + $crossed)
            continue
        }

        if (-not $script:Config.notifyEnabled) { continue }

        # 40%에서 75%로 한 번에 뛰면 50과 70이 동시에 걸린다. 풍선은 가장 높은 것 하나만 띄우고
        # 나머지도 발화 처리해 뒤늦은 중복 알림을 막는다.
        $highest = ($crossed | Measure-Object -Maximum).Maximum
        $state.Fired = @($state.Fired + $crossed)

        $icon = if ($highest -ge 90) {
            [System.Windows.Forms.ToolTipIcon]::Error
        } else {
            [System.Windows.Forms.ToolTipIcon]::Warning
        }
        $script:NotifyIcon.ShowBalloonTip(
            10000,
            "$($script:AppTitle) — $($row.Label) $highest% 초과",
            ("현재 {0}% · {1}" -f [int][Math]::Round($row.Percent), (Format-Countdown $row.ResetsAt)),
            $icon)
    }

    if ($priming) { $script:NotifyPrimed = $true }

    # 사라진 한도의 이력도 그대로 둔다. 한도 종류는 몇 개뿐이라 쌓이지 않고, 지웠다가 그 한도가
    # 다시 나타나면 같은 구간을 또 알리게 된다(각 이력은 리셋 시각으로 이미 구분된다).
}


