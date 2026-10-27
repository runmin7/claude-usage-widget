# ClaudeUsageMonitor.ps1 - 진입점
#
# Claude · Gemini · AGY 사용량을 트레이 아이콘과 바탕화면 위젯으로 표시한다.
# 실제 동작은 lib/ 아래로 나뉘어 있다. 어떤 변경을 어느 파일에서 하는지는 MODULES.md를 보라.
#
# 한글이 들어 있으므로 이 파일과 lib/ 아래 모든 파일은 UTF-8 BOM으로 저장해야 한다.
# BOM이 없으면 PowerShell 5.1이 ANSI로 읽어 파싱조차 실패한다. tools/Fix-Encoding.ps1 참고.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

# api.anthropic.com은 TLS 1.2 이상만 받는다. .NET Framework 기본값은 그보다 낮을 수 있다.
[Net.ServicePointManager]::SecurityProtocol =
    [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol

#region 모듈 로드

# dot-source(`.`)는 파일 내용을 이 스코프에서 실행한다. 그래서 lib/ 안의 $script: 변수와
# 함수가 모두 이 진입점의 스코프에 들어오고, 파일을 나눠도 기존 코드가 그대로 동작한다.
#
# 순서 규칙은 하나뿐이다 — 실행되는 코드가 먼저, 함수 정의는 아무 때나.
#   Native    : C# 타입을 컴파일한다. 이 타입을 쓰는 코드보다 앞이어야 한다.
#   Constants : 상수를 대입한다.
#   State     : 상태 변수를 초기화한다.
# 나머지 파일은 함수만 정의하므로 순서가 무관하다. Menu는 예외로, 아래 시작 순서 중간에서
# 읽어들인다($menu를 만들어 트레이 아이콘에 바로 붙이기 때문이다).

# 프로젝트 폴더는 여기서만 알 수 있다. lib/ 안에서 $PSScriptRoot 를 읽으면 lib/ 자신을 가리키므로,
# 설정·런처 경로가 전부 lib/ 아래로 잘못 잡힌다. 그래서 진입점이 정해 넘긴다.
$script:ScriptDir = $PSScriptRoot
$lib = Join-Path $PSScriptRoot 'lib'

. (Join-Path $lib 'Native.ps1')
. (Join-Path $lib 'Constants.ps1')
. (Join-Path $lib 'State.ps1')

. (Join-Path $lib 'Config.ps1')
. (Join-Path $lib 'Credential.ps1')
. (Join-Path $lib 'Api.ps1')
. (Join-Path $lib 'Parse.ps1')
. (Join-Path $lib 'Format.ps1')
. (Join-Path $lib 'Poll.ps1')
. (Join-Path $lib 'Tray.ps1')
. (Join-Path $lib 'Widget.ps1')
. (Join-Path $lib 'WidgetLayout.ps1')
. (Join-Path $lib 'Hotkey.ps1')
. (Join-Path $lib 'Autostart.ps1')

#endregion

#region 종료

function Stop-App {
    try { Export-Config } catch { }

    # 전역 단축키는 프로세스가 끝나도 OS가 자동으로 놓아주지만, 명시적으로 해제해 다른 프로그램이
    # 곧바로 같은 조합을 쓸 수 있게 한다.
    if ($script:HotkeySink) { $script:HotkeySink.Dispose() }

    if ($script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
    }
    if ($script:CurrentIcon) {
        $script:CurrentIcon.Icon.Dispose()
        [void][NativeUtil]::DestroyIcon($script:CurrentIcon.Handle)
    }
    if ($script:WidgetForm) { $script:WidgetForm.Dispose() }

    # 라벨들이 공유해 쓴 폰트는 컨트롤이 해제해주지 않는다. 여기서 한 번에 정리한다.
    foreach ($font in @($script:FontCache.Values)) { $font.Dispose() }
    $script:FontCache.Clear()

    if ($script:HttpClient) { $script:HttpClient.Dispose() }
    $script:AppContext.ExitThread()
}

#endregion

#region 시작

# 창을 하나라도 만들기 전에 호출해야 효과가 있다. 아래 "이미 실행 중" 안내창도 창이므로 그보다 앞이어야 한다.
[void][NativeUtil]::SetProcessDPIAware()

# 트레이 아이콘이 여러 개 생기는 것을 막는다.
$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeUsageMonitor')
$acquired = $false
try {
    $acquired = $mutex.WaitOne(0)
}
catch {
    # 이전 인스턴스가 mutex를 들고 비정상 종료(작업 관리자 강제 종료·크래시)하면
    # AbandonedMutexException이 난다. PowerShell이 MethodInvocationException으로 감싼다.
    # 이 예외는 "대기는 성공했고 이전 소유자가 정리를 못 했다"는 뜻이므로 소유권은 이미 우리 것이다.
    # 잡지 않으면 강제 종료 이후 다시 실행할 수 없게 된다(런처가 콘솔을 숨겨 오류도 안 보인다).
    $abandoned = [System.Threading.AbandonedMutexException]
    if ($_.Exception -is $abandoned -or $_.Exception.InnerException -is $abandoned) {
        $acquired = $true
    }
    else { throw }
}

if (-not $acquired) {
    [System.Windows.Forms.MessageBox]::Show(
        '이미 실행 중입니다. 트레이 아이콘을 확인하세요.', $script:AppTitle) | Out-Null
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# DPI 인식을 켠 뒤라야 실제 배율이 읽힌다(150% 화면에서 1.5).
$probe = New-Object System.Windows.Forms.Form
$graphicsProbe = $probe.CreateGraphics()
$script:Scale = $graphicsProbe.DpiX / 96.0
$graphicsProbe.Dispose()
$probe.Dispose()

Import-Config

# 지난 실행이 요청 제한에 걸려 있었다면 남은 대기를 이어받는다. 이게 없으면 재시작이
# 곧 즉시 재요청이 되어, 사용자가 껐다 켤수록 차단이 길어진다.
Restore-RetryAfter

$script:UserAgent = Resolve-UserAgent

$script:HttpClient = New-Object System.Net.Http.HttpClient
$script:HttpClient.Timeout = [TimeSpan]::FromSeconds(20)

# $menu 를 만든다. 트레이 아이콘에 곧바로 붙이므로 이 위치여야 한다.
. (Join-Path $lib 'Menu.ps1')

$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:NotifyIcon.ContextMenuStrip = $menu
$script:NotifyIcon.Text = $script:AppTitle
$script:NotifyIcon.Visible = $true
Update-TrayIcon

# 좌클릭으로 위젯을 토글한다. 우클릭은 컨텍스트 메뉴가 가져간다.
$script:NotifyIcon.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:WidgetForm -and $script:WidgetForm.Visible) { Hide-Widget } else { Show-Widget }
})

