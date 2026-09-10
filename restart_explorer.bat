@echo off
setlocal EnableDelayedExpansion

set "logfile=%TEMP%\explorer_restart_log.txt"
set "pathsfile=%TEMP%\explorer_paths.txt"
set "zorderfile=%TEMP%\window_zorders.txt"
set "FORCE_MODE=0"

chcp 65001 >nul

echo ======================================== > "%logfile%"
echo Start: %date% %time% >> "%logfile%"
echo. >> "%logfile%"

:: === 0. Проверка активности пользователя и монитора ===
:: Параметр /force пропускает проверку (для тестирования)
if /i "%1"=="/force" (
    set "FORCE_MODE=1"
    echo FORCE mode - skipping activity check and display turn off >> "%logfile%"
    goto skip_check
)

echo Checking user activity and monitor state... >> "%logfile%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_idle.ps1" >> "%logfile%" 2>&1

if errorlevel 1 (
    echo   Restart skipped - user active or monitor on >> "%logfile%"
    echo. >> "%logfile%"
    echo End: %date% %time% >> "%logfile%"
    echo ======================================== >> "%logfile%"
    goto :eof
)

echo   PC idle and monitor off, proceeding... >> "%logfile%"

:skip_check
echo. >> "%logfile%"

:: === 1. Сохраняем окна проводника (пути и состояние) ===
echo Getting open Explorer windows + minimized state... >> "%logfile%"

if exist "%pathsfile%" del "%pathsfile%" >nul 2>&1
if exist "%zorderfile%" del "%zorderfile%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_explorers.ps1" -OutputPath "%pathsfile%" >> "%logfile%" 2>&1

echo. >> "%logfile%"
echo Content of paths file: >> "%logfile%"
if exist "%pathsfile%" (type "%pathsfile%" >> "%logfile%") else (echo paths file NOT created >> "%logfile%")
echo. >> "%logfile%"

set "HAS_EXPLORER_WINDOWS=0"
if exist "%pathsfile%" (
    for /f "usebackq delims=" %%A in ("%pathsfile%") do set "HAS_EXPLORER_WINDOWS=1"
)
echo Explorer windows saved: !HAS_EXPLORER_WINDOWS! >> "%logfile%"

:: === 2. Сохраняем Z-порядок только при наличии окон проводника ===
if "!HAS_EXPLORER_WINDOWS!"=="1" (
    echo Saving Z-order of all windows... >> "%logfile%"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_zorders.ps1" -OutputPath "%zorderfile%" >> "%logfile%" 2>&1
) else (
    echo Skipping Z-order save - no Explorer windows were saved >> "%logfile%"
)
echo. >> "%logfile%"

:: === 3. Kill explorer ===
echo Killing explorer... >> "%logfile%"
taskkill /f /im explorer.exe >nul 2>&1
echo   explorer.exe terminated >> "%logfile%"

:: === 4. Start explorer and wait for shell to be fully ready ===
echo Starting explorer... >> "%logfile%"
start explorer.exe

echo Waiting for explorer shell to be fully ready... >> "%logfile%"

set "wait_count=0"

:wait_shell
timeout /t 1 /nobreak >nul
set /a wait_count+=1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$p = Get-Process explorer -ErrorAction SilentlyContinue; if (-not $p) { exit 1 }; $null = Add-Type -Name User32 -Namespace Win32 -MemberDefinition '[DllImport(\"user32.dll\")] public static extern IntPtr FindWindow(string c, string n); [DllImport(\"user32.dll\")] public static extern bool IsWindowVisible(IntPtr hWnd);'; $hwnd = [Win32.User32]::FindWindow('Shell_TrayWnd', $null); if ($hwnd -eq [IntPtr]::Zero) { exit 1 }; if (-not [Win32.User32]::IsWindowVisible($hwnd)) { exit 1 }; Write-Output ('PID=' + $p.Id + ' Shell_TrayWnd visible'); exit 0" > "%TEMP%\shell_check.txt" 2>&1

if errorlevel 1 (
    echo   attempt !wait_count!: shell not ready yet >> "%logfile%"
    goto wait_shell
)

echo   attempt !wait_count!: shell is ready >> "%logfile%"
type "%TEMP%\shell_check.txt" >> "%logfile%"
del "%TEMP%\shell_check.txt" >nul 2>&1

echo Explorer shell is ready >> "%logfile%"
echo. >> "%logfile%"

:: === 5. Restore windows ===
echo Restoring windows... >> "%logfile%"

if exist "%pathsfile%" (
    set count=0
    for /f "usebackq tokens=1-10 delims=|" %%a in ("%pathsfile%") do (
        set "item=%%a"
        set "windowstate=%%b"
        set "x=%%c"
        set "y=%%d"
        set "width=%%e"
        set "height=%%f"
        set "viewmode=%%g"
        set "iconsize=%%h"
        set "sortstr=%%i"
        set "groupstr=%%j"
        
        set /a count+=1

        echo Trying to open: !item!  ^(state=!windowstate!, pos=!x!,!y! !width!x!height!, vm=!viewmode!, isz=!iconsize!, sort=!sortstr!, group=!groupstr!^) >> "%logfile%"

        set "RESTORE_PATH=!item!"
        set "RESTORE_STATE=!windowstate!"
        set "RESTORE_X=!x!"
        set "RESTORE_Y=!y!"
        set "RESTORE_W=!width!"
        set "RESTORE_H=!height!"
        set "RESTORE_VM=!viewmode!"
        set "RESTORE_ISZ=!iconsize!"
        set "RESTORE_SORT=!sortstr!"
        set "RESTORE_GROUP=!groupstr!"
    
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            "$path = $env:RESTORE_PATH; $state = $env:RESTORE_STATE; $x = $env:RESTORE_X; $y = $env:RESTORE_Y; $w = $env:RESTORE_W; $h = $env:RESTORE_H; $vm = $env:RESTORE_VM; $isz = $env:RESTORE_ISZ; $sort = $env:RESTORE_SORT; $group = $env:RESTORE_GROUP;" ^
            ". '%~dp0restore_explorer.ps1'; Restore-Window -Path $path -WindowState $state -X $x -Y $y -Width $w -Height $h -ViewMode $vm -IconSize $isz -SortStr $sort -GroupStr $group" >> "%logfile%" 2>&1
        
        echo   - restored >> "%logfile%"
    )
    echo Total restored attempts: !count! >> "%logfile%"
    del "%pathsfile%" >nul 2>&1
) else (
    echo No paths file - nothing to restore >> "%logfile%"
)

echo. >> "%logfile%"

:: === 6. Restore Z-order of ALL windows ===
if "!HAS_EXPLORER_WINDOWS!"=="1" (
    echo Restoring Z-order of all windows... >> "%logfile%"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore_zorders.ps1" -ZOrderFile "%zorderfile%" >> "%logfile%" 2>&1
) else (
    echo Skipping Z-order restore - no Explorer windows were saved >> "%logfile%"
)
del "%zorderfile%" >nul 2>&1

echo. >> "%logfile%"

:: === 7. Turn off display (только если НЕ force) ===
if %FORCE_MODE%==0 (
    echo Turning off display... >> "%logfile%"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0turn_off_display.ps1" >> "%logfile%" 2>&1
    echo Display turned off >> "%logfile%"
) else (
    echo Skipping display turn off (force mode) >> "%logfile%"
)

echo. >> "%logfile%"

echo End: %date% %time% >> "%logfile%"
echo ======================================== >> "%logfile%"

echo.
echo Log saved to: %logfile%
echo.
type "%logfile%"

endlocal