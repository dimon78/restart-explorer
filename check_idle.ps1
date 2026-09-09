# check_idle.ps1 - Берем предпоследнее значение

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Input {
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO l);
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
}
'@

function Get-IdleData {
    $l = New-Object Input+LASTINPUTINFO
    $l.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($l)
    if ([Input]::GetLastInputInfo([ref]$l)) {
        $idleMs = [Environment]::TickCount - $l.dwTime
        return $idleMs, [math]::Round($idleMs / 60000, 1)
    }
    return 0, 0
}

function Get-MonitorTimeout {
    $activePlan = powercfg /getactivescheme
    if ($activePlan -match '([a-fA-F0-9\-]{36})') {
        $planGuid = $matches[1]
    } else {
        return $null, $null
    }
    
    $videoIdleGuid = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
    $output = powercfg /query $planGuid SUB_VIDEO $videoIdleGuid 2>$null
    
    if (-not $output) {
        return $null, $null
    }
    
    # Собираем ВСЕ значения 0x (без фильтрации)
    $allValues = @()
    $lines = $output -split "`r`n"
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "0x([0-9a-f]+)") {
            $hex = $matches[1]
            $seconds = [Convert]::ToInt32($hex, 16)
            $allValues += $seconds
        }
    }
    
    # Берем ПРЕДПОСЛЕДНЕЕ значение (индекс -2)
    # Порядок: 0 (мин), -1 (макс), 1 (инкремент), AC, DC
    # Предпоследнее = AC
    if ($allValues.Count -ge 2) {
        $timeoutSeconds = $allValues[-2]
        $timeoutMin = [math]::Round($timeoutSeconds / 60, 1)
        return $timeoutSeconds, $timeoutMin
    }
    
    return $null, $null
}

# ---- Основная логика ----
$idleMs, $idleMin = Get-IdleData
$timeoutSeconds, $timeoutMin = Get-MonitorTimeout

# Если не удалось получить таймаут
if ($timeoutSeconds -eq $null) {
    Write-Output "SKIP|$idleMin|UNKNOWN"
    exit 1
}

# Случай 1: Если таймаут = 0 (монитор никогда не выключается)
if ($timeoutSeconds -eq 0) {
    Write-Output "SKIP|$idleMin|NEVER"
    exit 1
}

# Случай 2: Если пользователь активен (<5 мин)
if ($idleMs -lt 300000) {
    Write-Output "ACTIVE|$idleMin|$timeoutMin"
    exit 1
}

# Случай 3: Проверяем, превышает ли время бездействия таймаут монитора
if ($idleMin -gt $timeoutMin) {
    Write-Output "CONTINUE|$idleMin|$timeoutMin"
    exit 0
} else {
    Write-Output "SKIP|$idleMin|$timeoutMin"
    exit 1
}