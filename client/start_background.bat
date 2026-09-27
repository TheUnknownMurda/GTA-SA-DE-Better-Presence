@echo off
rem Lance le client en arriere-plan (pythonw.exe n'ouvre pas de console).
rem Normalement inutile : le mod UE4SS le lance tout seul au demarrage du jeu.
rem Pour l'arreter : stop.bat
cd /d "%~dp0"
start "" ".venv\Scripts\pythonw.exe" "presence.py" %*
