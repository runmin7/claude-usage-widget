# WidgetLayout.ps1 - what the widget draws: labels, bars, rows, layout (Claude / Gemini / AGY)
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.

# 얇은 글씨가 섞이지 않게 하기 위해서다(어두운 배경에서 얇은 글씨는 읽기 어렵다).
function New-WidgetLabel([string]$text, [int]$x, [int]$y, [int]$width, [double]$fontSize, $color) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text      = $text
    $label.AutoSize  = $false
    $label.Location  = New-Object System.Drawing.Point($x, $y)
    $label.Size      = New-Object System.Drawing.Size($width, (Get-Px ($fontSize * 1.9)))
    $label.ForeColor = $color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.Font      = Get-CachedFont $fontSize ([System.Drawing.FontStyle]::Bold)
    Set-DragHandlers $label
    return $label
}

function New-WidgetCloseButton([int]$x, [int]$y, [int]$size) {
    $button = New-Object System.Windows.Forms.Label
    $button.Text      = '✕'
    $button.AutoSize  = $false
    $button.Location  = New-Object System.Drawing.Point($x, $y)
    $button.Size      = New-Object System.Drawing.Size($size, $size)
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.ForeColor = $script:ColorBright
    $button.BackColor = [System.Drawing.Color]::Transparent
    $button.Font      = Get-CachedFont 10 ([System.Drawing.FontStyle]::Bold)
    $button.Cursor    = [System.Windows.Forms.Cursors]::Hand

    # 드래그 핸들러는 붙이지 않는다. 클릭이 드래그로 먹혀 닫히지 않는다.
    # 회색을 쓸 수 없으니 호버 표시는 밝기 대신 강조색으로 준다.
    $button.Add_Click({ Hide-Widget })
    $button.Add_MouseEnter({ $this.ForeColor = $script:ColorTime })
    $button.Add_MouseLeave({ $this.ForeColor = $script:ColorBright })
    return $button
}

function New-WidgetBar($x, $y, $width, $height, [double]$percent, $color) {
    $track = New-Object System.Windows.Forms.Panel
    $track.Location  = New-Object System.Drawing.Point($x, $y)
    $track.Size      = New-Object System.Drawing.Size($width, $height)
    $track.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 64)
    Set-DragHandlers $track

    $filled = [int]([Math]::Max(2, [Math]::Min(100, $percent) / 100.0 * $width))
    $fill = New-Object System.Windows.Forms.Panel
    $fill.Location  = New-Object System.Drawing.Point(0, 0)
    $fill.Size      = New-Object System.Drawing.Size($filled, $height)
    $fill.BackColor = $color
    $track.Controls.Add($fill)
    return $track
}

function Add-WidgetDivider($form, [int]$margin, [int]$innerWide, [int]$y) {
    $line = New-Object System.Windows.Forms.Panel
    $line.Location  = New-Object System.Drawing.Point($margin, $y)
    $line.Size      = New-Object System.Drawing.Size($innerWide, 1)
    $line.BackColor = [System.Drawing.Color]::FromArgb(52, 56, 63)
    Set-DragHandlers $line
    $form.Controls.Add($line)
    return $y + (Get-Px 9)
}

function Add-WidgetSectionHeader($form, [string]$provider, [int]$margin, [int]$headerWide, [int]$y) {
    $title = $script:ProviderTitle[$provider]
    $color = $script:ProviderColor[$provider]
    $hdr   = New-WidgetLabel "■ $title" $margin $y $headerWide 9.5 $color
    $form.Controls.Add($hdr)
    return $y + (Get-Px 20)
}

function Add-WidgetCompactRow($form, $row, [int]$margin, [int]$innerWide, [int]$barHeight, [int]$y) {
    $percent = [int][Math]::Round($row.Percent)

    # 이름은 흰색, 퍼센트는 등급색이라 라벨을 둘로 나눈다. 퍼센트는 오른쪽 끝에 맞춰
    # 이름 길이가 달라져도 자리가 흔들리지 않게 한다.
    $nameWide = Get-Px 190
    $form.Controls.Add((New-WidgetLabel $row.Label $margin $y $nameWide 9 $script:ColorBright))

    $value = New-WidgetLabel "$percent%" ($margin + $nameWide) $y ($innerWide - $nameWide) 9 `
        $script:SeverityColor[$row.Severity]
    $value.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $form.Controls.Add($value)
    $y += Get-Px 18

    $form.Controls.Add((New-WidgetBar $margin $y $innerWide $barHeight $row.Percent `
        $script:SeverityColor[$row.Severity]))
    $y += $barHeight + (Get-Px 4)

    $detailColor = $script:ColorBright
    if ($row.DetailText) {
        $reset = $row.DetailText
        $detailColor = $script:ColorTime
    }
    else {
        $reset = Format-Countdown $row.ResetsAt
        if ($row.ResetsAt) {
            if ($row.Key -eq 'session' -or $row.Provider -eq 'gemini') {
                $reset += "  ({0:HH:mm} 초기화)" -f $row.ResetsAt
                $detailColor = $script:ColorTime
            }
            elseif ($row.Provider -eq 'agy') {
                $reset += "  ({0:M'/'d HH:mm} 초기화)" -f $row.ResetsAt
                $detailColor = $script:ColorTime
            }
            else {
                $reset += "  ({0:M'/'d HH:mm})" -f $row.ResetsAt
            }
        }
    }

    $form.Controls.Add((New-WidgetLabel $reset $margin $y $innerWide 8.5 $detailColor))
    return $y + (Get-Px 21)
}

