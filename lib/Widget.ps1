# Widget.ps1 - widget window: create, place, drag, show, hide
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


function Set-DragHandlers($control) {
    $control.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:DragOrigin = [System.Windows.Forms.Cursor]::Position
        }
    })
    $control.Add_MouseMove({
        param($sender, $e)
        if ($null -eq $script:DragOrigin) { return }
        $now = [System.Windows.Forms.Cursor]::Position
        $form = $script:WidgetForm
        $form.Location = New-Object System.Drawing.Point(
            ($form.Location.X + $now.X - $script:DragOrigin.X),
            ($form.Location.Y + $now.Y - $script:DragOrigin.Y))
        $script:DragOrigin = $now
    })
    $control.Add_MouseUp({
        param($sender, $e)
        if ($null -eq $script:DragOrigin) { return }
        $script:DragOrigin = $null
        $script:Config.widgetX = $script:WidgetForm.Location.X
        $script:Config.widgetY = $script:WidgetForm.Location.Y
        Export-Config
    })
}

function Initialize-Widget {
    if ($script:WidgetForm) { return }

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false
    $form.BackColor       = [System.Drawing.Color]::FromArgb(28, 30, 34)
    $form.Width           = Get-Px 284
    $form.Height          = Get-Px 280
    $form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $form.ContextMenuStrip = $script:NotifyIcon.ContextMenuStrip

    # 사용자가 X를 누를 수단이 없으므로 닫기 시도는 숨기기로 바꾼다(트레이는 계속 살아 있어야 한다).
    $form.Add_FormClosing({
        param($sender, $e)
        if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $e.Cancel = $true
            Hide-Widget
        }
    })

    Set-DragHandlers $form
    $script:WidgetForm = $form

    # 스타일을 바꾸려면 창 핸들이 있어야 한다. 아직 Show 전이라 여기서 강제로 만든다.
    [void]$form.Handle
    [void][NativeUtil]::HideFromAltTab($form.Handle)

    Restore-WidgetLocation
}

function Restore-WidgetLocation {
    $form = $script:WidgetForm
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $gap = Get-Px 24
    if ($null -ne $script:Config.widgetX -and $null -ne $script:Config.widgetY) {
        $x = [int]$script:Config.widgetX
        $y = [int]$script:Config.widgetY
    }
    else {
        $x = $bounds.Right - $form.Width - $gap
        $y = $bounds.Bottom - $form.Height - $gap
    }

    # 저장된 위치가 지금 모니터 구성에서 화면 밖이면 되돌린다.
    $visible = [System.Windows.Forms.Screen]::AllScreens |
        Where-Object { $_.WorkingArea.IntersectsWith(
            (New-Object System.Drawing.Rectangle($x, $y, $form.Width, $form.Height))) }
    if (-not $visible) {
        $x = $bounds.Right - $form.Width - $gap
        $y = $bounds.Bottom - $form.Height - $gap
    }

    $form.Location = New-Object System.Drawing.Point($x, $y)
}

function Get-CachedFont([double]$size, $style) {
    $key = "$size|$style"
    if (-not $script:FontCache.ContainsKey($key)) {
        $script:FontCache[$key] = New-Object System.Drawing.Font('Malgun Gothic', $size, $style)
    }
    return $script:FontCache[$key]
}

function Show-Widget {
    Initialize-Widget
    Update-Widget
    # 보일 때마다 좌표를 다시 검증한다. 위젯이 있던 모니터가 분리되면 화면 밖에 갇히기 때문이다.
    Restore-WidgetLocation
    $script:WidgetForm.Show()
    $script:WidgetForm.TopMost = $true
    $script:Config.widgetVisible = $true
    Export-Config
}

function Hide-Widget {
    if ($script:WidgetForm) { $script:WidgetForm.Hide() }
    $script:Config.widgetVisible = $false
    Export-Config
}
