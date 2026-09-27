# Donne à l'utilisateur courant le droit "Modifier" sur le dossier Win64 du jeu
# (là où vivent SanAndreas.exe, UE4SS.dll, Mods\ ...). Nécessaire pour que :
#   - UE4SS (qui tourne dans le processus du jeu, non élevé) puisse écrire
#     UE4SS.log, son cache et ses crash dumps ;
#   - on puisse installer / mettre à jour le mod sans UAC à chaque fois.
#
# À exécuter en administrateur. Ne touche qu'à ce dossier et son contenu.

param(
    [string]$GameWin64,   # par défaut : détection automatique (voir common.ps1)
    [string]$User = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

if (-not (Test-GameWin64 $GameWin64)) {
    $GameWin64 = Resolve-GameWin64 $GameWin64
}
if (-not $GameWin64) {
    Write-Error "Game folder not found. Pass -GameWin64 '...\Gameface\Binaries\Win64' (the folder that contains SanAndreas.exe)."
    exit 1
}

if (-not $User) {
    # Nom du compte qui a lancé le script (même en élévation, c'est le même compte).
    $User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}

if (-not (Test-Path $GameWin64)) {
    Write-Error "Folder not found: $GameWin64"
    exit 1
}

Write-Host "Folder  : $GameWin64"
Write-Host "Account : $User"
Write-Host "Right   : Modify (M), inherited by subfolders (CI) and files (OI)"
Write-Host ""

# (OI)(CI)M = Object Inherit + Container Inherit + Modify
& icacls "$GameWin64" /grant "${User}:(OI)(CI)M" /T /C
if ($LASTEXITCODE -ne 0) {
    Write-Error "icacls failed (code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Checking:"
try {
    $test = Join-Path $GameWin64 "__permtest.tmp"
    [IO.File]::WriteAllText($test, "ok")
    Remove-Item $test
    Write-Host "  Write access OK." -ForegroundColor Green
} catch {
    Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
