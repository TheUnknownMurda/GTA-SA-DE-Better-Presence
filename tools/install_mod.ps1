# Copie (ou met à jour) le mod UE4SS BetterPresence dans le dossier Mods du jeu.
# Relance ce script après chaque modification de mod\BetterPresence\Scripts\main.lua,
# puis appuie sur Ctrl+R en jeu (hot reload UE4SS) ou relance le jeu.
#
# Le mod est activé par le fichier mod\BetterPresence\enabled.txt (mécanisme UE4SS) :
# pas besoin de le déclarer dans mods.txt.

param(
    [string]$GameWin64   # par défaut : détection automatique (voir common.ps1)
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$GameWin64 = Resolve-GameWin64 $GameWin64
if (-not $GameWin64) {
    Write-Error "Dossier du jeu introuvable. Lance Install.bat pour le choisir, ou passe -GameWin64 '...\Gameface\Binaries\Win64'."
    exit 1
}

$root = Get-ProjectRoot
$src  = Join-Path $root "mod\BetterPresence"
$dst  = Join-Path $GameWin64 "Mods\BetterPresence"

if (-not (Test-Path (Join-Path $GameWin64 "UE4SS.dll"))) {
    Write-Error "UE4SS.dll introuvable dans $GameWin64 - installe UE4SS d'abord (voir README)."
    exit 1
}
if (-not (Test-Path $src)) {
    Write-Error "Source introuvable : $src"
    exit 1
}

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Path (Join-Path $src "*") -Destination $dst -Recurse -Force

# Commande de lancement du client Discord, lue par le mod au démarrage du jeu :
# ligne 1 = interpréteur (pythonw.exe n'ouvre pas de console), ligne 2 = script.
$pythonw = Join-Path $root "client\.venv\Scripts\pythonw.exe"
$script  = Join-Path $root "client\presence.py"
if (Test-Path $script) {
    [IO.File]::WriteAllText((Join-Path $dst "client_path.txt"), "$pythonw`r`n$script",
        [Text.UTF8Encoding]::new($false))
    if (-not (Test-Path $pythonw)) {
        Write-Warning "client\.venv absent : lance Install.bat (etape [C]) pour preparer le client Python."
    }
} else {
    Write-Warning "client\presence.py introuvable : le client ne sera pas lance automatiquement."
}

Write-Host "Mod installé dans $dst"
Get-ChildItem -Recurse -File $dst | ForEach-Object { "  " + $_.FullName.Substring($dst.Length + 1) + "  (" + $_.Length + " o)" }