if ($script:Config.widgetVisible) { Show-Widget }

# 전역 단축키. 등록에 실패해도(다른 프로그램 점유) 나머지 기능은 그대로 동작해야 한다.
$script:HotkeySink = New-Object HotkeySink
[void](Register-Hotkey $script:Config.hotkey)

# 눌린 횟수만 확인하는 가벼운 타이머다. 데이터 폴링 주기(5~15분)와 무관하게 반응해야 하고,
# 1초 타이머로는 위젯이 뜨기까지 체감이 느리다.
$hotkeyTimer = New-Object System.Windows.Forms.Timer
$hotkeyTimer.Interval = 200
$hotkeyTimer.Add_Tick({
    if ($script:HotkeySink.PressCount -eq $script:HotkeySeen) { return }
    $script:HotkeySeen = $script:HotkeySink.PressCount
    if ($script:WidgetForm -and $script:WidgetForm.Visible) { Hide-Widget } else { Show-Widget }
})
$hotkeyTimer.Start()

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    try { Invoke-Tick }
    catch {
        # 틱 하나가 실패해도 프로그램은 살아 있어야 한다.
        Set-Status -Status 'error' -Text $_.Exception.Message
    }
})
$timer.Start()

$script:AppContext = New-Object System.Windows.Forms.ApplicationContext
try {
    [System.Windows.Forms.Application]::Run($script:AppContext)
}
finally {
    $timer.Stop()
    $timer.Dispose()
    $hotkeyTimer.Stop()
    $hotkeyTimer.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

#endregion
