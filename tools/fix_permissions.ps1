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
    Write-Error "Dossier du jeu introuvable. Lance Install.bat pour le choisir, ou passe -GameWin64 '...\Gameface\Binaries\Win64'."
    exit 1
}

if (-not $User) {
    # Nom du compte qui a lancé le script (même en élévation, c'est le même compte).
    $User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}

if (-not (Test-Path $GameWin64)) {
    Write-Error "Dossier introuvable : $GameWin64"
    exit 1
}

Write-Host "Dossier : $GameWin64"
Write-Host "Compte  : $User"
Write-Host "Droit   : Modifier (M), hérité par les sous-dossiers (CI) et fichiers (OI)"
Write-Host ""

# (OI)(CI)M = Object Inherit + Container Inherit + Modify
& icacls "$GameWin64" /grant "${User}:(OI)(CI)M" /T /C
if ($LASTEXITCODE -ne 0) {
    Write-Error "icacls a échoué (code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Vérification :"
try {
    $test = Join-Path $GameWin64 "__permtest.tmp"
    [IO.File]::WriteAllText($test, "ok")
    Remove-Item $test
    Write-Host "  Écriture OK." -ForegroundColor Green
} catch {
    Write-Host "  Échec : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
