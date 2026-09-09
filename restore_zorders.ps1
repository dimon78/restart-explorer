# restore_zorders.ps1 - ТОЛЬКО ПО ID ПРОЦЕССА для всех окон

param(
    [string]$ZOrderFile = "$env:TEMP\window_zorders.txt"
)

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WindowZOrderRestore {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    
    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowPlacement(IntPtr hWnd, out WINDOWPLACEMENT lpwndpl);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    public const uint SWP_NOMOVE = 0x0001;
    public const uint SWP_NOSIZE = 0x0002;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const uint SWP_NOZORDER = 0x0004;
    
    public static readonly IntPtr HWND_BOTTOM = (IntPtr)1;
    
    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int x;
        public int y;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    
    public class WindowInfo {
        public IntPtr HWND { get; set; }
        public int ProcessId { get; set; }
        public string ProcessName { get; set; }
        public string Title { get; set; }
    }
    
    public static List<WindowInfo> GetCurrentWindows() {
        var windows = new List<WindowInfo>();
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);
                
                string processName = "";
                try {
                    var process = System.Diagnostics.Process.GetProcessById((int)processId);
                    processName = process.ProcessName;
                } catch {
                    processName = "unknown";
                }
                
                var title = new System.Text.StringBuilder(256);
                GetWindowText(hWnd, title, 256);
                
                windows.Add(new WindowInfo {
                    HWND = hWnd,
                    ProcessId = (int)processId,
                    ProcessName = processName,
                    Title = title.ToString()
                });
            }
            return true;
        }, IntPtr.Zero);
        return windows;
    }
    
    public static bool FindWindowByProcessId(List<WindowInfo> windows, int processId, out IntPtr hwnd) {
        hwnd = IntPtr.Zero;
        foreach (var win in windows) {
            if (win.ProcessId == processId) {
                hwnd = win.HWND;
                return true;
            }
        }
        return false;
    }
    
    public static void SetWindowBottom(IntPtr hWnd) {
        SetWindowPos(hWnd, HWND_BOTTOM, 0, 0, 0, 0, 
            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
}
'@

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESTORING Z-ORDER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Split-EscapedPipe {
    param([string]$Line)

    $fields = New-Object System.Collections.Generic.List[string]
    $field = New-Object System.Text.StringBuilder

    for ($i = 0; $i -lt $Line.Length; $i++) {
        if ($Line[$i] -eq '|' -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '|') {
            [void]$field.Append('|')
            $i++
        } elseif ($Line[$i] -eq '|') {
            [void]$fields.Add($field.ToString())
            [void]$field.Clear()
        } else {
            [void]$field.Append($Line[$i])
        }
    }

    [void]$fields.Add($field.ToString())
    return $fields
}

if (-not (Test-Path $ZOrderFile)) {
    Write-Host "Z-order file not found: $ZOrderFile" -ForegroundColor Red
    exit 1
}

# Читаем сохраненный Z-порядок
$lines = Get-Content $ZOrderFile -Encoding UTF8
$zOrderData = @()

foreach ($line in $lines) {
    $parts = Split-EscapedPipe $line
    
    # Для explorer (12 полей) - сопоставление по хешу
    if ($parts.Count -eq 12) {
        $zOrderData += [PSCustomObject]@{
            ZOrder = [int]$parts[0]
            ProcessId = [int]$parts[1]
            ProcessName = $parts[2]
            Title = $parts[3]
            Path = $parts[4]
            IsForeground = [bool]$parts[5]
            WindowState = [int]$parts[6]
            X = [int]$parts[7]
            Y = [int]$parts[8]
            Width = [int]$parts[9]
            Height = [int]$parts[10]
            Hash = $parts[11]
            IsExplorer = $true
        }
    }
    # Для обычных окон (5 полей) - сопоставление ПО ID ПРОЦЕССА
    elseif ($parts.Count -eq 5) {
        $zOrderData += [PSCustomObject]@{
            ZOrder = [int]$parts[0]
            ProcessId = [int]$parts[1]
            ProcessName = $parts[2]
            Title = $parts[3]
            Path = ""
            IsForeground = [bool]$parts[4]
            WindowState = 0
            X = 0
            Y = 0
            Width = 0
            Height = 0
            Hash = ""
            IsExplorer = $false
        }
    }
}

Write-Host "Loaded $($zOrderData.Count) windows from Z-order file" -ForegroundColor Green

# Получаем текущие окна
$currentWindows = [WindowZOrderRestore]::GetCurrentWindows()
Write-Host "Found $($currentWindows.Count) visible windows" -ForegroundColor Green

# Для explorer окон получаем пути и параметры через PowerShell
$explorerCurrentInfo = @{}
$shell = New-Object -ComObject Shell.Application
$shellWindows = $shell.Windows()

foreach ($win in $shellWindows) {
    try {
        $hwnd = [IntPtr]$win.HWND
        $path = $win.Document.Folder.Self.Path
        
        $placement = New-Object WindowZOrderRestore+WINDOWPLACEMENT
        $placement.length = [System.Runtime.InteropServices.Marshal]::SizeOf($placement)
        $windowState = 0
        $x = 0; $y = 0; $width = 0; $height = 0
        
        if ([WindowZOrderRestore]::GetWindowPlacement($hwnd, [ref]$placement)) {
            $wasMinimized = ($placement.showCmd -eq 6 -or $placement.showCmd -eq 2)
            $wasMaximized = ($placement.showCmd -eq 3)
            
            if ($wasMinimized) { $windowState = 1 }
            elseif ($wasMaximized) { $windowState = 3 }
            else { $windowState = 0 }
            
            $x = $placement.rcNormalPosition.Left
            $y = $placement.rcNormalPosition.Top
            $width = $placement.rcNormalPosition.Right - $placement.rcNormalPosition.Left
            $height = $placement.rcNormalPosition.Bottom - $placement.rcNormalPosition.Top
        }
        
        $hashString = "$path|$windowState|$x|$y|$width|$height"
        $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashString)
        $hash = [Convert]::ToBase64String($hashBytes)
        
        $explorerCurrentInfo[$hwnd] = @{
            Path = $path
            WindowState = $windowState
            X = $x
            Y = $y
            Width = $width
            Height = $height
            Hash = $hash
        }
    } catch {}
}