function Add-WidgetFoldedRow($form, $row, [int]$margin, [int]$innerWide, [int]$y) {
    $head = "{0} {1}%" -f $row.Label, [int][Math]::Round($row.Percent)
    if ($row.DetailText) {
        $tail = $row.DetailText
    }
    else {
        $tail = Format-Countdown $row.ResetsAt
        if ($row.ResetsAt) { $tail += "({0:M'/'d})" -f $row.ResetsAt }
        $tail += ' 갱신'
    }

    $gap  = Get-Px 6
    $size = 8.5
    $headWide = 0
    while ($true) {
        $font = Get-CachedFont $size ([System.Drawing.FontStyle]::Bold)
        $headWide = [System.Windows.Forms.TextRenderer]::MeasureText($head, $font).Width
        $tailWide = [System.Windows.Forms.TextRenderer]::MeasureText($tail, $font).Width
        if (($headWide + $gap + $tailWide) -le $innerWide -or $size -le 7.0) { break }
        $size -= 0.5
    }

    $form.Controls.Add((New-WidgetLabel $head $margin $y $headWide $size $script:ColorSummary))

    $tailX = $margin + $headWide + $gap
    $note = New-WidgetLabel $tail $tailX $y ($innerWide + $margin - $tailX) $size $script:ColorBright
    $note.AutoEllipsis = $true
    $form.Controls.Add($note)
    return $y + (Get-Px 19)
}

function Add-ProviderSection($form, [string]$provider, $rows, [string]$status, [string]$statusText,
    [string]$primaryKey, [int]$margin, [int]$innerWide, [int]$headerWide, [int]$barHeight, [int]$y) {

    $y = Add-WidgetSectionHeader $form $provider $margin $headerWide $y

    if ($status -ne 'ok' -and $status -ne 'init') {
        $errLabel = New-WidgetLabel $statusText $margin $y $innerWide 8.5 $script:SeverityColor[3]
        $form.Controls.Add($errLabel)
        $y += Get-Px 20
    }

    if (-not $rows -or $rows.Count -eq 0) {
        if ($status -eq 'init') {
            $form.Controls.Add((New-WidgetLabel '조회 중...' $margin $y $innerWide 8.5 $script:ColorBright))
            $y += Get-Px 20
        }
        return $y
    }

    if ($script:Config.showWeekly) {
        foreach ($r in $rows) {
            $y = Add-WidgetCompactRow $form $r $margin $innerWide $barHeight $y
        }
    }
    else {
        $primary = $rows | Where-Object { $_.Key -eq $primaryKey } | Select-Object -First 1
        if (-not $primary) { $primary = $rows[0] }
        $rest    = @($rows | Where-Object { $_.Key -ne $primary.Key })

        $y = Add-WidgetCompactRow $form $primary $margin $innerWide $barHeight $y
        foreach ($r in $rest) {
            $y = Add-WidgetFoldedRow $form $r $margin $innerWide $y
        }
    }

    return $y
}

function Update-Widget {
    if (-not $script:WidgetForm -or -not $script:WidgetForm.Visible) { return }

    $form = $script:WidgetForm
    $form.SuspendLayout()

    foreach ($child in @($form.Controls)) {
        $form.Controls.Remove($child)
        $child.Dispose()
    }

    $margin    = Get-Px 14
    $barHeight = Get-Px 6
    $closeSize = Get-Px 22
    $innerWide = $form.Width - ($margin * 2)
    $y         = Get-Px 10

    $firstHeaderWide = $innerWide - $closeSize - (Get-Px 4)
    $form.Controls.Add((New-WidgetCloseButton ($form.Width - $margin - $closeSize) (Get-Px 8) $closeSize))

    $sections = @()
    if (-not $script:Config.hideClaude) {
        $sections += @{
            Provider   = 'claude'
            Rows       = $script:ClaudeLimits
            Status     = $script:ClaudeStatus
            StatusText = $script:ClaudeStatusText
            PrimaryKey = 'session'
        }
    }
    if (-not $script:Config.hideGemini) {
        $sections += @{
            Provider   = 'gemini'
            Rows       = $script:GeminiLimits
            Status     = $script:GeminiStatus
            StatusText = $script:GeminiStatusText
            PrimaryKey = 'gemini_pro'
        }
    }
    if (-not $script:Config.hideAgy) {
        $sections += @{
            Provider   = 'agy'
            Rows       = $script:AgyLimits
            Status     = $script:AgyStatus
            StatusText = $script:AgyStatusText
            PrimaryKey = 'agy_weekly'
        }
    }

    for ($i = 0; $i -lt $sections.Count; $i++) {
        if ($i -gt 0) {
            $y = Add-WidgetDivider $form $margin $innerWide $y
        }
        $sec = $sections[$i]
        $hdrWide = if ($i -eq 0) { $firstHeaderWide } else { $innerWide }
        $y = Add-ProviderSection $form $sec.Provider $sec.Rows $sec.Status $sec.StatusText `
            $sec.PrimaryKey $margin $innerWide $hdrWide $barHeight $y
    }

    $y += Get-Px 6

    $form.Height = $y
    $form.ResumeLayout()
}
