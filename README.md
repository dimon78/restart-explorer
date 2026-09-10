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
- waits for the shell and taskbar to pass several consecutive readiness checks;
- restores Explorer windows and the previous foreground window;
- can turn off the display after recovery.

Run `restart_explorer.vbs` from Task Scheduler for unattended execution.
For testing, run:

```bat
restart_explorer.bat /force
```

The `/force` option skips the inactivity and monitor-state checks and does not
turn off the display.

## Recent fixes

- Z-order capture and restoration are skipped when no File Explorer windows
  were open.
- Shell readiness is checked after restarting Explorer by inspecting the
  taskbar window and its Win32/XAML child components.
- Explorer windows are opened only after the taskbar passes several successful
  readiness checks.
- Each restored Explorer window is also checked for its folder view and modern
  command bar before its position and view settings are applied.
- Window titles containing `|` are parsed correctly during Z-order restoration.

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
- дожидается успешного прохождения нескольких последовательных проверок оболочки и панели задач;
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

## Последние исправления

- Сохранение и восстановление Z-порядка пропускается, если окон Проводника не
  было.
- После перезапуска Explorer проверяется панель задач и её Win32/XAML-компоненты.
- Окна Проводника открываются только после нескольких успешных проверок готовности
  панели задач.
- Перед применением размеров и параметров каждого окна проверяются область папки
  и современная командная панель.
- Заголовки окон с символом `|` корректно разбираются при восстановлении Z-порядка.

## Requirements / Требования

- Windows 10/11
- Windows PowerShell
- Windows Explorer shell

The scripts use Windows APIs and the `Shell.Application` COM interface.
Скрипты используют Windows API и COM-интерфейс `Shell.Application`.
