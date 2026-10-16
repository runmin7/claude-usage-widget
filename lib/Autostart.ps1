# Autostart.ps1 - startup-folder shortcut
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


function Get-StartupShortcutPath {
    Join-Path ([Environment]::GetFolderPath('Startup')) $script:ShortcutName
}

function Test-Autostart { Test-Path (Get-StartupShortcutPath) }

function Set-Autostart([bool]$enabled) {
    $path = Get-StartupShortcutPath
    try {
        if ($enabled) {
            $shell = New-Object -ComObject WScript.Shell
            $link = $shell.CreateShortcut($path)
            # 콘솔 창이 뜨지 않도록 PowerShell을 직접 걸지 않고 런처를 경유한다.
            $link.TargetPath       = 'wscript.exe'
            $link.Arguments        = """$script:LauncherPath"""
            $link.WorkingDirectory = $script:ScriptDir
            $link.Description      = 'Claude 사용량 모니터'
            $link.Save()
        }
        elseif (Test-Path $path) {
            Remove-Item $path -Force
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "자동 시작 설정을 바꾸지 못했습니다.`n$($_.Exception.Message)",
            $script:AppTitle) | Out-Null
    }
}


