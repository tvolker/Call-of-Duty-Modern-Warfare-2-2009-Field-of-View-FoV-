@echo off
title MW2 Utility Launcher
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MW2 Utility.ps1"
if errorlevel 1 (
    echo.
    echo MW2 Utility exited with an error.
    echo Press any key to close.
    pause >nul
)
