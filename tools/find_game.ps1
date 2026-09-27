# Trouve le dossier Win64 du jeu (celui qui contient SanAndreas.exe) et
# l'affiche. Le chemin est copié dans le presse-papiers et mémorisé dans
# tools\game_path.txt, que les autres scripts réutilisent ensuite.
#
# Utilisation : clic droit sur ce fichier > Exécuter avec PowerShell.

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Write-Found($path) {
    Save-GamePath $path
    Write-Host ""
    Write-Host "  Game folder found:" -ForegroundColor Green
    Write-Host "  $path" -ForegroundColor White
    Write-Host ""
    try {
        Set-Clipboard -Value $path
        Write-Host "  (copied to the clipboard - paste it wherever the README says <Win64>)" -ForegroundColor DarkGray
    } catch {
        Write-Host "  (could not copy it to the clipboard, select the line above instead)" -ForegroundColor DarkGray
    }
    Write-Host "  Remembered in tools\game_path.txt, so the other scripts find it on their own." -ForegroundColor DarkGray
    Write-Host ""
    $answer = Read-Host "  Open this folder in Explorer? [Y/n]"
    if ($answer -notmatch '^(n|no|non)$') { Start-Process explorer.exe $path }
}

# Recherche approfondie : parcourt réellement les disques. Lente (plusieurs
# minutes), donc proposée seulement si la recherche rapide échoue.
function Find-GameThorough {
    $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty DeviceID
    if (-not $drives) { $drives = @("C:") }
    foreach ($d in $drives) {
        Write-Host "  Searching $d ..." -ForegroundColor DarkGray
        $hit = Get-ChildItem "$d\" -Recurse -Filter "SanAndreas.exe" -File -Force -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return (Split-Path $hit.FullName) }
    }
    return $null
}

Write-Host ""
Write-Host "  GTA SA DE Better Presence - finding your game" -ForegroundColor Cyan
Write-Host "  Looking in the running game, Steam, Epic and the usual folders..." -ForegroundColor DarkGray

$win64 = Find-GameWin64
if ($win64) {
    Write-Found $win64
} else {
    Write-Host ""
    Write-Host "  Not found in the usual places." -ForegroundColor Yellow
    Write-Host "  A full search of your drives takes a few minutes." -ForegroundColor Gray
    $answer = Read-Host "  Search everywhere now? [Y/n]"
    if ($answer -notmatch '^(n|no|non)$') {
        $win64 = Find-GameThorough
    }
    if ($win64) {
        Write-Found $win64
    } else {
        Write-Host ""
        Write-Host "  Still nothing. Find SanAndreas.exe yourself:" -ForegroundColor Yellow
        Write-Host "    - Rockstar Launcher: Settings > GTA San Andreas - Definitive Edition > shows the folder" -ForegroundColor Gray
        Write-Host "    - Steam: right-click the game > Manage > Browse local files" -ForegroundColor Gray
        Write-Host "    - Epic Games: Library > the three dots > Manage > folder icon" -ForegroundColor Gray
        Write-Host "  The folder you need is the Gameface\Binaries\Win64 one inside it." -ForegroundColor Gray
        Write-Host ""
    }
}

Read-Host "  Press Enter to close"
