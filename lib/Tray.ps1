# Tray.ps1 - tray icon rendering and tooltip
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


function New-TrayIconObject([int]$severityRank, [bool]$stale) {
    # 트레이가 실제로 요구하는 크기로 그린다.
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    if ($size -lt 16) { $size = 16 } elseif ($size -gt 64) { $size = 64 }

    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $color = $script:SeverityColor[$severityRank]
        if ($stale) {
            # 모든 서비스 갱신이 멈춘 경우 색을 죽여 알린다.
            $color = [System.Drawing.Color]::FromArgb(120, 120, 120)
        }

        $brush = New-Object System.Drawing.SolidBrush($color)
        try { $graphics.FillRectangle($brush, 0, 0, $size, $size) }
        finally { $brush.Dispose() }

        # 3개 서비스(Claude · Gemini · AGY) 통합 모니터를 상징하는 3단 수평 게이지 바 아이콘을 그린다.
        $padX   = [Math]::Max(2, [int][Math]::Round($size * 0.18))
        $padY   = [Math]::Max(2, [int][Math]::Round($size * 0.20))
        $barW   = $size - ($padX * 2)
        $barH   = [Math]::Max(2, [int][Math]::Round($size * 0.13))
        $gapY   = [Math]::Max(1, [int][Math]::Round(($size - ($padY * 2) - ($barH * 3)) / 2.0))

        # 각 서비스의 대표 사용률(0.30~1.0 폭으로 상징 표현)
        $cRow = $script:ClaudeLimits | Where-Object { $_.Key -eq 'session' } | Select-Object -First 1
        $gRow = $script:GeminiLimits | Where-Object { $_.Key -eq 'gemini_pro' } | Select-Object -First 1
        $aRow = $script:AgyLimits    | Select-Object -First 1

        $r1 = if ($cRow) { [Math]::Max(0.30, [Math]::Min(1.0, $cRow.Percent / 100.0)) } else { 0.75 }
        $r2 = if ($gRow) { [Math]::Max(0.30, [Math]::Min(1.0, $gRow.Percent / 100.0)) } else { 0.55 }
        $r3 = if ($aRow) { [Math]::Max(0.30, [Math]::Min(1.0, $aRow.Percent / 100.0)) } else { 0.85 }
        $ratios = @($r1, $r2, $r3)
        $hiddenFlags = @(
            [bool]$script:Config.hideClaude,
            [bool]$script:Config.hideGemini,
            [bool]$script:Config.hideAgy
        )

        $trackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(95, 255, 255, 255))
        $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        try {
            for ($i = 0; $i -lt 3; $i++) {
                $y = $padY + $i * ($barH + $gapY)
                $graphics.FillRectangle($trackBrush, $padX, $y, $barW, $barH)
                if (-not $hiddenFlags[$i]) {
                    $fillW = [Math]::Max(2, [int][Math]::Round($barW * $ratios[$i]))
                    $graphics.FillRectangle($whiteBrush, $padX, $y, $fillW, $barH)
                }
            }
        }
        finally {
            $trackBrush.Dispose()
            $whiteBrush.Dispose()
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
    $severity = Get-OverallSeverity
    $anyOk    = ((-not $script:Config.hideClaude -and $script:ClaudeStatus -eq 'ok') -or
                 (-not $script:Config.hideGemini -and $script:GeminiStatus -eq 'ok') -or
                 (-not $script:Config.hideAgy    -and $script:AgyStatus    -eq 'ok'))
    $allInit  = (($script:Config.hideClaude -or $script:ClaudeStatus -eq 'init') -and
                 ($script:Config.hideGemini -or $script:GeminiStatus -eq 'init') -and
                 ($script:Config.hideAgy    -or $script:AgyStatus    -eq 'init'))
    $stale    = (-not $anyOk -and -not $allInit)

    $new = New-TrayIconObject $severity $stale
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

    # 1. Claude 요약 줄
    if (-not $script:Config.hideClaude) {
        if ($script:ClaudeLimits.Count -gt 0) {
            $c5 = $script:ClaudeLimits | Where-Object { $_.Key -eq 'session' } | Select-Object -First 1
            $c7 = $script:ClaudeLimits | Where-Object { $_.Key -eq 'weekly_all' } | Select-Object -First 1
            if ($c5 -and $c7) {
                $lines += ("Claude 5h:{0}% 7d:{1}%" -f [int][Math]::Round($c5.Percent), [int][Math]::Round($c7.Percent))
            }
            elseif ($c5) {
                $lines += ("Claude 5h:{0}%" -f [int][Math]::Round($c5.Percent))
            }
        }
        elseif ($script:ClaudeStatus -ne 'init') {
            $lines += "Claude: 확인 필요"
        }
    }

    # 2. Gemini 요약 줄
    if (-not $script:Config.hideGemini) {
        if ($script:GeminiLimits.Count -gt 0) {
            $gp = $script:GeminiLimits | Where-Object { $_.Key -eq 'gemini_pro' } | Select-Object -First 1
            $gf = $script:GeminiLimits | Where-Object { $_.Key -eq 'gemini_flash' } | Select-Object -First 1
            if ($gp -and $gf) {
                $lines += ("Gemini Pro:{0}% Fl:{1}%" -f [int][Math]::Round($gp.Percent), [int][Math]::Round($gf.Percent))
            }
            elseif ($gp) {
                $lines += ("Gemini Pro:{0}%" -f [int][Math]::Round($gp.Percent))
            }
        }
        elseif ($script:GeminiStatus -ne 'init') {
            $lines += "Gemini: 확인 필요"
        }
    }

    # 3. AGY 요약 줄
    if (-not $script:Config.hideAgy -and $script:AgyLimits.Count -gt 0) {
        $aw = $script:AgyLimits[0]
        $lines += ("AGY 7d:{0}%" -f [int][Math]::Round($aw.Percent))
    }

    if ($lines.Count -eq 0) { $lines += $script:StatusText }

    # 63자를 넘기면 예외가 난다. 줄 단위로 담다가 안 들어가는 줄은 버린다.
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
