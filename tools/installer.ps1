# Installateur interactif de GTA SA DE Better Presence.
# Lancer par un double-clic sur Install.bat (à la racine du projet).
#
# Chaque étape reste utilisable séparément : ce menu ne fait qu'appeler les
# scripts tools\*.ps1 et afficher l'état courant de l'installation.
# Compatible Windows PowerShell 5.1 et PowerShell 7.

param([string]$GameWin64)

$ErrorActionPreference = "Stop"

# --- Chargement des fonctions partagées ------------------------------------
# Tout ce bloc est autonome (aucune fonction de common.ps1) puisque c'est
# justement ce fichier que l'on essaie de lire. Copier un dossier d'une machine
# à l'autre laisse souvent des droits NTFS inutilisables ; on répare tout seul
# plutôt que d'exiger de l'utilisateur qu'il s'en occupe.
$projectRoot = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $PSScriptRoot "common.ps1"

function Test-CanRead($path) {
    try {
        $fs = [IO.File]::OpenRead($path)
        $fs.Close()
        return $true
    } catch { return $false }
}

function Repair-FolderAccess($folder) {
    # Rend au dossier des droits hérités normaux, puis s'ajoute explicitement.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls "$folder" /reset /T /C /Q 2>&1 | Out-Null
    & icacls "$folder" /grant "${me}:(OI)(CI)M" /T /C /Q 2>&1 | Out-Null
}

function Repair-FolderAccessElevated($folder) {
    # Quand les fichiers appartiennent à un autre compte (copie depuis une autre
    # machine), il faut d'abord en reprendre la propriété : cela demande l'UAC.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $cmd = "icacls '$folder' /setowner '$me' /T /C /Q; " +
           "icacls '$folder' /reset /T /C /Q; " +
           "icacls '$folder' /grant '${me}:(OI)(CI)M' /T /C /Q"
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd
        )
        return ($p.ExitCode -eq 0)
    } catch { return $false }
}

