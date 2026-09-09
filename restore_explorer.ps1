# restore_explorer.ps1 - С функцией Restore-Window

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

    Start-Sleep -Milliseconds 1500

    # Применяем позицию, размер, ViewMode, IconSize
    $shell = New-Object -ComObject Shell.Application
    foreach ($w in $shell.Windows()) {
        try {
            $wPath = $w.Document.Folder.Self.Path
            if ($w.FullName -like '*explorer.exe' -and $wPath -eq $Path) {
                $hwnd = [IntPtr]$w.HWND
                $doc = $w.Document
                
                # WinAPI функции
                $code = @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
                Add-Type -TypeDefinition $code
                
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
                
                break
            }
        } catch {}
    }

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
