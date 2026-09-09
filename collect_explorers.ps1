# collect_explorers.ps1 - С возвратом логов из C#

param(
    [string]$OutputPath = "$env:TEMP\explorer_paths.txt"
)

$csharpCode = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class ExplorerHelper {
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool GetWindowPlacement(IntPtr hWnd, out WINDOWPLACEMENT lpwndpl);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    
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
    
    const int SW_RESTORE = 9;
    const int SW_MINIMIZE = 6;
    const int SW_SHOWMINIMIZED = 2;
    const int SW_MAXIMIZE = 3;
    const int WPF_RESTORETOMAXIMIZED = 2;
    
    public static string CollectWindows() {
        var logs = new List<string>();
        var lines = new List<string>();
        
        logs.Add("=== COLLECT EXPLORERS (C#) ===");
        
        Type shellType = Type.GetTypeFromProgID("Shell.Application");
        dynamic shell = Activator.CreateInstance(shellType);
        dynamic windows = shell.Windows();
        
        int totalWindows = 0;
        int searchWindows = 0;
        
        foreach (dynamic window in windows) {
            try {
                string fullName = window.FullName;
                if (!fullName.Contains("explorer.exe")) continue;
                
                totalWindows++;
                dynamic doc = window.Document;
                dynamic folder = doc.Folder;
                dynamic self = folder.Self;
                string path = self.Path;
                
                logs.Add("  [" + totalWindows + "] Path: " + path);
                
                // Проверяем, является ли это окно поиска
                bool isSearchWindow = false;
                
                if (!string.IsNullOrEmpty(path)) {
                    if (!path.Contains("\\") && !path.StartsWith("\\\\")) {
                        isSearchWindow = true;
                        logs.Add("    -> SEARCH (no backslash)");
                    }                    
                }
                
                if (isSearchWindow) {
                    searchWindows++;
                    continue;
                }
                
                if (string.IsNullOrEmpty(path) || path == "::") {
                    logs.Add("    -> SKIP (invalid path)");
                    continue;
                }
                
                logs.Add("    -> SAVE");
                
                IntPtr hwnd = (IntPtr)(int)window.HWND;
                
                WINDOWPLACEMENT wpOriginal = new WINDOWPLACEMENT();
                wpOriginal.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
                GetWindowPlacement(hwnd, out wpOriginal);
                
                bool wasMinimized = (wpOriginal.showCmd == SW_MINIMIZE || wpOriginal.showCmd == SW_SHOWMINIMIZED);
                bool wasMaximized = (wpOriginal.showCmd == SW_MAXIMIZE);
                
                if (wasMinimized || wasMaximized) {
                    ShowWindow(hwnd, SW_RESTORE);
                    System.Threading.Thread.Sleep(100);
                }
                
                WINDOWPLACEMENT wpNormal = new WINDOWPLACEMENT();
                wpNormal.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
                int x = 0, y = 0, width = 0, height = 0;
                
                if (GetWindowPlacement(hwnd, out wpNormal)) {
                    x = wpNormal.rcNormalPosition.Left;
                    y = wpNormal.rcNormalPosition.Top;
                    width = wpNormal.rcNormalPosition.Right - wpNormal.rcNormalPosition.Left;
                    height = wpNormal.rcNormalPosition.Bottom - wpNormal.rcNormalPosition.Top;
                }
                
                int windowState = 0;
                if (wasMinimized) {
                    if ((wpOriginal.flags & WPF_RESTORETOMAXIMIZED) != 0) {
                        windowState = 2;
                    } else {
                        windowState = 1;
                    }
                } else if (wasMaximized) {
                    windowState = 3;
                } else {
                    windowState = 0;
                }
                
                int viewmode = 4;
                int iconsize = 48;
                try { viewmode = (int)doc.CurrentViewMode; } catch {}
                try { iconsize = (int)doc.IconSize; } catch {}
                
                string sortStr = "";
                string groupStr = "";
                try { sortStr = doc.SortColumns != null ? doc.SortColumns.ToString() : ""; } catch {}
                try { groupStr = doc.GroupBy != null ? doc.GroupBy.ToString() : ""; } catch {}
                
                lines.Add(string.Format("{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}", 
                    path, windowState, x, y, width, height, viewmode, iconsize, sortStr, groupStr));
            } catch (Exception ex) {
                logs.Add("    -> ERROR: " + ex.Message);
            }
        }
        
        logs.Add("");
        logs.Add("Total explorer windows: " + totalWindows);
        logs.Add("Search windows skipped: " + searchWindows);
        logs.Add("Windows saved: " + lines.Count);
        logs.Add("=== END ===");
        
        // Возвращаем логи и результат
        return string.Join("\n", logs) + "\n\n=== DATA ===\n" + string.Join("\n", lines);
    }
}
"@

# Создаем временный скрипт
$tempScript = @"
Add-Type -TypeDefinition @'
$csharpCode
'@ -ReferencedAssemblies "System.Runtime.InteropServices", "Microsoft.CSharp"

`$result = [ExplorerHelper]::CollectWindows()

# Разделяем логи и данные
`$parts = `$result -split "\n=== DATA ===\n"
`$logs = `$parts[0]
`$data = if (`$parts.Count -gt 1) { `$parts[1] } else { "" }

# Выводим логи
Write-Host `$logs -ForegroundColor Cyan

# Сохраняем данные
if (-not [string]::IsNullOrEmpty(`$data)) {
    `$data = `$data.Trim()
    [System.IO.File]::WriteAllText('$OutputPath', `$data, [System.Text.UTF8Encoding]::new(`$false))
    `$count = (`$data -split "`n" | Where-Object { `$_ -ne "" }).Count
    Write-Host "`nSaved $count windows to: $OutputPath" -ForegroundColor Green
} else {
    Write-Host "No data to save" -ForegroundColor Yellow
}
"@

$tempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
$tempScript | Out-File -FilePath $tempFile -Encoding UTF8

& powershell -NoProfile -ExecutionPolicy Bypass -File $tempFile

Remove-Item $tempFile -Force -ErrorAction SilentlyContinue