if (-not (Test-Path $commonPath)) {
    Write-Host ""
    Write-Host "  tools\common.ps1 is missing." -ForegroundColor Red
    Write-Host "  Copy the whole project folder, not just some of its files." -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Get-ChildItem $PSScriptRoot -Filter "*.ps1" -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue

if (-not (Test-CanRead $commonPath)) {
    Write-Host ""
    Write-Host "  Windows is refusing to read the project files." -ForegroundColor Yellow
    Write-Host "  This happens after copying the folder from another computer." -ForegroundColor Gray
    Write-Host "  Repairing the folder permissions..." -ForegroundColor Gray
    Repair-FolderAccess $projectRoot
    Get-ChildItem $PSScriptRoot -Filter "*.ps1" -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
}

if (-not (Test-CanRead $commonPath)) {
    Write-Host "  Still blocked. The files probably belong to another account," -ForegroundColor Gray
    Write-Host "  which needs administrator rights to fix (one UAC prompt)." -ForegroundColor Gray
    $answer = Read-Host "  Repair as administrator? [Y/n]"
    if ($answer -notmatch '^(n|no|non)$') {
        Repair-FolderAccessElevated $projectRoot | Out-Null
    }
}

try {
    . $commonPath
} catch {
    Write-Host ""
    Write-Host "  Windows still refuses to read tools\common.ps1:" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  At this point it is almost always the antivirus." -ForegroundColor Yellow
    Write-Host "    - Open its protection history (Bitdefender, Avast, Norton, Windows Security...)" -ForegroundColor Gray
    Write-Host "      and allow this folder, or add it to the exclusions:" -ForegroundColor Gray
    Write-Host "      $projectRoot" -ForegroundColor White
    Write-Host "    - Windows Security > Ransomware protection > 'Controlled folder access'" -ForegroundColor Gray
    Write-Host "      can also block it; allow powershell.exe or turn it off while installing." -ForegroundColor Gray
    Write-Host ""
    exit 1
}

$root = Get-ProjectRoot
$UE4SS_VERSION = "v3.0.1"
$UE4SS_ZIP = "UE4SS_v3.0.1.zip"
$UE4SS_URL = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/$UE4SS_VERSION/$UE4SS_ZIP"
$SIGNATURES_URL = "https://www.nexusmods.com/grandtheftautothetrilogy/mods/897?tab=files"
$DISCORD_APPS_URL = "https://discord.com/developers/applications"
# Repli quand winget n'est pas disponible : installateur officiel python.org.
$PYTHON_VERSION = "3.13.7"
$PYTHON_URL = "https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-amd64.exe"
$VCREDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

$script:Win64 = $null

# --------------------------------------------------------------------------- #
# Affichage
# --------------------------------------------------------------------------- #
function Write-Title {
    Clear-Host
    Write-Host ""
    Write-Host "  GTA SA DE Better Presence - Installer" -ForegroundColor Cyan
    Write-Host "  Discord Rich Presence for GTA San Andreas: The Definitive Edition" -ForegroundColor DarkGray
    Write-Host "  ------------------------------------------------------------------" -ForegroundColor DarkGray
}

function Write-Status($label, $ok, $detail, $warn) {
    $dots = "." * [Math]::Max(1, 22 - $label.Length)
    if ($ok) {
        $mark = "[ OK ]"; $color = "Green"
    } elseif ($warn) {
        $mark = "[ !  ]"; $color = "Yellow"
    } else {
        $mark = "[ -- ]"; $color = "Red"
    }
    Write-Host ("  {0} {1} " -f $label, $dots) -NoNewline
    Write-Host $mark -ForegroundColor $color -NoNewline
    if ($detail) { Write-Host "  $detail" -ForegroundColor DarkGray } else { Write-Host "" }
}

function Write-Step($text) { Write-Host "`n  > $text" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "    $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }
function Write-Err($text)  { Write-Host "    $text" -ForegroundColor Red }
function Write-Info($text) { Write-Host "    $text" -ForegroundColor Gray }

function Pause-Menu {
    Write-Host ""
    Read-Host "  Press Enter to continue" | Out-Null
}

function Confirm-Action($question) {
    $a = Read-Host "  $question [y/N]"
    return ($a -match '^(y|yes|o|oui)$')
}

# --------------------------------------------------------------------------- #
# État
# --------------------------------------------------------------------------- #
function Get-State {
    $s = @{}
    $s.Win64 = $script:Win64
    $s.GameOk = Test-GameWin64 $s.Win64
    if ($s.GameOk) {
        $s.Writable = Test-WriteAccess $s.Win64
        $s.Ue4ss = (Test-Path (Join-Path $s.Win64 "UE4SS.dll")) -and (Test-Path (Join-Path $s.Win64 "dwmapi.dll"))
        $s.Signatures = Test-Path (Join-Path $s.Win64 "UE4SS_Signatures\StaticConstructObject.lua")
        $s.Configured = $s.Ue4ss -and (Test-Ue4ssConfigured $s.Win64)
        $s.ModVersion = Get-ModVersion $s.Win64
        # client_path.txt : ligne 1 = pythonw.exe du venv, ligne 2 = presence.py.
        $cp = Join-Path $s.Win64 "Mods\BetterPresence\client_path.txt"
        $s.ClientPathOk = $false
        if (Test-Path $cp) {
            $lines = @(Get-Content $cp | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $s.ClientPathOk = ($lines.Count -ge 2) -and
                              ($lines[0] -eq (Join-Path $root "client\.venv\Scripts\pythonw.exe")) -and
                              ($lines[1] -eq (Join-Path $root "client\presence.py"))
        }
    }
    $s.VcRedist = Test-VcRedist
    $s.Python = Find-SystemPython
    $s.Venv = Get-VenvPython
    $s.Deps = $false
    if ($s.Venv) {
        $s.Deps = (Test-Path (Join-Path $root "client\.venv\Lib\site-packages\pypresence")) -and
                  (Test-Path (Join-Path $root "client\.venv\Lib\site-packages\psutil"))
    }
    $s.AppId = Get-DiscordAppId
    $s.DiscordRunning = Test-DiscordRunning
    return $s
}

function Show-Board($s) {
    Write-Title
    Write-Host ""
    Write-Host "  Prerequisites" -ForegroundColor DarkGray
    if ($s.GameOk) {
        Write-Status "Game folder" $true $s.Win64
    } else {
        Write-Status "Game folder" $false "not found - use [2] to choose it"
    }
    Write-Status "Python" ($null -ne $s.Python) $(if ($s.Python) { $s.Python.Version } else { "not installed - use [3]" })
    Write-Status "Visual C++ runtime" $s.VcRedist $(if ($s.VcRedist) { "2015-2022 x64" } else { "needed by UE4SS - use [4]" })
    if ($s.GameOk) {
        Write-Status "Write access" $s.Writable $(if ($s.Writable) { "" } else { "needed by UE4SS - use [5]" })
    }

    Write-Host ""
    Write-Host "  Game" -ForegroundColor DarkGray
    if ($s.GameOk) {
        Write-Status "UE4SS" $s.Ue4ss $(if ($s.Ue4ss) { "$UE4SS_VERSION" } else { "not installed - use [6]" })
        Write-Status "SA signatures" $s.Signatures $(if ($s.Signatures) { "" } else { "required on 1.112 - use [7]" })
        Write-Status "UE4SS settings" $s.Configured $(if ($s.Configured) { "UE 4.26, consoles off, hot reload" } else { "use [8]" })
        if ($s.ModVersion) {
            Write-Status "BetterPresence mod" $s.ClientPathOk "v$($s.ModVersion)$(if (-not $s.ClientPathOk) { ' - launcher path outdated, use [9]' })" (-not $s.ClientPathOk)
        } else {
            Write-Status "BetterPresence mod" $false "not installed - use [9]"
        }
    } else {
        Write-Info "(set the game folder to see these)"
    }

    Write-Host ""
    Write-Host "  Presence" -ForegroundColor DarkGray
    Write-Status "Python client" ($null -ne $s.Venv -and $s.Deps) $(if ($s.Venv -and $s.Deps) { "virtualenv ready" } else { "use [C]" })
    Write-Status "Discord app ID" ($null -ne $s.AppId) $(if ($s.AppId) { $s.AppId } else { "use [D]" })
    Write-Status "Discord running" $s.DiscordRunning $(if ($s.DiscordRunning) { "" } else { "start Discord to see the presence" }) (-not $s.DiscordRunning)
    Write-Host ""
}

function Test-Ready($s) {
    return $s.GameOk -and $s.Python -and $s.VcRedist -and $s.Ue4ss -and $s.Signatures -and
           $s.Configured -and $s.ModVersion -and $s.ClientPathOk -and $s.Venv -and $s.Deps -and $s.AppId
}

# --------------------------------------------------------------------------- #
# Étapes
# --------------------------------------------------------------------------- #
function Step-FindGame {
    Write-Step "Locating the game"
    Write-Info "Searching (running process, Steam, Epic, usual folders)..."
    $found = Find-GameWin64
    if ($found) {
        $script:Win64 = $found
        Save-GamePath $found
        Write-Ok "Found: $found"
        return $true
    }
    Write-Warn "Not found automatically."
    return Step-PickGame
}

function Step-PickGame {
    Write-Info "Select the folder that contains SanAndreas.exe, for example:"
    Write-Info "  ...\GTA San Andreas - Definitive Edition\Gameface\Binaries\Win64"
    $picked = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.BrowseForFolder(0, "Select the Win64 folder (contains SanAndreas.exe)", 0, "")
        if ($folder) { $picked = $folder.Self.Path }
    } catch {
        Write-Warn "Folder picker unavailable."
    }
    if (-not $picked) {
        $picked = (Read-Host "  Paste the folder path (empty to cancel)").Trim('"', ' ')
    }
    if (-not $picked) { Write-Warn "Cancelled."; return $false }

    # Tolérance : dossier racine du jeu, ou n'importe quel dossier au-dessus.
    if (-not (Test-GameWin64 $picked)) {
        $deeper = Find-GameUnder $picked 2
        if ($deeper) { $picked = $deeper }
    }
    if (Test-GameWin64 $picked) {
        $script:Win64 = $picked
        Save-GamePath $picked
        Write-Ok "Game folder set: $picked"
        return $true
    }
    Write-Err "SanAndreas.exe not found in (or under) that folder."
    return $false
}

function Step-InstallUe4ss {
    if (-not (Test-GameWin64 $script:Win64)) { Write-Err "Set the game folder first ([2])."; return $false }
    Write-Step "Installing UE4SS $UE4SS_VERSION"
    if (Test-Path (Join-Path $script:Win64 "UE4SS.dll")) {
        Write-Info "UE4SS is already present."
        if (-not (Confirm-Action "Download and overwrite it anyway?")) { return $true }
    }
    Write-Info "Source : $UE4SS_URL"
    Write-Info "Size   : about 5.5 MB, extracted next to SanAndreas.exe"
    if (-not (Confirm-Action "Download UE4SS now?")) { Write-Warn "Skipped."; return $false }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("bp_ue4ss_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp $UE4SS_ZIP
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Info "Downloading..."
        Invoke-WebRequest -Uri $UE4SS_URL -OutFile $zip -UseBasicParsing
        Write-Info "Extracting..."
        Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp "x") -Force

        # On ne réécrit pas mods.txt s'il existe déjà (il porte nos réglages).
        $src = Join-Path $tmp "x"
        $keepModsTxt = Test-Path (Join-Path $script:Win64 "Mods\mods.txt")
        foreach ($item in Get-ChildItem $src -Recurse -File) {
            $rel = $item.FullName.Substring($src.Length).TrimStart('\')
            if ($keepModsTxt -and $rel -eq "Mods\mods.txt") { continue }
            $dest = Join-Path $script:Win64 $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item $item.FullName $dest -Force
        }
        Write-Ok "UE4SS installed in $($script:Win64)"
        return $true
    } catch {
        Write-Err "Failed: $($_.Exception.Message)"
        Write-Info "You can download $UE4SS_ZIP manually and extract it next to SanAndreas.exe."
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Find-SignatureArchive {
    $dirs = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", $root)
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { continue }
        $hit = Get-ChildItem $d -Filter "*.zip" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "signature|UE4SS_Sig|San.?Andreas.?UE4SS" } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Install-SignatureArchive($zipPath) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("bp_sig_" + [Guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
        $lua = Get-ChildItem $tmp -Recurse -Filter "StaticConstructObject.lua" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $lua) {
            Write-Err "StaticConstructObject.lua not found inside that archive."
            return $false
        }
        $dst = Join-Path $script:Win64 "UE4SS_Signatures"
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Copy-Item (Join-Path $lua.DirectoryName "*") $dst -Recurse -Force
        Write-Ok "Signatures installed in $dst"
        return $true
    } catch {
        Write-Err "Failed: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Step-InstallSignatures {
    if (-not (Test-GameWin64 $script:Win64)) { Write-Err "Set the game folder first ([2])."; return $false }
    Write-Step "Installing the San Andreas UE4SS signatures"
    if (Test-Path (Join-Path $script:Win64 "UE4SS_Signatures\StaticConstructObject.lua")) {
        Write-Info "Already installed."
        if (-not (Confirm-Action "Install again from an archive?")) { return $true }
    }
    Write-Info "UE4SS cannot start on game version 1.112 without this small file."
    Write-Info "It is hosted on Nexus Mods (free account required), so it cannot be"
    Write-Info "downloaded automatically: 'San Andreas UE4SS Signatures' by Holydh."

    $zip = Find-SignatureArchive
    if ($zip) {
        Write-Info "Found an archive that looks like it: $zip"
        if (Confirm-Action "Install from this archive?") { return (Install-SignatureArchive $zip) }
    }
    if (Confirm-Action "Open the download page in your browser?") {
        Start-Process $SIGNATURES_URL
        Write-Info "Download the file, then come back here."
    }
    $path = (Read-Host "  Path of the downloaded .zip (empty to skip)").Trim('"', ' ')
    if (-not $path) { Write-Warn "Skipped - UE4SS will not start until this is installed."; return $false }
    if (-not (Test-Path $path)) { Write-Err "File not found: $path"; return $false }
    return (Install-SignatureArchive $path)
}

function Step-FixPermissions {
    if (-not (Test-GameWin64 $script:Win64)) { Write-Err "Set the game folder first ([2])."; return $false }
    Write-Step "Granting write access to the game folder"
    if (Test-WriteAccess $script:Win64) { Write-Ok "Already writable."; return $true }
    Write-Info "UE4SS must be able to write its log and cache next to SanAndreas.exe."
    Write-Info "A Windows admin prompt (UAC) will appear."
    if (-not (Confirm-Action "Continue?")) { Write-Warn "Skipped."; return $false }
    $script = Join-Path $PSScriptRoot "fix_permissions.ps1"
    $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$script`"", "-GameWin64", "`"$($script:Win64)`""
    )
    if ($p.ExitCode -eq 0 -and (Test-WriteAccess $script:Win64)) { Write-Ok "Write access granted."; return $true }
    Write-Err "Could not grant write access (exit code $($p.ExitCode))."
    return $false
}

function Step-ConfigureUe4ss {
    if (-not (Test-GameWin64 $script:Win64)) { Write-Err "Set the game folder first ([2])."; return $false }
    if (-not (Test-Path (Join-Path $script:Win64 "UE4SS-settings.ini"))) {
        Write-Err "UE4SS is not installed yet ([6])."; return $false
    }
    Write-Step "Configuring UE4SS for San Andreas"
    & (Join-Path $PSScriptRoot "configure_ue4ss.ps1") -GameWin64 $script:Win64 | ForEach-Object { Write-Info $_ }
    return (Test-Ue4ssConfigured $script:Win64)
}

function Step-InstallMod {
    if (-not (Test-GameWin64 $script:Win64)) { Write-Err "Set the game folder first ([2])."; return $false }
    if (-not (Test-Path (Join-Path $script:Win64 "UE4SS.dll"))) { Write-Err "Install UE4SS first ([6])."; return $false }
    Write-Step "Installing the BetterPresence mod"
    & (Join-Path $PSScriptRoot "install_mod.ps1") -GameWin64 $script:Win64 | ForEach-Object { Write-Info $_ }
    $v = Get-ModVersion $script:Win64
    if ($v) { Write-Ok "Mod v$v installed."; return $true }
    return $false
}

function Test-PythonExe($exe, $prefix) {
    try {
        $out = & $exe @($prefix + "--version") 2>&1
        if ($LASTEXITCODE -eq 0 -and "$out" -match "Python 3\.(\d+)" -and [int]$Matches[1] -ge 8) {
            return @{ Exe = $exe; Prefix = $prefix; Version = "$out".Trim() }
        }
    } catch { }
    return $null
}

function Find-SystemPython {
    # 1. Dans le PATH. Le lanceur "py" a besoin de -3 pour choisir Python 3.
    $candidates = @(
        @{ Exe = "py";      Prefix = @("-3") },
        @{ Exe = "python";  Prefix = @() },
        @{ Exe = "python3"; Prefix = @() }
    )
    foreach ($c in $candidates) {
        $cmd = Get-Command $c.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        if ($cmd.Source -like "*WindowsApps*") { continue }  # alias du Microsoft Store
        $found = Test-PythonExe $c.Exe $c.Prefix
        if ($found) { return $found }
    }
    # 2. Emplacements d'installation habituels (PATH pas encore rafraîchi).
    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python"),
        (Join-Path $env:ProgramFiles "Python"),
        "$env:SystemDrive\"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $exes = Get-ChildItem (Join-Path $root "Python3*\python.exe") -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending
        foreach ($exe in $exes) {
            $found = Test-PythonExe $exe.FullName @()
            if ($found) { return $found }
        }
    }
    return $null
}

function Step-InstallPython {
    Write-Step "Installing Python"
    $py = Find-SystemPython
    if ($py) {
        Write-Ok "Already installed: $($py.Version)"
        return $true
    }
    Write-Info "The Discord client is a small Python program, so Python 3 is needed."
    Write-Info "It is installed for your user only - no admin rights, nothing else changed."

    # 1) winget quand il est disponible (installe la version courante, gère le PATH).
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "Installing through winget (Windows package manager)..."
        if (Confirm-Action "Install Python with winget?") {
            & winget install --exact --id Python.Python.3.13 --scope user `
                --accept-source-agreements --accept-package-agreements --silent
            Update-SessionPath
            $py = Find-SystemPython
            if ($py) { Write-Ok "Installed: $($py.Version)"; return $true }
            Write-Warn "winget did not complete; falling back to the python.org installer."
        }
    }

    # 2) Installateur officiel python.org.
    Write-Info "Source : $PYTHON_URL"
    Write-Info "Size   : about 28 MB - the official python.org installer"
    if (-not (Confirm-Action "Download and install Python $PYTHON_VERSION now?")) {
        Write-Warn "Skipped."
        if (Confirm-Action "Open the Python download page instead?") { Start-Process "https://www.python.org/downloads/" }
        return $false
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("bp_python_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $exe = Join-Path $tmp "python-installer.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Info "Downloading..."
        Invoke-WebRequest -Uri $PYTHON_URL -OutFile $exe -UseBasicParsing
        Write-Info "Installing (a progress window appears, this takes a minute)..."
        $p = Start-Process $exe -Wait -PassThru -ArgumentList @(
            "/passive", "InstallAllUsers=0", "PrependPath=1", "Include_launcher=1", "Include_test=0"
        )
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            Write-Err "The Python installer returned code $($p.ExitCode)."
            return $false
        }
        Update-SessionPath
        $py = Find-SystemPython
        if ($py) { Write-Ok "Installed: $($py.Version)"; return $true }
        Write-Err "Python was installed but could not be found - restart this installer."
        return $false
    } catch {
        Write-Err "Failed: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Step-InstallVcRedist {
    Write-Step "Installing the Visual C++ runtime"
    if (Test-VcRedist) { Write-Ok "Already installed."; return $true }
    Write-Info "UE4SS cannot load without the Microsoft Visual C++ 2015-2022 runtime."
    Write-Info "Source : $VCREDIST_URL"
    Write-Info "Size   : about 25 MB, from Microsoft. A Windows admin prompt will appear."
    if (-not (Confirm-Action "Download and install it now?")) { Write-Warn "Skipped."; return $false }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("bp_vcredist_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $exe = Join-Path $tmp "vc_redist.x64.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Info "Downloading..."
        Invoke-WebRequest -Uri $VCREDIST_URL -OutFile $exe -UseBasicParsing
        Write-Info "Installing..."
        $p = Start-Process $exe -Wait -PassThru -Verb RunAs -ArgumentList @("/install", "/passive", "/norestart")
        # 0 = installé, 3010 = redémarrage conseillé, 1638 = version plus récente déjà là
        if ($p.ExitCode -in @(0, 3010, 1638)) { Write-Ok "Visual C++ runtime ready."; return $true }
        Write-Err "The installer returned code $($p.ExitCode)."
        return $false
    } catch {
        Write-Err "Failed: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Step-SetupClient {
    Write-Step "Setting up the Python client"
    $venv = Get-VenvPython
    if (-not $venv) {
        $py = Find-SystemPython
        if (-not $py) {
            Write-Warn "Python 3.8+ was not found - installing it first."
            if (-not (Step-InstallPython)) { return $false }
            $py = Find-SystemPython
            if (-not $py) { return $false }
        }
        Write-Info "Using $($py.Version)"
        Write-Info "Creating the virtual environment (client\.venv)..."
        $venvDir = Join-Path $root "client\.venv"
        & $py.Exe @($py.Prefix + @("-m", "venv", $venvDir))
        $venv = Get-VenvPython
        if (-not $venv) { Write-Err "Virtual environment creation failed."; return $false }
    }
    Write-Info "Installing dependencies (pypresence, psutil)..."
    & $venv -m pip install --quiet --upgrade pip
    & $venv -m pip install --quiet -r (Join-Path $root "client\requirements.txt")
    if ($LASTEXITCODE -ne 0) { Write-Err "pip failed."; return $false }
    Write-Ok "Python client ready."
    return $true
}

function Set-ConfigValue($key, $value) {
    $cfg = Get-ClientConfigPath
    $f = Read-TextFile $cfg
    # Échappement JSON de la valeur, puis échappement du $ pour le moteur de
    # remplacement des expressions régulières ($$ = un $ littéral).
    $escaped = ($value -replace '\\', '\\' -replace '"', '\"').Replace('$', '$$')
    $re = [regex]::new('("' + [regex]::Escape($key) + '"\s*:\s*)"(?:[^"\\]|\\.)*"')
    if (-not $re.IsMatch($f.Text)) { return $false }
    # Méthode d'instance : le 3e paramètre est bien un nombre d'occurrences
    # (la surcharge statique à 4 arguments, elle, attend des RegexOptions).
    $new = $re.Replace($f.Text, '${1}"' + $escaped + '"', 1)
    Write-TextFile $cfg $new $f.Bom
    return $true
}

function Step-SetAppId {
    Write-Step "Discord application"
    Write-Info "Create a free application: it is what Discord shows next to your name."
    Write-Info "1. Open $DISCORD_APPS_URL and click 'New Application'."
    Write-Info "2. Copy its 'Application ID' (a long number)."
    Write-Info "3. Optional: Rich Presence > Art Assets, upload the images from assets\"
    Write-Info "   (onfoot, vehicle, menu, wanted_1..6) plus a 'logo' image of your choice."
    if (Confirm-Action "Open the Discord developer portal?") { Start-Process $DISCORD_APPS_URL }
    $id = (Read-Host "  Application ID (empty to keep current)").Trim()
    if (-not $id) { Write-Warn "Unchanged."; return ($null -ne (Get-DiscordAppId)) }
    if ($id -notmatch '^\d{15,25}$') { Write-Err "That does not look like an application ID (digits only)."; return $false }
    if (-not (Set-ConfigValue "discord_client_id" $id)) { Write-Err "Could not write client\config.json."; return $false }
    Write-Ok "Application ID saved."

    $name = (Read-Host "  Displayed title (empty to keep 'Grand Theft Auto: San Andreas - The Definitive Edition')").Trim()
    if ($name) {
        if (Set-ConfigValue "activity_name" $name) { Write-Ok "Displayed title saved." }
    }
    return $true
}

function Step-Test {
    Write-Step "Checking the client"
    $venv = Get-VenvPython
    if (-not $venv) { Write-Err "Set up the Python client first ([C])."; return }
    $env:PYTHONIOENCODING = "utf-8"
    & $venv (Join-Path $root "client\presence.py") --once 2>&1 | ForEach-Object { Write-Info $_ }
    Write-Host ""
    Write-Info "'Game: not detected' is normal when the game is not running."
    Write-Info "Start the game: the mod launches the client by itself, and the client"
    Write-Info "stops when you quit the game. Logs: client\presence.log"
}

function Step-Uninstall {
    Write-Step "Uninstall"
    if (-not (Test-GameWin64 $script:Win64)) { Write-Err "Game folder unknown."; return }
    Write-Info "This removes the mod from the game folder. UE4SS itself is kept"
    Write-Info "unless you ask for it below. Nothing is deleted from the project folder."
    if (-not (Confirm-Action "Remove Mods\BetterPresence?")) { Write-Warn "Cancelled."; return }
    Remove-Item (Join-Path $script:Win64 "Mods\BetterPresence") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Mod removed."
    if (Confirm-Action "Also remove UE4SS (dwmapi.dll, UE4SS.dll, UE4SS-settings.ini, Mods, UE4SS_Signatures)?") {
        foreach ($n in @("dwmapi.dll", "UE4SS.dll", "UE4SS-settings.ini", "UE4SS-settings.ini.bak", "UE4SS.log", "UE4SS_ObjectDump.txt")) {
            Remove-Item (Join-Path $script:Win64 $n) -Force -ErrorAction SilentlyContinue
        }
        foreach ($n in @("Mods", "UE4SS_Signatures")) {
            Remove-Item (Join-Path $script:Win64 $n) -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Ok "UE4SS removed - the game is back to its original files."
    }
    if (Confirm-Action "Remove the saved state folder (%LOCALAPPDATA%\GTASADEBetterPresence)?") {
        Remove-Item (Join-Path $env:LOCALAPPDATA "GTASADEBetterPresence") -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "State folder removed."
    }
}

function Step-FullInstall {
    $s = Get-State
    if (-not $s.GameOk) { if (-not (Step-FindGame)) { return } }
    $s = Get-State
    if (-not $s.Python) { Step-InstallPython | Out-Null }
    $s = Get-State
    if (-not $s.VcRedist) { Step-InstallVcRedist | Out-Null }
    $s = Get-State
    if (-not $s.Writable) { Step-FixPermissions | Out-Null }
    $s = Get-State
    if (-not $s.Ue4ss) { if (-not (Step-InstallUe4ss)) { return } }
    $s = Get-State
    if (-not $s.Signatures) { Step-InstallSignatures | Out-Null }
    Step-ConfigureUe4ss | Out-Null
    Step-InstallMod | Out-Null
    $s = Get-State
    if (-not ($s.Venv -and $s.Deps)) { if (-not (Step-SetupClient)) { return } }
    $s = Get-State
    if (-not $s.AppId) { Step-SetAppId | Out-Null }

    $s = Get-State
    Write-Host ""
    if (Test-Ready $s) {
        Write-Host "  All set. Start the game: the presence appears by itself." -ForegroundColor Green
        if (-not $s.DiscordRunning) { Write-Warn "Discord is not running - start it, or the presence has nowhere to show." }
    } else {
        Write-Warn "Some steps are still missing - see the list above."
    }
}

# --------------------------------------------------------------------------- #
# Menu
# --------------------------------------------------------------------------- #
Unblock-ProjectFiles
$script:Win64 = Resolve-GameWin64 $GameWin64

while ($true) {
    $s = Get-State
    Show-Board $s
    Write-Host "  [1] Install everything (recommended)" -ForegroundColor White
    Write-Host ""
    Write-Host "  [2] Choose the game folder            [6] Install UE4SS"
    Write-Host "  [3] Install Python                    [7] Install SA signatures"
    Write-Host "  [4] Install Visual C++ runtime        [8] Configure UE4SS"
    Write-Host "  [5] Fix folder permissions            [9] Install / update the mod"
    Write-Host ""
    Write-Host "  [C] Set up the Python client          [D] Set the Discord application"
    Write-Host "  [T] Test the client                   [U] Uninstall            [Q] Quit"
    Write-Host ""
    $choice = (Read-Host "  Your choice").Trim().ToUpper()

    switch ($choice) {
        "1" { Step-FullInstall; Pause-Menu }
        "2" { Step-PickGame | Out-Null; Pause-Menu }
        "3" { Step-InstallPython | Out-Null; Pause-Menu }
        "4" { Step-InstallVcRedist | Out-Null; Pause-Menu }
        "5" { Step-FixPermissions | Out-Null; Pause-Menu }
        "6" { Step-InstallUe4ss | Out-Null; Pause-Menu }
        "7" { Step-InstallSignatures | Out-Null; Pause-Menu }
        "8" { Step-ConfigureUe4ss | Out-Null; Pause-Menu }
        "9" { Step-InstallMod | Out-Null; Pause-Menu }
        "C" { Step-SetupClient | Out-Null; Pause-Menu }
        "D" { Step-SetAppId | Out-Null; Pause-Menu }
        "T" { Step-Test; Pause-Menu }
        "U" { Step-Uninstall; Pause-Menu }
        "Q" { Write-Host ""; return }
        default { }
    }
}
