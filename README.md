# GTA SA DE Better Presence

Discord Rich Presence détaillée pour **Grand Theft Auto: San Andreas – The Definitive Edition** (PC, v1.0.112) :

> **Jefferson, Los Santos**
> ★★ · In a Greenwood · Mission: Big Smoke
> 🕑 1:23:45 elapsed

Affiche en temps réel : quartier + ville, à pied / nom du véhicule, niveau de recherche, mission en cours, pause, Wasted/Busted, menus.

## Comment ça marche

```
Jeu (UE4) ──UE4SS──> mod Lua BetterPresence ──> %LOCALAPPDATA%\GTASADEBetterPresence\state.json
                                                         │
                          client Python (pypresence) <───┘ ──> Discord (IPC local)
```

- **`mod/BetterPresence/`** — mod Lua pour [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Lit l'état via la réflexion Unreal (interface `BP_SanAndreasInterface_C`, widgets du HUD) et écrit un JSON chaque seconde. Aucune lecture mémoire brute, aucun offset : résiste mieux aux patchs.
- **`client/`** — programme Python en arrière-plan : détecte `SanAndreas.exe`, lit le JSON, met à jour Discord. Retombe sur une présence basique (« En jeu » + temps) si le mod ne répond pas.

### Sources de données (SA DE 1.0.112)

| Info | Source |
|---|---|
| En jeu / menu principal | `Gameterface:IsPlayingGame()` |
| Pause | `Gameterface.CurrentMenu` valide |
| Position → ville | `Gameterface:GetGTAPlayerPosition()` (cm Unreal ; `SA_x = x/100`, `SA_y = −y/100`), ville par zones géographiques dans `client/zones.py` |
| Quartier | titre HUD `UI_HUDItem_TitleText_Area_C` (affiché à chaque changement de zone) |
| À pied / véhicule | `Gameterface:GetAppropriateGamepadTab()` → 0 à pied, 1 en véhicule |
| Nom du véhicule | titre HUD `UI_HUDItem_TitleText_Vehicle_C` (affiché à l'entrée) |
| Étoiles | `UI_HUDItem_PlayerInfo_SA_C.Star1..6` : `Brush.TintColor` clair = allumée ; `WantedStarsBox` cachée = 0 |
| Mission | titre HUD `UI_HUDItem_TitleText_Mission_C` ; effacée sur *MissionFailed*, « Mission passed », Wasted, Busted |
| Argent, heure, radio | `MoneyText`, `TimeText`, titre `UI_HUDItem_TitleText_Radio_SA_C` (dans le JSON, non affichés par défaut) |

Les titres HUD sont lus comme enfants de `MainCanvas` des deux HUD drawers (`Gameterface.CurrentHudDrawer` / `CurrentPriorityHudDrawer`) : coût ~0 ms par tick.

## Installation

### 1. UE4SS dans le jeu

1. Télécharge [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (`UE4SS_v3.0.1.zip`) et décompresse-le dans
   `…\GTA San Andreas - Definitive Edition\Gameface\Binaries\Win64\` (à côté de `SanAndreas.exe`).
2. Télécharge [San Andreas UE4SS Signatures](https://www.nexusmods.com/grandtheftautothetrilogy/mods/897) (Nexus, compte requis) et place le dossier `UE4SS_Signatures\` au même endroit. Sans lui, UE4SS ne démarre pas sur la 1.112.
3. Si le dossier du jeu est en lecture seule pour ton compte (installation Rockstar Launcher dans `Program Files`), exécute **en administrateur** `tools\fix_permissions.ps1` : UE4SS doit pouvoir y écrire son log et son cache.
4. Exécute `tools\configure_ue4ss.ps1` (force UE 4.26, désactive les consoles UE4SS qui plantent sur ce jeu, active le hot reload Ctrl+R, désactive les mods d'exemple).
5. Exécute `tools\install_mod.ps1` : copie `mod\BetterPresence` dans `Win64\Mods\`.

Vérification : lance le jeu, `Win64\UE4SS.log` doit contenir `[BetterPresence] v… chargé` et `%LOCALAPPDATA%\GTASADEBetterPresence\state.json` se met à jour chaque seconde.

### 2. Application Discord

1. [discord.com/developers/applications](https://discord.com/developers/applications) → *New Application*. Le **nom** de l'application est ce que Discord affiche (« Joue à … »).
2. Copie l'*Application ID* dans `client/config.json` → `discord_client_id`.
3. Optionnel — *Rich Presence → Art Assets*, uploade des images nommées :
   `logo` (grande image), `onfoot`, `vehicle`, `menu`, `wanted_1` … `wanted_6` (petites images). Des icônes prêtes à l'emploi sont fournies dans [`assets/`](assets/) (512×512, régénérables avec `tools/make_assets.py`) ; il te reste à fournir `logo` (jaquette du jeu). Les clés sont modifiables dans `config.json` (`images`), une URL `https://` directe fonctionne aussi.
4. Si Discord affiche la présence Rockstar de base à la place, désactive l'intégration Discord dans le Rockstar Games Launcher (ou dans Discord : *Paramètres → Activités enregistrées*).

### 3. Client Python

```bat
cd client
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
start.bat            rem console, logs visibles
```

- `start_hidden.vbs` : lance en arrière-plan sans fenêtre (crée un raccourci dans `shell:startup` pour le démarrer avec Windows). Le client attend le jeu et ne consomme rien tant qu'il n'est pas lancé.
- `stop.bat` : arrête le client lancé en arrière-plan.
- `python presence.py --once` : affiche l'état lu et la présence calculée (débogage).
- Logs : `client/presence.log`.

## Personnalisation

`client/config.json` — textes affichés (`texts`, en anglais par défaut, traduisibles librement), clés d'images, intervalle de lecture, âge maximal de `state.json` avant repli en présence basique.

`%LOCALAPPDATA%\GTASADEBetterPresence\flags.txt` (optionnel, relu à chaud par le mod) — active/désactive chaque source, `clé=0|1` par ligne : `position`, `gamepad`, `playerinfo`, `titles`, `menu`, `debug` (détails bruts dans le JSON), `camera`, `misc`, `timing`, `stars_tree`, `titles_scan`.

## Développement

- Modifie `mod/BetterPresence/Scripts/main.lua`, puis `tools\install_mod.ps1` et **Ctrl+R** en jeu (hot reload).
- Vérif. syntaxe Lua sans le jeu : `client\.venv\Scripts\python -c "from lupa import lua54 as L; L.LuaRuntime().compile(open('mod/BetterPresence/Scripts/main.lua', encoding='utf-8').read())"` (`pip install lupa`).
- Dump d'exploration : crée un fichier vide `dump.request` dans le dossier de `state.json` → `dump_objects.txt` / `dump_widgets.txt`. Le dump complet UE4SS (Ctrl+J en jeu → `UE4SS_ObjectDump.txt`) liste toutes les classes/fonctions réfléchies.

### Pièges connus (UE4SS 3.0.1 + SA DE)

- **`Gameterface:GetMapAreaName()` plante le jeu** (crash dans UE4SS, testé 2×). D'où la lecture du quartier via le titre HUD.
- **Appeler une méthode sur un UObject nul plante le jeu** : `pcall` ne protège pas d'une violation d'accès. Toujours `IsValid()` avant.
- `GetAllChildren()` renvoie une table de `RemoteUnrealParam` : déballer avec `:get()`.
- `FindAllOf` parcourt tout `GUObjectArray` (~10 ms par appel) : à réserver aux objets persistants, mis en cache.
- La console UE4SS (`ConsoleEnablerMod`, GUI) plante sur ce jeu : désactivée par `configure_ue4ss.ps1`.

## Limites

- Le quartier n'est connu qu'après le premier affichage de son nom (chargement de partie ou changement de zone).
- La mission en cours est déduite des titres HUD (début / échec / réussite / mort / arrestation) : une mission abandonnée sans message peut rester affichée jusqu'au prochain événement.
- Le nom du véhicule vient du titre affiché à l'entrée ; s'il n'est pas apparu (mod chargé en cours de route), on affiche « En véhicule ».

## Licence

[MIT](LICENSE).
