param(
    [int]$TimeoutSeconds = 60,
    [int]$RequiredSuccesses = 4
)

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ShellReadiness {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWnd, EnumWindowsProc callback, IntPtr lParam);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
'@

function Get-TaskbarReadiness {
    param([IntPtr]$Taskbar)

    $classes = @{}
    $callback = {
        param($hWnd, $lParam)

        $className = New-Object System.Text.StringBuilder 256
        [void][ShellReadiness]::GetClassName($hWnd, $className, $className.Capacity)
        $name = $className.ToString()

        if (-not $classes.ContainsKey($name)) {
            $classes[$name] = $false
        }

        if ([ShellReadiness]::IsWindowVisible($hWnd) -and [ShellReadiness]::IsWindowEnabled($hWnd)) {
            $classes[$name] = $true
        }

        return $true
    }

    [void][ShellReadiness]::EnumChildWindows($Taskbar, $callback, [IntPtr]::Zero)

    $hasTrayNotify = $classes.ContainsKey("TrayNotifyWnd") -and $classes["TrayNotifyWnd"]
    $hasTaskList = $classes.ContainsKey("MSTaskSwWClass") -and $classes["MSTaskSwWClass"]
    $hasTaskbarFrame = $classes.ContainsKey("ReBarWindow32") -and $classes["ReBarWindow32"]
    $hasXamlBridge = $classes.ContainsKey("Windows.UI.Composition.DesktopWindowContentBridge")
    $hasXamlCore = $classes.ContainsKey("Windows.UI.Core.CoreWindow")

    return @{
        Ready = $hasTrayNotify -and $hasTaskList -and $hasTaskbarFrame -and $hasXamlBridge -and $hasXamlCore
        Status = "children=$($classes.Keys -join ',')"
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$successes = 0
$lastStatus = ""

while ([DateTime]::UtcNow -lt $deadline) {
    $processes = @(Get-Process explorer -ErrorAction SilentlyContinue)
    $taskbar = [ShellReadiness]::FindWindow("Shell_TrayWnd", $null)
    $ready = $false
    $status = "processes=$($processes.Count), taskbar=$taskbar"

    if ($processes.Count -gt 0 -and $taskbar -ne [IntPtr]::Zero) {
        [uint32]$taskbarPid = 0
        [void][ShellReadiness]::GetWindowThreadProcessId($taskbar, [ref]$taskbarPid)

        $rect = New-Object ShellReadiness+RECT
        $hasRect = [ShellReadiness]::GetWindowRect($taskbar, [ref]$rect)
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        $ownsTaskbar = $processes.Id -contains [int]$taskbarPid

        if ($ownsTaskbar -and
            [ShellReadiness]::IsWindowVisible($taskbar) -and
            [ShellReadiness]::IsWindowEnabled($taskbar) -and
            $hasRect -and $width -gt 0 -and $height -gt 0) {
            $taskbarState = Get-TaskbarReadiness $taskbar
            $comReady = $false
            try {
                $shell = New-Object -ComObject Shell.Application
                $null = $shell.Windows().Count
                $comReady = $true
            } catch {
                $comReady = $false
            }
            $ready = $taskbarState.Ready
        } else {
            $taskbarState = @{ Status = "taskbar base window not ready" }
            $comReady = $false
        }

        $status = "processes=$($processes.Count), taskbarPid=$taskbarPid, size=${width}x${height}, comReady=$comReady, $($taskbarState.Status)"
    }

    if ($ready) {
        $successes++
    } else {
        $successes = 0
    }

    if ($status -ne $lastStatus) {
        Write-Output $status
        $lastStatus = $status
    }

    if ($successes -ge $RequiredSuccesses) {
        Write-Output "Shell readiness confirmed after $successes consecutive checks"
        exit 0
    }

    Start-Sleep -Milliseconds 500
}

Write-Output "Shell readiness timeout after $TimeoutSeconds seconds"
exit 1
