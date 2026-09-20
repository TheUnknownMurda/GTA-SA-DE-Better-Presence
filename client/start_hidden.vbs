' Lance le client en arriere-plan, sans fenetre de console.
' Pour l'arreter : Gestionnaire des taches > pythonw.exe, ou stop.bat.
' Pour le demarrer avec Windows : cree un raccourci vers ce fichier dans
'   %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = dir
shell.Run """" & dir & "\.venv\Scripts\pythonw.exe"" """ & dir & "\presence.py""", 0, False
