# Menu.ps1 - the tray context menu
#
# Top-level code, not a function: it builds $menu, which the entry script assigns to
# the tray icon right after dot-sourcing this file. So the dot-source position matters
# here, unlike the other lib files which only define functions.
# The $menuXxx variables stay reachable from the Add_Opening handler that reads them.

function Invoke-ToggleServiceHide([string]$configKey) {
    $currentlyHidden = [bool]$script:Config.$configKey

    if (-not $currentlyHidden) {
        # 숨김으로 전환하려는 경우, 현재 표시 중인 서비스 수를 확인한다.
        $visibleCount = 0
        if (-not $script:Config.hideClaude) { $visibleCount++ }
        if (-not $script:Config.hideGemini) { $visibleCount++ }
        if (-not $script:Config.hideAgy)    { $visibleCount++ }

        if ($visibleCount -le 1) {
            $script:NotifyIcon.ShowBalloonTip(
                6000,
                "$($script:AppTitle) — 숨김 불가",
                "최소 하나의 서비스는 모니터링해야 합니다.`n다른 서비스의 숨김을 먼저 해제한 뒤 다시 시도해 주세요.",
                [System.Windows.Forms.ToolTipIcon]::Warning)
            return
        }
    }

    $script:Config.$configKey = (-not $currentlyHidden)
    Export-Config

    # 숨김을 해제한 경우 즉시 최신 데이터를 가져오도록 유도한다.
    if (-not $script:Config.$configKey) {
        if ($configKey -eq 'hideAgy')    { Update-AgyUsage }
        if ($configKey -eq 'hideGemini') { Update-GeminiUsage }
        if ($configKey -eq 'hideClaude') { $script:ForceFetch = $true }
    }

    Sync-CombinedState
    Invoke-Tick
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip

# 갱신 시각은 위젯에 상시 표시하지 않는다. 메뉴를 열 때 이 항목 라벨에만 붙여 보여준다.
$menuRefresh = $menu.Items.Add('지금 갱신')
$menuRefresh.Add_Click({
    # 요청 제한 중에는 누른 만큼 요청이 나가 차단이 연장된다. 누르는 것을 막고 이유를 알린다.
    if (-not $script:Config.hideClaude -and $script:ClaudeStatus -eq 'ratelimited' -and $script:Backoff -gt 0) {
        $script:NotifyIcon.ShowBalloonTip(
            8000,
            "$($script:AppTitle) — Claude 요청 제한 중",
            ("Claude 서버가 요청을 제한하고 있습니다. 약 {0}분 뒤 자동으로 다시 시도합니다.`nGemini와 AGY 사용량만 먼저 갱신합니다." -f `
                [int][Math]::Ceiling($script:Backoff / 60)),
            [System.Windows.Forms.ToolTipIcon]::Warning)
        if (-not $script:Config.hideAgy)    { Update-AgyUsage }
        if (-not $script:Config.hideGemini) { Update-GeminiUsage }
        Sync-CombinedState
        Invoke-Tick
        return
    }

    $script:Backoff    = 0
    $script:ForceFetch = $true
    Invoke-Tick
})

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

$menuRefreshToken = $menu.Items.Add('Claude 토큰 갱신 시도 (소량 소모)')
$menuRefreshToken.Add_Click({
    if (Invoke-TokenRefresh -Manual) {
        $script:NotifyIcon.ShowBalloonTip(
            6000,
            "$($script:AppTitle) — Claude 토큰 갱신 시도",
            "claude를 짧게 실행했습니다. 10초쯤 뒤 자동으로 다시 조회합니다.",
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
    else {
        $script:NotifyIcon.ShowBalloonTip(
            6000,
            "$($script:AppTitle) — 갱신할 수 없습니다",
            $script:ClaudeStatusText,
            [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})

$menuAutoRefresh = New-Object System.Windows.Forms.ToolStripMenuItem('Claude 토큰 만료 시 자동 갱신')
$menuAutoRefresh.Add_Click({
    $script:Config.autoRefreshToken = -not $script:Config.autoRefreshToken
    Export-Config
    if ($script:Config.autoRefreshToken) {
        $script:NotifyIcon.ShowBalloonTip(
            8000,
            "$($script:AppTitle) — 자동 갱신 켜짐",
            ("Claude 토큰이 만료되면 claude를 대신 실행합니다.`n회당 약 10초, 사용량을 소량 씁니다. 최소 간격 {0}분." -f `
                [int]$script:Config.refreshCooldownMinutes),
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
})
[void]$menu.Items.Add($menuAutoRefresh)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# 표시 옵션 묶음
$menuWidget = New-Object System.Windows.Forms.ToolStripMenuItem('위젯 표시')
$menuWidget.CheckOnClick = $false
$menuWidget.Add_Click({
    if ($script:WidgetForm -and $script:WidgetForm.Visible) { Hide-Widget } else { Show-Widget }
})
[void]$menu.Items.Add($menuWidget)

$menuWeekly = New-Object System.Windows.Forms.ToolStripMenuItem('보조 한도(주간·Flash) 상세 표시')
$menuWeekly.Add_Click({
    $script:Config.showWeekly = -not $script:Config.showWeekly
    Export-Config
    # 다음 틱을 기다리지 않고 즉시 다시 그린다.
    Update-Widget
})
[void]$menu.Items.Add($menuWeekly)

$menuHotkey = New-Object System.Windows.Forms.ToolStripMenuItem('단축키 설정')
$menuHotkey.Add_Click({ Show-HotkeyDialog })
[void]$menu.Items.Add($menuHotkey)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# 서비스별 숨김 토글 묶음 (최소 1개 서비스는 표시 유지)
$menuHideClaude = New-Object System.Windows.Forms.ToolStripMenuItem('클로드 숨김')
$menuHideClaude.CheckOnClick = $false
$menuHideClaude.Add_Click({ Invoke-ToggleServiceHide 'hideClaude' })
[void]$menu.Items.Add($menuHideClaude)

$menuHideGemini = New-Object System.Windows.Forms.ToolStripMenuItem('제미나이 숨김')
$menuHideGemini.CheckOnClick = $false
$menuHideGemini.Add_Click({ Invoke-ToggleServiceHide 'hideGemini' })
[void]$menu.Items.Add($menuHideGemini)

$menuHideAgy = New-Object System.Windows.Forms.ToolStripMenuItem('AGY 숨김')
$menuHideAgy.CheckOnClick = $false
$menuHideAgy.Add_Click({ Invoke-ToggleServiceHide 'hideAgy' })
[void]$menu.Items.Add($menuHideAgy)

[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

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
    $menuWidget.Checked      = ($script:WidgetForm -and $script:WidgetForm.Visible)
    $menuAutoRefresh.Checked = [bool]$script:Config.autoRefreshToken
    $menuWeekly.Checked      = [bool]$script:Config.showWeekly
    $menuHideClaude.Checked  = [bool]$script:Config.hideClaude
    $menuHideGemini.Checked  = [bool]$script:Config.hideGemini
    $menuHideAgy.Checked     = [bool]$script:Config.hideAgy
    $menuAutostart.Checked   = Test-Autostart
    # 현재 조합과 등록 실패 여부를 메뉴에 그대로 보여준다. 안 보이면 왜 안 먹는지 알 수 없다.
    $menuHotkey.Text         = Get-HotkeyMenuLabel
})
