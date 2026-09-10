# Restart Explorer

## English

A Windows utility for periodically restarting `explorer.exe` to help recover
from Windows 11 shell and window-rendering glitches that can appear after long
periods without a reboot.

The utility:

- checks user inactivity and monitor power state;
- saves open File Explorer windows, positions, sizes, view settings, and state;
- saves and restores the Z-order of visible windows when File Explorer windows are open;
- skips Z-order save and restoration when no File Explorer windows were open;
- restarts the Windows shell;
- restores Explorer windows and the previous foreground window;
- can turn off the display after recovery.

Run `restart_explorer.vbs` from Task Scheduler for unattended execution.
For testing, run:

```bat
restart_explorer.bat /force
```

The `/force` option skips the inactivity and monitor-state checks and does not
turn off the display.

## Русский

Утилита для Windows, которая периодически перезапускает `explorer.exe` и
помогает устранить сбои оболочки Windows 11 и отрисовки окон, возникающие
после длительной работы компьютера без перезагрузки.

Утилита:

- проверяет бездействие пользователя и состояние монитора;
- сохраняет открытые окна Проводника, их позиции, размеры, режимы просмотра и состояние;
- сохраняет и восстанавливает Z-порядок видимых окон, если открыты окна Проводника;
- не выполняет сохранение и восстановление Z-порядка, если открытых окон Проводника не было;
- перезапускает оболочку Windows;
- восстанавливает окна Проводника и предыдущее активное окно;
- может выключить монитор после восстановления.

Для автоматического запуска через Планировщик заданий используйте
`restart_explorer.vbs`.

Для тестирования выполните:

```bat
restart_explorer.bat /force
```

Параметр `/force` отключает проверки бездействия и состояния монитора, а
также не выключает монитор.

## Requirements / Требования

- Windows 10/11
- Windows PowerShell
- Windows Explorer shell

The scripts use Windows APIs and the `Shell.Application` COM interface.
Скрипты используют Windows API и COM-интерфейс `Shell.Application`.
