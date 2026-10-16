# Hotkey.ps1 - hotkey parsing, registration, and the settings dialog
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


# "Ctrl+Alt+U" 같은 문자열을 RegisterHotKey가 받는 수정자 비트와 가상 키로 바꾼다.
# 전역 단축키는 수정자가 하나도 없으면 다른 프로그램의 일반 타이핑을 가로채므로 최소 하나를 요구한다.
function ConvertFrom-HotkeyString([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $modifiers = 0
    $keyName = $null
    foreach ($token in ($text -split '\+')) {
        $token = $token.Trim()
        if (-not $token) { continue }
        $lower = $token.ToLowerInvariant()
        if ($script:HotkeyModifier.ContainsKey($lower)) {
            $modifiers = $modifiers -bor $script:HotkeyModifier[$lower]
        }
        elseif ($keyName) { return $null }   # 키가 두 개면 해석할 수 없다
        else { $keyName = $token }
    }
    if ($modifiers -eq 0 -or -not $keyName) { return $null }

    # Enum.Parse는 "5"나 "A,B" 같은 입력도 받아들인다. 정의된 이름과의 정확한 일치만 허용한다.
    $matched = [System.Enum]::GetNames([System.Windows.Forms.Keys]) |
        Where-Object { $_ -ieq $keyName } | Select-Object -First 1
    if (-not $matched) { return $null }

    $key = [System.Windows.Forms.Keys]$matched

    # 수정자 자체를 주 키로 쓸 수는 없다(Keys.Control 등은 키가 아니라 플래그다).
    $notAKey = @(
        [System.Windows.Forms.Keys]::None,       [System.Windows.Forms.Keys]::ControlKey,
        [System.Windows.Forms.Keys]::Menu,       [System.Windows.Forms.Keys]::ShiftKey,
        [System.Windows.Forms.Keys]::LWin,       [System.Windows.Forms.Keys]::RWin,
        [System.Windows.Forms.Keys]::Control,    [System.Windows.Forms.Keys]::Alt,
        [System.Windows.Forms.Keys]::Shift,      [System.Windows.Forms.Keys]::Modifiers,
        [System.Windows.Forms.Keys]::LControlKey, [System.Windows.Forms.Keys]::RControlKey,
        [System.Windows.Forms.Keys]::LShiftKey,  [System.Windows.Forms.Keys]::RShiftKey,
        [System.Windows.Forms.Keys]::LMenu,      [System.Windows.Forms.Keys]::RMenu
    )
    if ($notAKey -contains $key) { return $null }

    return @{
        Modifiers = [uint32]$modifiers
        Key       = $key
        Text      = Format-HotkeyText $modifiers $key
    }
}

function Format-HotkeyText([int]$modifiers, $key) {
    $parts = @()
    if ($modifiers -band 0x2) { $parts += 'Ctrl' }
    if ($modifiers -band 0x1) { $parts += 'Alt' }
    if ($modifiers -band 0x4) { $parts += 'Shift' }
    if ($modifiers -band 0x8) { $parts += 'Win' }
    $parts += [string]$key
    return ($parts -join '+')
}

function Register-Hotkey([string]$text) {
    $parsed = ConvertFrom-HotkeyString $text
    if (-not $parsed) {
        $script:HotkeyError = "형식을 알 수 없음: $text"
        return $false
    }

    if ($script:HotkeySink.Register(($parsed.Modifiers -bor $script:HotkeyNoRepeat), [uint32]$parsed.Key)) {
        $script:HotkeyText = $parsed.Text
        $script:HotkeyError = ''
        return $true
    }

    # 다른 프로그램이 같은 조합을 먼저 잡고 있으면 실패한다. 조용히 넘기면 사용자는 왜 안 되는지 알 수 없다.
    $script:HotkeyText = $parsed.Text
    $script:HotkeyError = '다른 프로그램이 사용 중'
    return $false
}

function Get-HotkeyMenuLabel {
    if ($script:HotkeyError) { return "단축키 설정 ($($script:HotkeyText) — $($script:HotkeyError))" }
    if ($script:HotkeyText) { return "단축키 설정 ($($script:HotkeyText))" }
    return '단축키 설정'
}



function Show-HotkeyDialog {
    $script:HotkeyDraft = $script:HotkeyText

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text            = '단축키 설정'
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dialog.MaximizeBox     = $false
    $dialog.MinimizeBox     = $false
    $dialog.ShowInTaskbar   = $false
    $dialog.ClientSize      = New-Object System.Drawing.Size((Get-Px 320), (Get-Px 150))
    # 키를 컨트롤이 먼저 삼키지 않도록 폼에서 먼저 받는다.
    $dialog.KeyPreview      = $true

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text     = "위젯을 열고 닫을 조합을 지금 눌러주세요.`nCtrl · Alt · Shift · Win 중 하나 이상이 포함돼야 합니다."
    $hint.Location = New-Object System.Drawing.Point((Get-Px 14), (Get-Px 12))
    $hint.Size     = New-Object System.Drawing.Size((Get-Px 292), (Get-Px 40))
    $hint.Font     = Get-CachedFont 9 ([System.Drawing.FontStyle]::Regular)
    $dialog.Controls.Add($hint)

    $capture = New-Object System.Windows.Forms.Label
    $capture.Text        = $script:HotkeyDraft
    $capture.TextAlign   = [System.Drawing.ContentAlignment]::MiddleCenter
    $capture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $capture.Location    = New-Object System.Drawing.Point((Get-Px 14), (Get-Px 58))
    $capture.Size        = New-Object System.Drawing.Size((Get-Px 292), (Get-Px 32))
    $capture.Font        = Get-CachedFont 11 ([System.Drawing.FontStyle]::Bold)
    $dialog.Controls.Add($capture)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text     = '확인'
    $ok.Location = New-Object System.Drawing.Point((Get-Px 128), (Get-Px 104))
    $ok.Size     = New-Object System.Drawing.Size((Get-Px 84), (Get-Px 28))
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text         = '취소'
    $cancel.Location     = New-Object System.Drawing.Point((Get-Px 222), (Get-Px 104))
    $cancel.Size         = New-Object System.Drawing.Size((Get-Px 84), (Get-Px 28))
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)
    $dialog.CancelButton = $cancel

    $dialog.Add_KeyDown({
        param($sender, $e)

        # 수정자 키만 눌린 상태는 아직 조합이 아니다.
        $bare = @(
            [System.Windows.Forms.Keys]::ControlKey, [System.Windows.Forms.Keys]::Menu,
            [System.Windows.Forms.Keys]::ShiftKey,   [System.Windows.Forms.Keys]::LWin,
            [System.Windows.Forms.Keys]::RWin
        )
        if ($bare -contains $e.KeyCode) { return }

        # 수정자가 없으면 대화상자 조작(Enter/Esc/Tab)으로 그냥 흘려보낸다.
        if ($e.Modifiers -eq [System.Windows.Forms.Keys]::None) { return }

        $modifiers = 0
        if ($e.Control) { $modifiers = $modifiers -bor 0x2 }
        if ($e.Alt)     { $modifiers = $modifiers -bor 0x1 }
        if ($e.Shift)   { $modifiers = $modifiers -bor 0x4 }

        $script:HotkeyDraft = Format-HotkeyText $modifiers $e.KeyCode
        $capture.Text = $script:HotkeyDraft
        $e.SuppressKeyPress = $true
        $e.Handled = $true
    })

    $ok.Add_Click({
        if (-not (ConvertFrom-HotkeyString $script:HotkeyDraft)) {
            [System.Windows.Forms.MessageBox]::Show(
                '조합을 먼저 눌러주세요. 수정자(Ctrl·Alt·Shift·Win)가 하나 이상 필요합니다.',
                '단축키 설정') | Out-Null
            return
        }

        # 이전 등록을 되돌릴 수 있어야 하므로 실패 시 원래 조합으로 복구한다.
        $previous = $script:HotkeyText
        if (Register-Hotkey $script:HotkeyDraft) {
            $script:Config.hotkey = $script:HotkeyText
            Export-Config
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
            return
        }

        [System.Windows.Forms.MessageBox]::Show(
            "$($script:HotkeyDraft) 는 다른 프로그램이 사용 중입니다. 다른 조합을 눌러주세요.",
            '단축키 설정') | Out-Null
        [void](Register-Hotkey $previous)
    })

    [void]$dialog.ShowDialog()
    $dialog.Dispose()
}


