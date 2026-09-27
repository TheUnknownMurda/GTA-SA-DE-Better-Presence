# Fonctions partagées par les scripts tools\*.ps1 : localisation du jeu,
# lecture/écriture des fichiers texte du jeu, état de l'installation.
# Compatible Windows PowerShell 5.1 (celui livré avec Windows) et PowerShell 7.

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:GamePathFile = Join-Path $PSScriptRoot "game_path.txt"

function Get-ProjectRoot { return $script:ProjectRoot }

# --- Fichiers texte (les .ini/.txt du jeu sont en UTF-8, parfois avec BOM) ----
function Read-TextFile($path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    # Le BOM se détecte sur les octets : en PowerShell 5.1, "texte".StartsWith([char]0xFEFF)
    # est VRAI pour n'importe quelle chaîne (comparaison culturelle, le BOM est ignorable),
    # ce qui ferait perdre le premier caractère des fichiers sans BOM.
    if ($bom) {
        $text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    } else {
        $text = [Text.Encoding]::UTF8.GetString($bytes)
    }
    $nl = "`n"
    if ($text -match "`r`n") { $nl = "`r`n" }
    return @{ Text = $text; Bom = $bom; Nl = $nl }
}

function Write-TextFile($path, $text, $bom) {
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($bom))
}

function Backup-Once($path) {
    $bak = "$path.bak"
    if ((Test-Path $path) -and -not (Test-Path $bak)) { Copy-Item $path $bak }
}

# --- Localisation du jeu ------------------------------------------------------
function Test-GameWin64($path) {
    if (-not $path) { return $false }
    return (Test-Path (Join-Path $path "SanAndreas.exe"))
}

function Get-SavedGamePath {
    if (Test-Path $script:GamePathFile) {
        $p = (Get-Content $script:GamePathFile -TotalCount 1).Trim()
        if (Test-GameWin64 $p) { return $p }
    }
    return $null
}

function Save-GamePath($path) {
    Write-TextFile $script:GamePathFile $path $false
}

function Get-GameFromProcess {
    $p = Get-Process SanAndreas -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and $p.Path) { return (Split-Path $p.Path) }
    return $null
}

function Get-SteamLibraryRoots {
    $roots = @()
    foreach ($steam in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $roots += $m.Groups[1].Value -replace '\\\\', '\'
            }
        }
    }
    return $roots
}

function Get-EpicInstallLocations {
    $locs = @()
    $dir = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $dir) {
        foreach ($item in Get-ChildItem "$dir\*.item" -ErrorAction SilentlyContinue) {
            try {
                $j = Get-Content $item.FullName -Raw | ConvertFrom-Json
                if ($j.InstallLocation) { $locs += $j.InstallLocation }
            } catch { }
        }
    }
    return $locs
}

# Cherche …\<jeu>\Gameface\Binaries\Win64\SanAndreas.exe sous une racine donnée.
function Find-GameUnder($root, $depth) {
    if (-not $root -or -not (Test-Path $root)) { return $null }
    $pattern = "Gameface\Binaries\Win64\SanAndreas.exe"
    $prefix = ""
    for ($i = 0; $i -le $depth; $i++) {
        $candidate = Join-Path $root "$prefix$pattern"
        $hit = Get-Item $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return (Split-Path $hit.FullName) }
        $prefix += "*\"
    }
    return $null
}

# Détection automatique : processus en cours, Steam, Epic, puis emplacements
# habituels sur chaque disque fixe.
function Find-GameWin64 {
    $fromProc = Get-GameFromProcess
    if (Test-GameWin64 $fromProc) { return $fromProc }

    foreach ($root in Get-SteamLibraryRoots) {
        $hit = Find-GameUnder (Join-Path $root "steamapps\common") 1
        if ($hit) { return $hit }
    }
    foreach ($loc in Get-EpicInstallLocations) {
        $hit = Find-GameUnder $loc 1
        if ($hit) { return $hit }
    }

    $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty DeviceID
    if (-not $drives) { $drives = @("C:") }
    $subRoots = @(
        "Program Files\Rockstar Games", "Program Files (x86)\Rockstar Games",
        "Rockstar Games", "Games", "Program Files\Epic Games", "Epic Games",
        "SteamLibrary\steamapps\common", "Program Files (x86)\Steam\steamapps\common",
        "Program Files\Steam\steamapps\common", "XboxGames"
    )
    foreach ($d in $drives) {
        foreach ($sub in $subRoots) {
            $hit = Find-GameUnder (Join-Path "$d\" $sub) 1
            if ($hit) { return $hit }
        }
        # Dernier recours : deux niveaux de dossiers à la racine du disque.
        $hit = Find-GameUnder "$d\" 2
        if ($hit) { return $hit }
    }
    return $null
}

# Chemin à utiliser : paramètre explicite, puis chemin mémorisé, puis détection.
function Resolve-GameWin64($explicit) {
    if (Test-GameWin64 $explicit) { return $explicit }
    $saved = Get-SavedGamePath
    if ($saved) { return $saved }
    $found = Find-GameWin64
    if ($found) { Save-GamePath $found }
    return $found
}

# --- État de l'installation ---------------------------------------------------
function Get-ModVersion($win64) {
    $lua = Join-Path $win64 "Mods\BetterPresence\Scripts\main.lua"
    if (-not (Test-Path $lua)) { return $null }
    $m = Select-String -Path $lua -Pattern '^local VERSION\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return "?"
}

function Test-WriteAccess($path) {
    if (-not (Test-Path $path)) { return $false }
    $probe = Join-Path $path ".bp_write_test"
    try {
        [IO.File]::WriteAllText($probe, "x")
        Remove-Item $probe -Force
        return $true
    } catch { return $false }
}

function Test-Ue4ssConfigured($win64) {
    $ini = Join-Path $win64 "UE4SS-settings.ini"
    if (-not (Test-Path $ini)) { return $false }
    $txt = (Read-TextFile $ini).Text
    return ($txt -match "(?m)^MajorVersion\s*=\s*4\s*$") -and
           ($txt -match "(?m)^MinorVersion\s*=\s*26\s*$") -and
           ($txt -match "(?m)^GuiConsoleEnabled\s*=\s*0\s*$")
}

function Get-ClientConfigPath {
    return (Join-Path (Get-ProjectRoot) "client\config.json")
}

function Get-DiscordAppId {
    $cfg = Get-ClientConfigPath
    if (-not (Test-Path $cfg)) { return $null }
    $m = Select-String -Path $cfg -Pattern '"discord_client_id"\s*:\s*"([^"]*)"' | Select-Object -First 1
    if ($m) {
        $v = $m.Matches[0].Groups[1].Value
        if ($v -match '^\d{15,25}$') { return $v }
    }
    return $null
}

function Get-VenvPython {
    $py = Join-Path (Get-ProjectRoot) "client\.venv\Scripts\python.exe"
    if (Test-Path $py) { return $py }
    return $null
}

# Runtime Visual C++ 2015-2022 : UE4SS.dll ne peut pas se charger sans lui.
function Test-VcRedist {
    foreach ($dll in @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll")) {
        if (-not (Test-Path (Join-Path $env:SystemRoot "System32\$dll"))) { return $false }
    }
    return $true
}

# Recharge PATH depuis le registre (après l'installation de Python, par exemple).
function Update-SessionPath {
    $parts = @()
    foreach ($scope in @("Machine", "User")) {
        $v = [Environment]::GetEnvironmentVariable("Path", $scope)
        if ($v) { $parts += $v }
    }
    if ($parts.Count -gt 0) { $env:Path = $parts -join ";" }
}
