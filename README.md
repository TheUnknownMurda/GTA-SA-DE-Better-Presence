# GTA SA DE Better Presence

Detailed Discord Rich Presence for **Grand Theft Auto: San Andreas – The Definitive Edition** (PC, v1.0.112):

> **Jefferson, Los Santos**
> ★★ · In a Greenwood · Mission: Big Smoke
> 🕑 1:23:45 elapsed

Shows in real time: district + city, on foot / vehicle name, wanted level, current mission, pause, Wasted/Busted, menus.

## How it works

```
Game (UE4) ──UE4SS──> BetterPresence Lua mod ──> %LOCALAPPDATA%\GTASADEBetterPresence\state.json
                                                          │
                          Python client (pypresence) <────┘ ──> Discord (local IPC)
```

- **`mod/BetterPresence/`** — Lua mod for [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Reads the game state through Unreal reflection (the `BP_SanAndreasInterface_C` game interface and HUD widgets) and writes a JSON file every second. No raw memory reads, no hard-coded offsets: it survives game patches better.
- **`client/`** — background Python program: detects `SanAndreas.exe`, reads the JSON and updates Discord. Falls back to a basic presence ("In game" + elapsed time) when the mod is not responding.

The mod starts the client when the game starts, and the client exits by itself when the game closes, so nothing runs while you are not playing.

---

# Installation

Everything is done by hand, step by step. Count about 15 minutes the first time.
Optional PowerShell helpers are provided for two of the steps, but every step can
be done manually and the manual way is written out below.

## What you need

| | Requirement | Where to get it | Size |
|---|---|---|---|
| 1 | **The game**, version 1.0.112 (Rockstar Launcher, Steam or Epic) | already installed | — |
| 2 | **Python 3.8 or newer** | [python.org/downloads](https://www.python.org/downloads/) | ~28 MB |
| 3 | **Visual C++ 2015-2022 runtime (x64)** | [aka.ms/vs/17/release/vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe) | ~25 MB |
| 4 | **UE4SS 3.0.1** | [GitHub release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) → `UE4SS_v3.0.1.zip` | ~5 MB |
| 5 | **San Andreas UE4SS signatures** | [Nexus Mods](https://www.nexusmods.com/grandtheftautothetrilogy/mods/897) (free account needed) | ~1 KB |
| 6 | **A Discord application** (free, you create it) | [discord.com/developers/applications](https://discord.com/developers/applications) | — |
| 7 | **This project** | *Code → Download ZIP* at the top of this page | ~1 MB |

Extract this project anywhere you like, for example `C:\BetterPresence`. Keep the
folder where it is afterwards — the game is told where to find it during step 6.

**First, find your game folder.** You need the folder that contains
`SanAndreas.exe`. It is called `Win64` and sits here, depending on the store:

| Store | Typical path |
|---|---|
| Rockstar Launcher | `C:\Program Files\Rockstar Games\GTA San Andreas - Definitive Edition\Gameface\Binaries\Win64` |
| Steam | `C:\Program Files (x86)\Steam\steamapps\common\GTA San Andreas - The Definitive Edition\Gameface\Binaries\Win64` |
| Epic Games | `C:\Program Files\Epic Games\<folder>\Gameface\Binaries\Win64` |

Throughout this guide, **`<Win64>`** means that folder. Keep an Explorer window
open on it — most steps happen there.

---

## Step 1 — Install Python

1. Download Python from [python.org/downloads](https://www.python.org/downloads/) and run the installer.
2. On the first screen, **tick “Add python.exe to PATH”**, then click *Install Now*.

**Check:** press `Win+R`, type `cmd`, press Enter, then type:

```bat
python --version
```

It must answer something like `Python 3.13.7`. If it says the command is not
found, reinstall Python and make sure the PATH box is ticked.

## Step 2 — Install the Visual C++ runtime

UE4SS cannot load without it, and the game does not ship it.

1. Download [vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe) and run it.
2. If it says *“already installed”*, you are done — close it.

## Step 3 — Install UE4SS in the game folder

1. Download `UE4SS_v3.0.1.zip` from the [UE4SS 3.0.1 release page](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
   (under *Assets*, at the bottom).
2. **Right-click the downloaded .zip → Properties → tick “Unblock” → OK.**
   Windows blocks files downloaded from the internet, and UE4SS will not load otherwise.
3. Extract the contents of the zip **into `<Win64>`**, next to `SanAndreas.exe`.

**Check:** `<Win64>` now contains `dwmapi.dll`, `UE4SS.dll`, `UE4SS-settings.ini` and a `Mods` folder.

## Step 4 — Add the San Andreas signature file

Without this file UE4SS refuses to start on game version 1.112.

1. Open [San Andreas UE4SS Signatures](https://www.nexusmods.com/grandtheftautothetrilogy/mods/897) on Nexus Mods
   (a free account is required to download; use *Manual download* / *Slow download*).
2. Extract the archive, then copy its **`UE4SS_Signatures` folder into `<Win64>`**.

**Check:** the file `<Win64>\UE4SS_Signatures\StaticConstructObject.lua` exists.

## Step 5 — Configure UE4SS

Open `<Win64>\UE4SS-settings.ini` in Notepad and change these five lines
(they are scattered in the file; use `Ctrl+F` to find each one):

| Setting | Set it to | Why |
|---|---|---|
| `MajorVersion` | `4` | the game runs on Unreal Engine 4.26 |
| `MinorVersion` | `26` | idem |
| `GuiConsoleEnabled` | `0` | the UE4SS console crashes this game |
| `GuiConsoleVisible` | `0` | idem |
| `GraphicsAPI` | `dx11` | avoids a crash on startup |

Optional but handy: set `EnableHotReloadSystem` to `1` — you can then press
`Ctrl+R` in game to reload the mod without restarting.

Then open `<Win64>\Mods\mods.txt` and set every line to `0` **except `Keybinds`**:

```
CheatManagerEnablerMod : 0
ActorDumperMod : 0
ConsoleCommandsMod : 0
ConsoleEnablerMod : 0
SplitScreenMod : 0
LineTraceMod : 0
BPModLoaderMod : 0
BPML_GenericFunctions : 0
jsbLuaProfilerMod : 0
Keybinds : 1
```

> **Shortcut:** instead of steps 5, right-click `tools\configure_ue4ss.ps1` →
> *Run with PowerShell*. It makes exactly these changes and keeps a `.bak` copy.

## Step 6 — Install the mod

1. Copy the folder **`mod\BetterPresence`** (from this project) into **`<Win64>\Mods\`**.
   You should end up with `<Win64>\Mods\BetterPresence\Scripts\main.lua`.
2. In `<Win64>\Mods\BetterPresence\`, create a text file named **`client_path.txt`**
   containing exactly two lines: the Python interpreter, then the client script.
   Replace `C:\BetterPresence` with wherever you extracted this project:

```
C:\BetterPresence\client\.venv\Scripts\pythonw.exe
C:\BetterPresence\client\presence.py
```

This is how the game knows what to launch. If you move the project later, update
this file (or re-run the shortcut below).

> **Shortcut:** right-click `tools\install_mod.ps1` → *Run with PowerShell*.
> It copies the mod and writes `client_path.txt` with the right paths.

## Step 7 — Set up the Python client

Open a Command Prompt **in the project folder** (in Explorer, type `cmd` in the
address bar and press Enter), then run these three lines:

```bat
cd client
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
```

**Check:** the folder `client\.venv\Scripts\` now contains `python.exe` and `pythonw.exe`.

## Step 8 — Create your Discord application

Discord only displays a presence that belongs to an application of yours.

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → **New Application**.
   The name can be anything; it is not what players see (see below).
2. Copy the **Application ID** (a long number) from *General Information*.
3. Open `client\config.json` in Notepad and paste it between the quotes:

```json
"discord_client_id": "PASTE_YOUR_ID_HERE",
```

4. **Images (optional but recommended).** In the application, go to
   *Rich Presence → Art Assets* and upload the pictures from this project's
   [`assets/`](assets/) folder: `onfoot`, `vehicle`, `menu`, `wanted_1` … `wanted_6`.
   Add your own large image named `logo` (a cover of the game, for example).
   **The asset name must match the file name**, without `.png`.
5. The title shown in Discord comes from `activity_name` in `config.json`, not from
   the application name — Discord forbids `:` in application names and caps them at
   32 characters. It ships as
   `Grand Theft Auto: San Andreas – The Definitive Edition`; change it if you like.

## Step 9 — Allow the game folder to be written to (only if needed)

If your game is installed under `C:\Program Files`, UE4SS may not be able to write
its log there, which makes troubleshooting impossible. To check: try creating a new
text file inside `<Win64>`. If Windows refuses, do this once:

Right-click `<Win64>` → *Properties* → *Security* → *Edit* → select your user
account → tick **Modify** → *OK*.

> **Shortcut:** right-click `tools\fix_permissions.ps1` → *Run with PowerShell as administrator*.

---

# Checking that it works

1. Make sure **Discord is running**.
2. Start the game and load a save.
3. Your Discord profile should show the presence within a few seconds.

If it does not, check these two files, in this order:

| File | What you should see |
|---|---|
| `<Win64>\UE4SS.log` | a line `[BetterPresence] v0.7.0 loaded` and, a bit later, `Discord client launched` |
| `client\presence.log` | `Game detected (PID …)`, `Connected to Discord`, then presence lines |

And `%LOCALAPPDATA%\GTASADEBetterPresence\state.json` should change every second
while you play (paste that path in Explorer's address bar).

## If something goes wrong

| Symptom | Cause and fix |
|---|---|
| The game crashes on startup with *Fatal error* | The UE4SS console is enabled or the signature file is missing — re-check steps 4 and 5. |
| No `UE4SS.log` appears at all | UE4SS is not loading: the zip was not unblocked (step 3), or the Visual C++ runtime is missing (step 2), or the game folder is not writable (step 9). |
| `UE4SS.log` says `Client not found` | The paths in `client_path.txt` are wrong, or `client\.venv` does not exist yet — redo steps 6 and 7. |
| The presence shows “In game — San Andreas” only | The client is running but the mod is not feeding it: look for `[BetterPresence]` lines in `UE4SS.log`. |
| Nothing at all in Discord | Discord is not running, the Application ID is wrong, or Discord is set to hide your activity (*Settings → Activity Privacy*). |
| Rockstar's own presence shows instead | Turn off the Discord integration in the Rockstar Games Launcher, or in Discord under *Settings → Registered Games*. |
| Images do not show | The asset names in *Art Assets* must match `config.json` exactly; newly uploaded assets can take a few minutes to appear. |

### A word about antivirus software

A game mod that injects a DLL into a process (UE4SS) and a program that launches
another program (this mod starting the Python client) look, from a distance, like
things malware does. Some antivirus products — Bitdefender in particular — block
them. If your antivirus flags the project or the game folder, add an exception for
both folders, or check its quarantine and restore what it took. Nothing here
connects to anything except Discord's local socket on your own machine; the whole
source is in this repository and can be read in a few minutes.

---

# Everyday use

Nothing to start by hand: the mod launches the client when the game starts, and the
client exits when the game closes. Only one instance runs at a time.

| File | What it does |
|---|---|
| `client\start.bat` | runs the client in a console window, logs visible (testing) |
| `client\start_background.bat` | runs it in the background, no window |
| `client\stop.bat` | stops a client running in the background |
| `client\presence.py --once` | prints the state read and the presence it would send |
| `client\presence.py --stay` | do not exit when the game closes |

## Customisation

`client/config.json` — `activity_name` (the title shown in Discord), the displayed
texts (`texts`, English by default, translate them freely), image keys, polling
interval, and `exit_with_game`.

`%LOCALAPPDATA%\GTASADEBetterPresence\flags.txt` (optional, re-read by the mod every
two seconds) — turns each data source on or off, one `key=0|1` per line:
`position`, `gamepad`, `playerinfo`, `titles`, `menu`, `launch_client`,
`debug` (raw details in the JSON), `camera`, `misc`, `timing`, `stars_tree`, `titles_scan`.

## Updating the mod

Replace `<Win64>\Mods\BetterPresence\Scripts\main.lua` with the new version (keep
your `client_path.txt`), then restart the game — or press `Ctrl+R` in game if you
enabled hot reload.

---

# Data sources (SA DE 1.0.112)

| Info | Source |
|---|---|
| In game / main menu | `Gameterface:IsPlayingGame()` |
| Paused | `Gameterface.CurrentMenu` is valid |
| Position → city | `Gameterface:GetGTAPlayerPosition()` (Unreal cm; `SA_x = x/100`, `SA_y = −y/100`), city from the geographic regions in `client/zones.py` |
| District | HUD title `UI_HUDItem_TitleText_Area_C` (shown on every zone change) |
| On foot / in vehicle | `Gameterface:GetAppropriateGamepadTab()` → 0 on foot, 1 in a vehicle |
| Vehicle name | HUD title `UI_HUDItem_TitleText_Vehicle_C` (shown when entering a vehicle) |
| Wanted stars | `UI_HUDItem_PlayerInfo_SA_C.Star1..6`: bright `Brush.TintColor` = lit star; `WantedStarsBox` hidden = 0 stars |
| Mission | HUD title `UI_HUDItem_TitleText_Mission_C`; cleared on *MissionFailed*, the "Mission passed" screen, Wasted, Busted |
| Money, clock, radio | `MoneyText`, `TimeText`, title `UI_HUDItem_TitleText_Radio_SA_C` (in the JSON, not displayed by default) |

HUD titles are read as children of the `MainCanvas` of the two HUD drawers
(`Gameterface.CurrentHudDrawer` / `CurrentPriorityHudDrawer`): ~0 ms per tick.
The mission-title filter (`isMissionName` in `main.lua`) discards system messages
that go through the same widget (property purchase, checkpoint saved…).

# Development

- Edit `mod/BetterPresence/Scripts/main.lua`, copy it into `<Win64>\Mods\BetterPresence\Scripts\`
  (or run `tools\install_mod.ps1`) and press **Ctrl+R** in game to hot reload.
- Lua syntax check without the game:
  `client\.venv\Scripts\python -c "from lupa import lua54 as L; L.LuaRuntime().compile(open('mod/BetterPresence/Scripts/main.lua', encoding='utf-8').read())"` (`pip install lupa`).
- Exploration dump: create an empty `dump.request` file next to `state.json` →
  `dump_objects.txt` / `dump_widgets.txt`. The full UE4SS dump (Ctrl+J in game →
  `UE4SS_ObjectDump.txt`) lists every reflected class and function.
- `tools\common.ps1` holds the shared helpers of the optional scripts (game
  detection, text files).

### Known pitfalls (UE4SS 3.0.1 + SA DE)

- **`Gameterface:GetMapAreaName()` crashes the game** (crash inside UE4SS, reproduced twice). Hence the district is read from the HUD title.
- **Calling a method on a null UObject crashes the game**: `pcall` does not protect against an access violation. Always check `IsValid()` first.
- `GetAllChildren()` returns a table of `RemoteUnrealParam`: unwrap with `:get()`.
- `FindAllOf` walks the whole `GUObjectArray` (~10 ms per call): only for persistent objects, then cached.
- The UE4SS console (`ConsoleEnablerMod`, GUI) crashes this game.
- `KismetSystemLibrary.LaunchURL` hands the URL to the default browser instead of executing the file: not usable to start the client, `os.execute` is the only option.
- A `.vbs` launcher starting a hidden process gets flagged by antivirus software; `pythonw.exe` needs no such wrapper.
- In Windows PowerShell 5.1, `"text".StartsWith([char]0xFEFF)` is **true** for any string (culture-sensitive comparison ignores the BOM character), which silently eats the first character of BOM-less files: detect the BOM on the raw bytes instead.

# Limitations

- The district is only known after its name has been displayed once (game load or zone change).
- The current mission is inferred from HUD titles (start / failed / passed / death / arrest): a mission abandoned without any message may stay displayed until the next event.
- The vehicle name comes from the title shown when entering it; if it did not appear (mod loaded mid-drive), "In a vehicle" is shown.

# License

[MIT](LICENSE).
