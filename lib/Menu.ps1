# Menu.ps1 - the tray context menu
#
# Top-level code, not a function: it builds $menu, which the entry script assigns to
# the tray icon right after dot-sourcing this file. So the dot-source position matters
# here, unlike the other lib files which only define functions.
# The $menuXxx variables stay reachable from the Add_Opening handler that reads them.

$menu = New-Object System.Windows.Forms.ContextMenuStrip

# 갱신 시각은 위젯에 상시 표시하지 않는다. 메뉴를 열 때 이 항목 라벨에만 붙여 보여준다.
$menuRefresh = $menu.Items.Add('지금 갱신')
$menuRefresh.Add_Click({
    # 요청 제한 중에는 누른 만큼 요청이 나가 차단이 연장된다. 누르는 것을 막고 이유를 알린다.
    if ($script:Status -eq 'ratelimited' -and $script:Backoff -gt 0) {
        $script:NotifyIcon.ShowBalloonTip(
            8000,
            "$($script:AppTitle) — 지금은 갱신할 수 없습니다",
            ("서버가 요청을 제한하고 있습니다. 약 {0}분 뒤 자동으로 다시 시도합니다.`n지금 누르면 제한이 더 길어집니다." -f `
                [int][Math]::Ceiling($script:Backoff / 60)),
            [System.Windows.Forms.ToolTipIcon]::Warning)
        return
    }

    $script:Backoff    = 0
    $script:ForceFetch = $true
    Invoke-Tick
})

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuRefreshToken = $menu.Items.Add('토큰 갱신 시도 (사용량 소량 소모)')
$menuRefreshToken.Add_Click({
    if (Invoke-TokenRefresh -Manual) {
        $script:NotifyIcon.ShowBalloonTip(
            6000,
            "$($script:AppTitle) — 토큰 갱신 시도",
            "claude를 짧게 실행했습니다. 10초쯤 뒤 자동으로 다시 조회합니다.",
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
    else {
        $script:NotifyIcon.ShowBalloonTip(
            6000,
            "$($script:AppTitle) — 갱신할 수 없습니다",
            $script:StatusText,
            [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})

$menuAutoRefresh = New-Object System.Windows.Forms.ToolStripMenuItem('토큰 만료 시 자동 갱신')
$menuAutoRefresh.Add_Click({
    $script:Config.autoRefreshToken = -not $script:Config.autoRefreshToken
    Export-Config
    if ($script:Config.autoRefreshToken) {
        $script:NotifyIcon.ShowBalloonTip(
            8000,
            "$($script:AppTitle) — 자동 갱신 켜짐",
            ("토큰이 만료되면 claude를 대신 실행합니다.`n회당 약 10초, 사용량을 소량 씁니다. 최소 간격 {0}분." -f `
                [int]$script:Config.refreshCooldownMinutes),
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
})
[void]$menu.Items.Add($menuAutoRefresh)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# 무엇을 보여줄지 정하는 항목들. 알림을 켜고 끄는 항목과 같은 묶음에 둔다.
$menuWidget = New-Object System.Windows.Forms.ToolStripMenuItem('위젯 표시')
$menuWidget.CheckOnClick = $false
$menuWidget.Add_Click({
    if ($script:WidgetForm -and $script:WidgetForm.Visible) { Hide-Widget } else { Show-Widget }
})
[void]$menu.Items.Add($menuWidget)

$menuWeekly = New-Object System.Windows.Forms.ToolStripMenuItem('주간 한도 함께 표시')
$menuWeekly.Add_Click({
    $script:Config.showWeekly = -not $script:Config.showWeekly
    Export-Config
    # 다음 틱을 기다리지 않고 즉시 다시 그린다.
    Update-Widget
})
[void]$menu.Items.Add($menuWeekly)

$menuNotify = New-Object System.Windows.Forms.ToolStripMenuItem('임계치 알림')
$menuNotify.Add_Click({
    $script:Config.notifyEnabled = -not $script:Config.notifyEnabled
    Export-Config
})
[void]$menu.Items.Add($menuNotify)

$menuHotkey = New-Object System.Windows.Forms.ToolStripMenuItem('단축키 설정')
$menuHotkey.Add_Click({ Show-HotkeyDialog })
[void]$menu.Items.Add($menuHotkey)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuGuide = $menu.Items.Add('사용 가이드')
$menuGuide.Add_Click({
    if (Test-Path $script:GuidePath) {
        # 기본 브라우저로 연다.
        Start-Process $script:GuidePath
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "가이드 파일을 찾을 수 없습니다.`n$($script:GuidePath)", $script:AppTitle) | Out-Null
    }
})

$menuAutostart = New-Object System.Windows.Forms.ToolStripMenuItem('로그온 시 자동 시작')
$menuAutostart.Add_Click({ Set-Autostart (-not (Test-Autostart)) })
[void]$menu.Items.Add($menuAutostart)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuExit = $menu.Items.Add('종료')
$menuExit.Add_Click({ Stop-App })

# 메뉴를 열 때마다 체크 표시를 실제 상태에 맞춘다.
$menu.Add_Opening({
    $menuRefresh.Text = if ($script:LastSuccess) {
        '지금 갱신 ({0:HH:mm:ss})' -f $script:LastSuccess
    } else {
        '지금 갱신 (갱신 없음)'
    }
    $menuWidget.Checked    = ($script:WidgetForm -and $script:WidgetForm.Visible)
    $menuAutoRefresh.Checked = [bool]$script:Config.autoRefreshToken
    $menuWeekly.Checked    = [bool]$script:Config.showWeekly
    $menuNotify.Checked    = [bool]$script:Config.notifyEnabled
    $menuAutostart.Checked = Test-Autostart
    # 현재 조합과 등록 실패 여부를 메뉴에 그대로 보여준다. 안 보이면 왜 안 먹는지 알 수 없다.
    $menuHotkey.Text       = Get-HotkeyMenuLabel
})