# Сопоставляем окна
$matchedWindows = @()
$notFoundCount = 0

foreach ($item in $zOrderData) {
    $targetHwnd = [IntPtr]::Zero
    
    if ($item.IsExplorer) {
        # Для explorer — сопоставляем по хешу
        Write-Host "  [$($item.ZOrder)] Looking for explorer with hash: $($item.Hash)" -ForegroundColor Gray
        
        foreach ($hwnd in $explorerCurrentInfo.Keys) {
            $info = $explorerCurrentInfo[$hwnd]
            if ($info.Hash -eq $item.Hash) {
                $targetHwnd = $hwnd
                Write-Host "  [$($item.ZOrder)] Explorer matched by hash: $($info.Path)" -ForegroundColor Green
                break
            }
        }
    } else {
        # Для ВСЕХ остальных окон — сопоставляем ТОЛЬКО ПО ID ПРОЦЕССА
        [WindowZOrderRestore]::FindWindowByProcessId($currentWindows, $item.ProcessId, [ref]$targetHwnd)
    }
    
    if ($targetHwnd -eq [IntPtr]::Zero) {
        Write-Host "  [$($item.ZOrder)] $($item.ProcessName) (PID: $($item.ProcessId)) -> NOT FOUND" -ForegroundColor Red
        $notFoundCount++
        continue
    }
    
    $matchedWindows += [PSCustomObject]@{
        ZOrder = $item.ZOrder
        ProcessName = $item.ProcessName
        ProcessId = $item.ProcessId
        HWND = $targetHwnd
        IsForeground = $item.IsForeground
    }
}

Write-Host "`nMatched $($matchedWindows.Count) windows" -ForegroundColor Green

# Восстанавливаем Z-порядок
$nonForeground = $matchedWindows | Where-Object { -not $_.IsForeground } | Sort-Object ZOrder -Descending
$foreground = $matchedWindows | Where-Object { $_.IsForeground }

Write-Host "`nRestoring non-foreground windows (bottom to top)..." -ForegroundColor Yellow

foreach ($win in $nonForeground) {
    [WindowZOrderRestore]::SetWindowBottom($win.HWND)
    Write-Host "  [$($win.ZOrder)] $($win.ProcessName) (PID: $($win.ProcessId)) -> bottom" -ForegroundColor Gray
    Start-Sleep -Milliseconds 50
}

if ($foreground) {
    $fgWin = $foreground | Select-Object -First 1
    Write-Host "`nSetting foreground window: [$($fgWin.ZOrder)] $($fgWin.ProcessName) (PID: $($fgWin.ProcessId))" -ForegroundColor Green
    [WindowZOrderRestore]::SetForegroundWindow($fgWin.HWND)
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESTORE COMPLETE" -ForegroundColor Green
Write-Host "Restored: $($matchedWindows.Count) windows" -ForegroundColor Green
Write-Host "Not found: $notFoundCount windows" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan