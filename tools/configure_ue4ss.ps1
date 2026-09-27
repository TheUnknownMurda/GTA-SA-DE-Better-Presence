# Applique la configuration UE4SS qui fonctionne avec GTA SA DE 1.0.112 :
#   - UE4SS-settings.ini : moteur forcé en 4.26, consoles UE4SS désactivées (plantent sur ce jeu),
#     hot reload activé (Ctrl+R), GraphicsAPI dx11
#   - Mods\mods.txt      : tous les mods livrés avec UE4SS désactivés sauf Keybinds
# Idempotent. Une sauvegarde .bak est créée au premier passage.

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


# --- UE4SS-settings.ini ---------------------------------------------------
$ini = Join-Path $GameWin64 "UE4SS-settings.ini"
if (-not (Test-Path $ini)) { Write-Error "Introuvable : $ini (UE4SS n'est pas installé ?)"; exit 1 }
Backup-Once $ini
$f = Read-TextFile $ini
$wanted = @(
    @("EngineVersionOverride", "MajorVersion", "4"),
    @("EngineVersionOverride", "MinorVersion", "26"),
    @("General", "EnableHotReloadSystem", "1"),
    @("Debug", "ConsoleEnabled", "0"),
    @("Debug", "GuiConsoleEnabled", "0"),
    @("Debug", "GuiConsoleVisible", "0"),
    @("Debug", "GraphicsAPI", "dx11")
)
$lines = $f.Text -split $f.Nl
$section = ""
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\[(.+)\]\s*$') { $section = $Matches[1]; continue }
    foreach ($w in $wanted) {
        if ($section -eq $w[0] -and $lines[$i] -match ('^\s*' + [regex]::Escape($w[1]) + '\s*=')) {
            $lines[$i] = "$($w[1]) = $($w[2])"
        }
    }
}
Write-TextFile $ini ($lines -join $f.Nl) $f.Bom
Write-Host "UE4SS-settings.ini configuré."

# --- mods.txt -------------------------------------------------------------
$mt = Join-Path $GameWin64 "Mods\mods.txt"
if (Test-Path $mt) {
    Backup-Once $mt
    $f = Read-TextFile $mt
    $lines = $f.Text -split $f.Nl | ForEach-Object {
        if ($_ -match '^(\w+)\s*:\s*\d\s*$' -and $Matches[1] -ne "Keybinds") { "$($Matches[1]) : 0" } else { $_ }
    }
    Write-TextFile $mt ($lines -join $f.Nl) $f.Bom
    Write-Host "mods.txt : mods UE4SS livrés désactivés (sauf Keybinds)."
}

Write-Host "Terminé. Le mod BetterPresence est activé par son fichier enabled.txt (voir install_mod.ps1)."
