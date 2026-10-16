# Stops the running monitor and starts it again through its real launcher.
#
# Use this after editing any file. It fixes the BOM first, because a missing BOM is the
# most common reason the program will not start after an edit.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Restart.ps1
#
# ASCII only.

$root = Split-Path $PSScriptRoot
$entry = Join-Path $root 'ClaudeUsageMonitor.ps1'
$launcher = Join-Path $root 'start.vbs'

& (Join-Path $PSScriptRoot 'Fix-Encoding.ps1') | Out-Null
'BOM checked'

# Match on "-File ...ClaudeUsageMonitor.ps1" and not just the file name: without the
# -File part, this command's own command line contains the name and it counts itself.
$running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*-File*ClaudeUsageMonitor.ps1*' })

foreach ($proc in $running) {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    "stopped pid $($proc.ProcessId)"
}
if ($running.Count -eq 0) { 'nothing was running' }

Start-Sleep -Seconds 2
Start-Process wscript.exe -ArgumentList ('"' + $launcher + '"')
Start-Sleep -Seconds 12

$now = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*-File*ClaudeUsageMonitor.ps1*' })

if ($now.Count -eq 1) {
    "started pid $($now[0].ProcessId)"
}
elseif ($now.Count -eq 0) {
    'FAILED to start -- run this to see the error:'
    "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$entry`""
}
else {
    "WARNING: $($now.Count) instances running: $(($now | ForEach-Object { $_.ProcessId }) -join ', ')"
}
