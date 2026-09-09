# collect_zorders.ps1 - Чистый Z-порядок

param(
    [string]$OutputPath = "$env:TEMP\window_zorders.txt"
)

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WindowZOrder {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowPlacement(IntPtr hWnd, out WINDOWPLACEMENT lpwndpl);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    
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
        public int ZOrder { get; set; }
        public int ProcessId { get; set; }
        public string ProcessName { get; set; }
        public string Title { get; set; }
        public bool IsForeground { get; set; }
        public string Path { get; set; }
        public int WindowState { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public string Hash { get; set; }
    }
    
    public static bool IsTaskbarWindow(IntPtr hWnd) {
        if (!IsWindowVisible(hWnd)) return false;
        
        int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
        if ((exStyle & WS_EX_TOOLWINDOW) != 0) return false;
        
        var title = new System.Text.StringBuilder(256);
        GetWindowText(hWnd, title, 256);
        string titleStr = title.ToString();
        
        uint processId;
        GetWindowThreadProcessId(hWnd, out processId);
        string processName = "";
        try {
            var process = System.Diagnostics.Process.GetProcessById((int)processId);
            processName = process.ProcessName;
        } catch {
            processName = "unknown";
        }
        
        if (titleStr == "Program Manager") return false;
        if (string.IsNullOrEmpty(titleStr) && processName != "explorer") return false;
        if (processName == "ShellExperienceHost") return false;
        if (processName == "TextInputHost") return false;
        if (processName == "ApplicationFrameHost") return false;
        
        return true;
    }
    
    public static List<WindowInfo> GetAllWindows() {
        var windows = new List<WindowInfo>();
        var allHwnds = new List<IntPtr>();
        
        EnumWindows((hWnd, lParam) => {
            if (IsTaskbarWindow(hWnd)) {
                allHwnds.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        
        IntPtr foregroundHwnd = GetForegroundWindow();
        int zOrder = 0;
        
        foreach (IntPtr hwnd in allHwnds) {
            zOrder++;
            
            uint processId;
            GetWindowThreadProcessId(hwnd, out processId);
            
            string processName = "";
            try {
                var process = System.Diagnostics.Process.GetProcessById((int)processId);
                processName = process.ProcessName;
            } catch {
                processName = "unknown";
            }
            
            var title = new System.Text.StringBuilder(256);
            GetWindowText(hwnd, title, 256);
            string titleStr = title.ToString();
            
            bool isForeground = (hwnd == foregroundHwnd);
            
            WINDOWPLACEMENT wp = new WINDOWPLACEMENT();
            wp.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
            int windowState = 0;
            int x = 0, y = 0, width = 0, height = 0;
            
            if (GetWindowPlacement(hwnd, out wp)) {
                bool wasMinimized = (wp.showCmd == 6 || wp.showCmd == 2);
                bool wasMaximized = (wp.showCmd == 3);
                
                if (wasMinimized) {
                    windowState = 1;
                } else if (wasMaximized) {
                    windowState = 3;
                } else {
                    windowState = 0;
                }
                
                x = wp.rcNormalPosition.Left;
                y = wp.rcNormalPosition.Top;
                width = wp.rcNormalPosition.Right - wp.rcNormalPosition.Left;
                height = wp.rcNormalPosition.Bottom - wp.rcNormalPosition.Top;
            }
            
            windows.Add(new WindowInfo {
                HWND = hwnd,
                ZOrder = zOrder,
                ProcessId = (int)processId,
                ProcessName = processName,
                Title = titleStr,
                IsForeground = isForeground,
                Path = "",
                WindowState = windowState,
                X = x,
                Y = y,
                Width = width,
                Height = height,
                Hash = ""
            });
        }
        
        return windows;
    }
}
'@

# Получаем все окна из таскбара
$allWindows = [WindowZOrder]::GetAllWindows()

# Собираем пути для explorer окон
$explorerPaths = @{}
$shell = New-Object -ComObject Shell.Application
$shellWindows = $shell.Windows()

foreach ($win in $shellWindows) {
    try {
        $hwnd = [IntPtr]$win.HWND
        $path = $win.Document.Folder.Self.Path
        $explorerPaths[$hwnd] = $path
    } catch {}
}

# Формируем строки для сохранения
$lines = @()

foreach ($win in $allWindows) {
    $path = ""
    $hash = ""
    
    # Для explorer окон — полная информация + хеш
    if ($win.ProcessName -eq "explorer") {
        if ($explorerPaths.ContainsKey($win.HWND)) {
            $path = $explorerPaths[$win.HWND]
            $hashString = "$path|$($win.WindowState)|$($win.X)|$($win.Y)|$($win.Width)|$($win.Height)"
            $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashString)
            $hash = [Convert]::ToBase64String($hashBytes)
        } else {
            continue
        }
    }
    
    # Экранируем спецсимволы
    $title = $win.Title -replace '\|', '||'
    $path = $path -replace '\|', '||'
    
    # Формат для ВСЕХ окон: ZOrder|ProcessId|ProcessName|Title|IsForeground
    # Для explorer добавляем Path, WindowState, X, Y, Width, Height, Hash
    if ($win.ProcessName -eq "explorer") {
        $line = "$($win.ZOrder)|$($win.ProcessId)|$($win.ProcessName)|$title|$path|$($win.IsForeground)|$($win.WindowState)|$($win.X)|$($win.Y)|$($win.Width)|$($win.Height)|$hash"
    } else {
        $line = "$($win.ZOrder)|$($win.ProcessId)|$($win.ProcessName)|$title|$($win.IsForeground)"
    }
    
    $lines += $line
}

[System.IO.File]::WriteAllText($OutputPath, ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))

Write-Output "========================================"
Write-Output "Taskbar windows: $($allWindows.Count)"
Write-Output "Saved entries: $($lines.Count)"
Write-Output "Saved to: $OutputPath"
Write-Output "========================================"