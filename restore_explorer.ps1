# restore_explorer.ps1 - С функцией Restore-Window

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ExplorerWindowReadiness {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWnd, EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
'@

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

function Get-ExplorerWindowReadiness {
    param([IntPtr]$Hwnd)

    $classes = @{}
    $callback = {
        param($childHwnd, $lParam)

        if (-not [ExplorerWindowReadiness]::IsWindowVisible($childHwnd)) {
            return $true
        }

        $className = New-Object System.Text.StringBuilder 256
        [void][ExplorerWindowReadiness]::GetClassName($childHwnd, $className, $className.Capacity)
        $classes[$className.ToString()] = $true
        return $true
    }

    [void][ExplorerWindowReadiness]::EnumChildWindows($Hwnd, $callback, [IntPtr]::Zero)

    $hasFolderView = $classes.ContainsKey("SHELLDLL_DefView")
    $hasCommandBar = $classes.ContainsKey("Microsoft.UI.Content.DesktopChildSiteBridge")

    return @{
        Ready = $hasFolderView -and $hasCommandBar
        Status = "folderView=$hasFolderView, commandBar=$hasCommandBar, children=$($classes.Keys -join ',')"
    }
}

function Restore-Window {
    param(
        [string]$Path,
        [string]$WindowState,
        [string]$X,
        [string]$Y,
        [string]$Width,
        [string]$Height,
        [string]$ViewMode,
        [string]$IconSize,
        [string]$SortStr,
        [string]$GroupStr
    )

    $Path = $Path.Trim()
    Write-Output "Opening path: '$Path' (state=$WindowState)"

    # Открываем проводник
    Start-Process explorer.exe -ArgumentList "`"$Path`""
    Write-Output 'opened via explorer.exe'

    $shell = New-Object -ComObject Shell.Application
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $window = $null
    $lastStatus = ""

    while ([DateTime]::UtcNow -lt $deadline -and $null -eq $window) {
        foreach ($candidate in $shell.Windows()) {
            try {
                $candidatePath = $candidate.Document.Folder.Self.Path
                if ($candidate.FullName -like '*explorer.exe' -and $candidatePath -eq $Path) {
                    $readiness = Get-ExplorerWindowReadiness ([IntPtr]$candidate.HWND)
                    if ($readiness.Status -ne $lastStatus) {
                        Write-Output "Explorer window readiness: $($readiness.Status)"
                        $lastStatus = $readiness.Status
                    }

                    if ($readiness.Ready) {
                        $window = $candidate
                        break
                    }
                }
            } catch {}
        }

        if ($null -eq $window) {
            Start-Sleep -Milliseconds 500
        }
    }

    if ($null -eq $window) {
        throw "Explorer window did not become ready within 60 seconds: '$Path'"
    }

    $hwnd = [IntPtr]$window.HWND
    $doc = $window.Document
    Write-Output "Explorer window and command bar are ready"

                # Шаг 1: всегда восстанавливаем normal и ставим размер/позицию
                [WinAPI]::ShowWindow($hwnd, 9)  # SW_RESTORE
                Start-Sleep -Milliseconds 100
                
                if ($X -and $Y -and $Width -and $Height -and [int]$Width -gt 0 -and [int]$Height -gt 0) {
                    [WinAPI]::MoveWindow($hwnd, [int]$X, [int]$Y, [int]$Width, [int]$Height, $true)
                    Write-Output "position: x=$X y=$Y w=$Width h=$Height"
                }
                
                # Шаг 2: применяем максимизацию или сворачивание по необходимости
                if ($WindowState -eq '3' -or $WindowState -eq '2') {
                    Start-Sleep -Milliseconds 100
                    [WinAPI]::ShowWindow($hwnd, 3)  # SW_MAXIMIZE
                    Write-Output 'maximized'
                }
                
                if ($WindowState -eq '1' -or $WindowState -eq '2') {
                    Start-Sleep -Milliseconds 100
                    [WinAPI]::ShowWindow($hwnd, 6)  # SW_MINIMIZE
                    Write-Output 'minimized'
                }
                
                # ViewMode и IconSize
                if ($ViewMode -and $ViewMode -ne '4') { 
                    try { $doc.CurrentViewMode = [int]$ViewMode } catch {} 
                }
                if ($IconSize -and $IconSize -ne '48' -and [int]$IconSize -gt 0) { 
                    try { $doc.IconSize = [int]$IconSize } catch {} 
                }
                Write-Output "applied vm=$ViewMode isz=$IconSize"

    # Сортировка/группировка через отдельный процесс (без Invoke)
    if ($SortStr -and $SortStr -ne '' -and $SortStr -ne ':') {
        Start-Sleep -Milliseconds 500
        
        # Создаем временный скрипт для применения сортировки в STA
        $applyScript = @"
param(`$path, `$sortStr, `$groupStr)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class RestoreHelper {
    public static void Apply(string path, string sortStr, string groupStr) {
        Type shellType = Type.GetTypeFromProgID("Shell.Application");
        dynamic shell = Activator.CreateInstance(shellType);
        foreach (dynamic w in shell.Windows()) {
            try {
                if (w.FullName.Contains("explorer.exe") && w.Document.Folder.Self.Path == path) {
                    dynamic doc = w.Document;
                    if (!string.IsNullOrEmpty(sortStr) && sortStr != ":") {
                        try { doc.SortColumns = sortStr; } catch {}
                    }
                    if (!string.IsNullOrEmpty(groupStr) && groupStr != "System.Null" && groupStr != ":") {
                        try { doc.GroupBy = groupStr; } catch {}
                    }
                    break;
                }
            } catch {}
        }
    }
}
'@ -ReferencedAssemblies "System.Runtime.InteropServices", "Microsoft.CSharp"

[RestoreHelper]::Apply(`$path, `$sortStr, `$groupStr)
Write-Output "sort/group applied for: `$path"
"@

        # Запускаем в отдельном процессе с STA
        $tempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
        $applyScript | Out-File -FilePath $tempFile -Encoding UTF8
        
        $result = & powershell -NoProfile -ExecutionPolicy Bypass -STA -File $tempFile -path $Path -sortStr $SortStr -groupStr $GroupStr 2>&1
        Write-Output $result
        
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}
