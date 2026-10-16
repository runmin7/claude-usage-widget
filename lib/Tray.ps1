# Tray.ps1 - tray icon rendering and tooltip
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


function New-TrayIconObject([int]$percent, [int]$severityRank, [bool]$stale) {
    # 트레이가 실제로 요구하는 크기로 그린다. 16px 고정으로 그리면 고배율 화면에서 확대되어 숫자가 뭉갠다.
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    if ($size -lt 16) { $size = 16 } elseif ($size -gt 64) { $size = 64 }

    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $color = $script:SeverityColor[$severityRank]
        if ($stale) {
            # 갱신이 멈춘 값임을 색을 죽여 알린다.
            $color = [System.Drawing.Color]::FromArgb(120, 120, 120)
        }

        $brush = New-Object System.Drawing.SolidBrush($color)
        try { $graphics.FillRectangle($brush, 0, 0, $size, $size) }
        finally { $brush.Dispose() }

        $text = if ($percent -lt 0) { '-' } elseif ($percent -ge 100) { '!!' } else { [string]$percent }
        $ratio = switch ($text.Length) { 1 { 0.85 } 2 { 0.66 } default { 0.50 } }
        $pixels = [Math]::Max(6, [int][Math]::Round($size * $ratio))
        $font = New-Object System.Drawing.Font(
            'Segoe UI', $pixels, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment     = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        # NoWrap이 없으면 두 자리 숫자가 폭에 못 들어갈 때 두 줄로 감겨 한 자리만 보인다.
        $format.FormatFlags   = [System.Drawing.StringFormatFlags]::NoWrap
        $format.Trimming      = [System.Drawing.StringTrimming]::None
        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        try {
            $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
            $graphics.DrawString($text, $font, $white, $rect, $format)
        }
        finally {
            $white.Dispose(); $format.Dispose(); $font.Dispose()
        }
    }
    finally { $graphics.Dispose() }

    $handle = $bitmap.GetHicon()
    $bitmap.Dispose()
    return @{
        Icon   = [System.Drawing.Icon]::FromHandle($handle)
        Handle = $handle
    }
}

function Update-TrayIcon {
    $session = Get-SessionRow
    $percent  = if ($session) { [int][Math]::Round($session.Percent) } else { -1 }
    $severity = if ($session) { $session.Severity } else { 0 }
    $stale    = ($script:Status -ne 'ok' -and $script:Status -ne 'init')

    $new = New-TrayIconObject $percent $severity $stale
    $old = $script:CurrentIcon
    $script:NotifyIcon.Icon = $new.Icon
    $script:CurrentIcon = $new

    # 아이콘을 교체한 뒤에 이전 핸들을 해제해야 한다. 순서를 바꾸면 트레이가 깨진 아이콘을 그린다.
    if ($old) {
        $old.Icon.Dispose()
        [void][NativeUtil]::DestroyIcon($old.Handle)
    }
}

function Update-Tooltip {
    $lines = @()
    foreach ($row in $script:Limits) {
        $lines += "{0} {1}% · {2}" -f $row.Label, [int][Math]::Round($row.Percent), (Format-Countdown $row.ResetsAt)
    }
    if ($lines.Count -eq 0) { $lines += $script:StatusText }
    elseif ($script:Status -ne 'ok') { $lines += "! $($script:StatusText)" }

    # 63자를 넘기면 예외가 난다. 줄 단위로 담다가 안 들어가는 줄은 버린다.
    # 한 줄을 중간에서 자르면 오히려 읽을 수 없으니, 한도 순서(세션 → 주간 → 그 외)를 신뢰해 뒤를 포기한다.
    $kept = @()
    foreach ($line in $lines) {
        $candidate = @($kept + $line) -join "`n"
        if ($candidate.Length -gt $script:TooltipMaxLength) { break }
        $kept += $line
    }
    if ($kept.Count -eq 0) {
        $kept = @($lines[0].Substring(0, [Math]::Min($lines[0].Length, $script:TooltipMaxLength - 1)) + '…')
    }
    $script:NotifyIcon.Text = ($kept -join "`n")
}


