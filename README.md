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

The mod launches the client when the game starts and the client exits by itself when the game closes, so nothing runs while you are not playing.

### Data sources (SA DE 1.0.112)

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

HUD titles are read as children of the `MainCanvas` of the two HUD drawers (`Gameterface.CurrentHudDrawer` / `CurrentPriorityHudDrawer`): ~0 ms per tick.

The mission-title filter (`isMissionName` in `main.lua`) discards system messages that go through the same widget (property purchase, checkpoint saved…).

## Installation

### 1. UE4SS in the game folder

1. Download [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (`UE4SS_v3.0.1.zip`) and extract it into
   `…\GTA San Andreas - Definitive Edition\Gameface\Binaries\Win64\` (next to `SanAndreas.exe`).
2. Download [San Andreas UE4SS Signatures](https://www.nexusmods.com/grandtheftautothetrilogy/mods/897) (Nexus Mods, account required) and put the `UE4SS_Signatures\` folder in the same place. Without it, UE4SS does not start on 1.112.
3. If the game folder is read-only for your account (Rockstar Games Launcher install under `Program Files`), run `tools\fix_permissions.ps1` **as administrator**: UE4SS must be able to write its log and cache there.
4. Run `tools\configure_ue4ss.ps1` (forces UE 4.26, disables the UE4SS consoles which crash this game, enables Ctrl+R hot reload, disables the bundled example mods).
5. Run `tools\install_mod.ps1`: copies `mod\BetterPresence` into `Win64\Mods\` and writes `client_path.txt` (path of the client launcher) next to it.

Check: start the game, `Win64\UE4SS.log` must contain `[BetterPresence] v… chargé` and `%LOCALAPPDATA%\GTASADEBetterPresence\state.json` must be updated every second.

### 2. Discord application

1. [discord.com/developers/applications](https://discord.com/developers/applications) → *New Application*. The application **name** is what Discord shows ("Playing …").
2. Copy the *Application ID* into `client/config.json` → `discord_client_id`.
   The displayed title ("Playing …") comes from `activity_name` in `config.json`, independent of the application name (Discord forbids `:` and caps it at 32 characters): default `Grand Theft Auto: San Andreas – The Definitive Edition`, leave empty to use the application name.
3. Optional — *Rich Presence → Art Assets*, upload images named:
   `logo` (large image), `onfoot`, `vehicle`, `menu`, `wanted_1` … `wanted_6` (small images). Ready-made icons are provided in [`assets/`](assets/) (512×512, regenerate with `tools/make_assets.py`); you only have to supply `logo` (game cover). Keys are configurable in `config.json` (`images`); a direct `https://` URL also works.
4. If Discord shows Rockstar's basic presence instead, disable the Discord integration in the Rockstar Games Launcher (or in Discord: *Settings → Registered Games*).

### 3. Python client

```bat
cd client
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
start.bat            rem console mode, logs visible
```

**Automatic lifecycle**: the mod launches the client when the game starts (`start_hidden.vbs` through `os.execute`, a console window flashes for ~100 ms) and the client exits by itself when the game closes (`exit_with_game` in `config.json`). Only one instance runs at a time (Windows mutex). Nothing runs while the game is not running. The launcher path is written by `tools\install_mod.ps1` into `Mods\BetterPresence\client_path.txt`: re-run that script if you move the project.

- `start_hidden.vbs`: manual background start, no window (handy to test without the mod).
- `stop.bat`: stops a client running in the background.
- `python presence.py --once`: prints the state read and the computed presence (debugging).
- `python presence.py --stay`: do not exit when the game closes.
- Logs: `client/presence.log`.

## Customisation

`client/config.json` — `activity_name` (title shown in Discord), displayed texts (`texts`, English by default, freely translatable), image keys, polling interval, maximum age of `state.json` before falling back to the basic presence, `exit_with_game`.

`%LOCALAPPDATA%\GTASADEBetterPresence\flags.txt` (optional, hot-reloaded by the mod) — enables/disables each data source, one `key=0|1` per line: `position`, `gamepad`, `playerinfo`, `titles`, `menu`, `launch_client`, `debug` (raw details in the JSON), `camera`, `misc`, `timing`, `stars_tree`, `titles_scan`.

## Development

- Edit `mod/BetterPresence/Scripts/main.lua`, then run `tools\install_mod.ps1` and press **Ctrl+R** in game (hot reload).
- Lua syntax check without the game: `client\.venv\Scripts\python -c "from lupa import lua54 as L; L.LuaRuntime().compile(open('mod/BetterPresence/Scripts/main.lua', encoding='utf-8').read())"` (`pip install lupa`).
- Exploration dump: create an empty `dump.request` file in the `state.json` folder → `dump_objects.txt` / `dump_widgets.txt`. The full UE4SS dump (Ctrl+J in game → `UE4SS_ObjectDump.txt`) lists every reflected class/function.

### Known pitfalls (UE4SS 3.0.1 + SA DE)

- **`Gameterface:GetMapAreaName()` crashes the game** (crash inside UE4SS, reproduced twice). Hence the district is read from the HUD title.
- **Calling a method on a null UObject crashes the game**: `pcall` does not protect against an access violation. Always check `IsValid()` first.
- `GetAllChildren()` returns a table of `RemoteUnrealParam`: unwrap with `:get()`.
- `FindAllOf` walks the whole `GUObjectArray` (~10 ms per call): only for persistent objects, then cached.
- The UE4SS console (`ConsoleEnablerMod`, GUI) crashes this game: disabled by `configure_ue4ss.ps1`.
- `KismetSystemLibrary.LaunchURL` hands the URL to the default browser instead of executing the file: not usable to start the client, `os.execute` is the only option.

## Limitations

- The district is only known after its name has been displayed once (game load or zone change).
- The current mission is inferred from HUD titles (start / failed / passed / death / arrest): a mission abandoned without any message may stay displayed until the next event.
- The vehicle name comes from the title shown when entering it; if it did not appear (mod loaded mid-drive), "In a vehicle" is shown.

## License

[MIT](LICENSE).
