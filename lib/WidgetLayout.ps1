# WidgetLayout.ps1 - what the widget draws: labels, bars, rows, layout
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

# 세션 전용 큰 행. 퍼센트를 크게, 그 옆에 남은 시간과 초기화 시각을 두 줄로 붙인다.
# labelWide를 따로 받는 이유는 첫 줄 오른쪽에 닫기 버튼이 앉기 때문이다.
function Add-WidgetHeroRow($form, $row, [int]$margin, [int]$innerWide, [int]$labelWide, [int]$y) {
    $percent = [int][Math]::Round($row.Percent)
    $color   = $script:SeverityColor[$row.Severity]

    $form.Controls.Add((New-WidgetLabel $row.Label $margin $y $labelWide 9 $script:ColorBright))
    $y += Get-Px 18

    $bigWide = Get-Px 104
    $big = New-WidgetLabel "$percent%" $margin $y $bigWide 24 $color
    $big.Size = New-Object System.Drawing.Size($bigWide, (Get-Px 42))
    $form.Controls.Add($big)

    # 남은 시간은 퍼센트·주 값과 다른 색으로 둔다. 세션에서 가장 자주 보는 숫자라 구분돼야 한다.
    $sideX    = $margin + $bigWide
    $sideWide = $innerWide - $bigWide
    $form.Controls.Add((New-WidgetLabel (Format-Countdown $row.ResetsAt '남음') `
        $sideX ($y + (Get-Px 4)) $sideWide 11.5 $script:ColorTime))

    $absolute = if ($row.ResetsAt) { "{0:HH:mm} 초기화" -f $row.ResetsAt } else { '' }
    $form.Controls.Add((New-WidgetLabel $absolute `
        $sideX ($y + (Get-Px 25)) $sideWide 9 $script:ColorBright))
    $y += Get-Px 44

    $form.Controls.Add((New-WidgetBar $margin $y $innerWide (Get-Px 10) $row.Percent $color))
    return $y + (Get-Px 10) + (Get-Px 14)
}

