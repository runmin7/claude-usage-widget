' start.vbs - launches ClaudeUsageMonitor.ps1 with no console window.
'
' Running "powershell -WindowStyle Hidden" still flashes a console for a moment.
' WScript.Shell.Run with intWindowStyle = 0 hides it completely.
'
' Kept ASCII-only on purpose: WSH reads .vbs as ANSI by default.

Option Explicit

Dim fso, shell, scriptDir, target, command

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(scriptDir, "ClaudeUsageMonitor.ps1")

If Not fso.FileExists(target) Then
    MsgBox "ClaudeUsageMonitor.ps1 not found:" & vbCrLf & target, 16, "Claude Usage Monitor"
    WScript.Quit 1
End If

command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & target & """"

' 0 = hidden window, False = do not wait for the process to exit
shell.Run command, 0, False
