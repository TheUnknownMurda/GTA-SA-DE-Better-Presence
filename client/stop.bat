@echo off
rem Arrete le client (lance par le mod, ou par start_background.bat).
cd /d "%~dp0"
".venv\Scripts\python.exe" -c "import psutil,os;me=os.path.abspath('presence.py').lower();[p.terminate() for p in psutil.process_iter(['cmdline']) if p.info['cmdline'] and any(me in a.lower() for a in p.info['cmdline'])]" && echo Client stopped.