# 주간 등 보조 행. 기존 크기를 그대로 유지한다.
function Add-WidgetCompactRow($form, $row, [int]$margin, [int]$innerWide, [int]$barHeight, [int]$y) {
    $percent = [int][Math]::Round($row.Percent)

    # 이름은 흰색, 퍼센트는 등급색이라 라벨을 둘로 나눈다. 퍼센트는 오른쪽 끝에 맞춰
    # 이름 길이가 달라져도 자리가 흔들리지 않게 한다.
    $nameWide = Get-Px 150
    $form.Controls.Add((New-WidgetLabel $row.Label $margin $y $nameWide 9 $script:ColorBright))

    $value = New-WidgetLabel "$percent%" ($margin + $nameWide) $y ($innerWide - $nameWide) 9 `
        $script:SeverityColor[$row.Severity]
    $value.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $form.Controls.Add($value)
    $y += Get-Px 19

    $form.Controls.Add((New-WidgetBar $margin $y $innerWide $barHeight $row.Percent `
        $script:SeverityColor[$row.Severity]))
    $y += $barHeight + (Get-Px 5)

    $reset = Format-Countdown $row.ResetsAt
    # 날짜 형식의 '/'는 리터럴이 아니라 문화권의 날짜 구분자 자리표시자다. 한국어 문화권에서는
    # '-'로 치환되므로, 슬래시로 보이게 하려면 따옴표로 감싸 리터럴임을 명시해야 한다.
    if ($row.ResetsAt) { $reset += "  ({0:M'/'d HH:mm})" -f $row.ResetsAt }
    $form.Controls.Add((New-WidgetLabel $reset $margin $y $innerWide 9 $script:ColorBright))
    return $y + (Get-Px 23)
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
    $bright    = $script:ColorBright
    $y         = Get-Px 12

    # 제목 줄도 갱신 시각 줄도 두지 않는다. 갱신 시각은 트레이 메뉴에서 확인한다.
    $firstRowWide = $innerWide - $closeSize - (Get-Px 4)
    $form.Controls.Add((New-WidgetCloseButton ($form.Width - $margin - $closeSize) (Get-Px 8) $closeSize))

    # 첫 줄에서 닫기 버튼을 비켜야 하는 라벨의 폭. 실패 사유가 첫 줄을 차지하면 그 아래는 전체 폭을 쓴다.
    $topRowWide = $firstRowWide

    $failed = ($script:Status -ne 'ok' -and $script:Status -ne 'init')
    if ($failed) {
        # 갱신이 멈췄다는 것은 화면의 값이 낡았다는 뜻이므로 맨 위에 붉게 세운다.
        # 사유는 위젯 폭보다 길어 두 줄 높이를 준다. 폭은 닫기 버튼 자리를 뺀 값을 유지해야 한다 —
        # 전체 폭으로 넓히면 첫 줄이 버튼 아래로 파고든다.
        $reason = New-WidgetLabel $script:StatusText $margin $y $topRowWide 9 $script:SeverityColor[3]
        $reason.Size = New-Object System.Drawing.Size($topRowWide, (Get-Px 34))
        $form.Controls.Add($reason)
        $y += Get-Px 36
        $topRowWide = $innerWide
    }

    # 아직 받아온 값이 없을 때만 상태를 본문에 쓴다. 실패 상태는 위에서 이미 붉게 알렸으므로
    # 여기서 또 쓰면 같은 문구가 두 번 나온다.
    if ($script:Limits.Count -eq 0 -and -not $failed) {
        $form.Controls.Add((New-WidgetLabel $script:StatusText $margin $y $innerWide 9 $bright))
        $y += Get-Px 30
    }
    else {
        # 세션은 매일 체감되는 값이라 크게 세운다. 남은 시간이 바로 읽혀야 "앞으로 어떻게 쓸지"를
        # 판단할 수 있다. 주간은 하루 단위로 천천히 움직이므로 보조 크기로 둔다.
        $session = $script:Limits | Where-Object { $_.Key -eq 'session' } | Select-Object -First 1
        $rest    = @($script:Limits | Where-Object { $_.Key -ne 'session' })

        # 세션만 보고 싶을 때는 나머지를 접는다. 알림과 툴팁은 그대로 유지되므로
        # 접어둔 한도가 임계치를 넘으면 여전히 알려준다.
        $folded = @()
        if ($session -and -not $script:Config.showWeekly) {
            $folded = $rest
            $rest = @()
        }

        if ($session) {
            $y = Add-WidgetHeroRow $form $session $margin $innerWide $topRowWide $y
            if ($rest.Count -gt 0) {
                $line = New-Object System.Windows.Forms.Panel
                $line.Location  = New-Object System.Drawing.Point($margin, $y)
                $line.Size      = New-Object System.Drawing.Size($innerWide, 1)
                $line.BackColor = [System.Drawing.Color]::FromArgb(52, 56, 63)
                Set-DragHandlers $line
                $form.Controls.Add($line)
                $y += Get-Px 13
            }
        }

        foreach ($row in $rest) {
            $y = Add-WidgetCompactRow $form $row $margin $innerWide $barHeight $y
        }

        # 접어둔 한도는 게이지 없이 한 줄 요약만 남긴다. 안 보인다고 없는 것이 아니므로
        # 퍼센트와 갱신 시점은 알려줘야 한다.
        # 적색은 갱신 실패에만 쓴다. 정상 상태의 요약을 붉게 두면 그 신호가 흐려진다.
        foreach ($row in $folded) {
            # 한도와 시간을 다른 색으로 보여야 하므로 라벨을 둘로 나눈다. 색이 이미 둘을 갈라주니
            # 가운데 구분 기호는 두지 않는다.
            $head = "{0} {1}%" -f $row.Label, [int][Math]::Round($row.Percent)
            $tail = Format-Countdown $row.ResetsAt
            if ($row.ResetsAt) { $tail += "({0:M'/'d})" -f $row.ResetsAt }
            $tail += ' 갱신'

            # 나뉘어도 한 줄이어야 한다. 넘치면 WinForms가 한국어를 문자 단위로 접어 "갱 / 신"처럼
            # 끊거나 한 줄 높이에 걸려 뒤가 잘린다. 두 조각의 합을 재서 들어가는 크기까지 함께 낮춘다.
            # 폭을 재는 방식이 Label이 실제로 요구하는 폭보다 작으면, 라벨이 좁아진 만큼 끝 글자('%')가
            # 둘째 줄로 밀리고 한 줄 높이에 걸려 잘린다. "주간 57%"를 9pt Bold로 실측한 값:
            #
            #   Label.GetPreferredSize            88px  <- 컨트롤이 요구하는 폭
            #   MeasureString GenericTypographic  79px  <- 여백을 제거해 부족하다
            #   MeasureString GenericDefault      88px
            #   TextRenderer.MeasureText          90px  <- 여유를 두고 넉넉하다
            #
            # GenericTypographic은 글자 좌우 여백을 빼고 재기 때문에 Label 레이아웃과 맞지 않는다.
            # TextRenderer 쪽이 항상 같거나 크게 나오므로 이걸 쓴다.
            $gap  = Get-Px 6
            $size = 9.0
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
            # 최소 크기에서도 넘치는 극단적인 경우엔 잘리는 대신 말줄임으로 끝낸다.
            $note.AutoEllipsis = $true
            $form.Controls.Add($note)
            $y += Get-Px 21
        }
    }

    $y += Get-Px 6

    $form.Height = $y
    $form.ResumeLayout()
}

