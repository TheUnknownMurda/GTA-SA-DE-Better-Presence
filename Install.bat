@echo off
rem GTA SA DE Better Presence - double-click this file to install or update.
rem It only opens the interactive installer (tools\installer.ps1); nothing is
rem changed on your computer until you pick an action in the menu.

title GTA SA DE Better Presence - Installer
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 goto nopowershell

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\installer.ps1"
if errorlevel 1 (
    echo.
    echo The installer stopped with an error. Scroll up for the message.
    pause
)
exit /b

:nopowershell
echo Windows PowerShell was not found on this computer.
echo Open tools\installer.ps1 manually, or install PowerShell.
pause
