# Native.ps1 - Win32 P/Invoke + global hotkey sink (runtime-compiled C#)
#
# ClaudeUsageMonitor.ps1 has dot-sourced this file, so $script: below refers to the
# entry script scope. See MODULES.md for which file to edit for a given change.


Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class NativeUtil
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr handle);

    // 창을 만들기 전에 호출해야 한다. 이걸 빼면 고배율 디스플레이에서 Windows가
    // 창 전체를 비트맵 확대해 글자가 흐려진다.
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_APPWINDOW = 0x00040000;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    // ShowInTaskbar = false만으로는 Alt+Tab 목록에서 빠지지 않는다.
    // Alt+Tab은 WS_EX_TOOLWINDOW가 붙은 창을 건너뛰므로 그 스타일을 직접 세운다.
    public static int HideFromAltTab(IntPtr hWnd)
    {
        int style = GetWindowLong(hWnd, GWL_EXSTYLE);
        style = (style | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
        SetWindowLong(hWnd, GWL_EXSTYLE, style);
        return GetWindowLong(hWnd, GWL_EXSTYLE);
    }

    public static bool IsToolWindow(IntPtr hWnd)
    {
        return (GetWindowLong(hWnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    // 마지막 키보드/마우스 입력 이후 경과 초. 실패하면 0(활성)으로 간주한다.
    public static uint IdleSeconds()
    {
        LASTINPUTINFO info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        if (!GetLastInputInfo(ref info)) { return 0; }
        int elapsed = Environment.TickCount - (int)info.dwTime;
        if (elapsed < 0) { return 0; }
        return (uint)(elapsed / 1000);
    }
}
'@

# 전역 단축키는 창 메시지(WM_HOTKEY)로 온다. 받아줄 창이 필요한데 PowerShell에서는 Form의 WndProc를
# 재정의할 수 없으므로, 보이지 않는 NativeWindow를 C#으로 만들어 누른 횟수만 세어둔다.
# WndProc는 UI 스레드에서 돌기 때문에 타이머가 이 횟수를 읽는 것으로 안전하게 전달된다.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class HotkeySink : NativeWindow, IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int HotkeyId = 0xC0DE;

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public int PressCount;

    public HotkeySink()
    {
        CreateHandle(new CreateParams());
    }

    public bool Register(uint modifiers, uint virtualKey)
    {
        UnregisterHotKey(Handle, HotkeyId);
        return RegisterHotKey(Handle, HotkeyId, modifiers, virtualKey);
    }

    public void Unregister()
    {
        if (Handle != IntPtr.Zero) { UnregisterHotKey(Handle, HotkeyId); }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && (int)m.WParam == HotkeyId) { PressCount++; }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        Unregister();
        if (Handle != IntPtr.Zero) { DestroyHandle(); }
    }
}
'@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

