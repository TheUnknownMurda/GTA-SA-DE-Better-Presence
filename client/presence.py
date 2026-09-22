"""
GTA SA DE Better Presence — client Discord.

Tourne en arrière-plan, détecte SanAndreas.exe et met à jour la Rich Presence
Discord. Les infos détaillées (quartier, véhicule, mission, étoiles) viennent
du mod UE4SS `BetterPresence`, qui écrit périodiquement un fichier JSON :

    %LOCALAPPDATA%\\GTASADEBetterPresence\\state.json

Si le fichier est absent ou trop vieux (mod pas chargé, écran de chargement…),
on retombe sur une présence basique "En jeu" avec le temps écoulé.

Cycle de vie : le mod UE4SS lance ce client au démarrage du jeu (start_hidden.vbs
via KismetSystemLibrary.LaunchURL). Une seule instance tourne à la fois (mutex
Windows) et, par défaut, le client se termine quand le jeu se ferme
(`exit_with_game` dans config.json).

Usage :
    python presence.py            # console, logs visibles
    python presence.py --once     # affiche l'état calculé puis quitte (debug)
    python presence.py --stay     # ne pas quitter quand le jeu se ferme
"""

from __future__ import annotations

import argparse
import ctypes
import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import psutil
from pypresence import Presence
from pypresence.exceptions import DiscordError, DiscordNotFound, PipeClosed

from zones import city_from_ue

HERE = Path(__file__).resolve().parent
CONFIG_PATH = HERE / "config.json"
LOG_PATH = HERE / "presence.log"
STATE_SCHEMA_VERSION = 1

log = logging.getLogger("presence")


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
@dataclass
class Config:
    client_id: str
    process_name: str
    state_file: Path
    poll_interval: float
    state_max_age: float
    min_update_interval: float
    exit_with_game: bool = True
    activity_name: str = ""   # nom affiché ("Playing …") ; vide = nom de l'application Discord
    images: dict[str, str] = field(default_factory=dict)
    texts: dict[str, str] = field(default_factory=dict)

    @staticmethod
    def load(path: Path = CONFIG_PATH) -> "Config":
        raw = json.loads(path.read_text(encoding="utf-8"))
        state_file = raw.get("state_file") or default_state_path()
        return Config(
            client_id=str(raw.get("discord_client_id", "")).strip(),
            process_name=raw.get("game_process_name", "SanAndreas.exe"),
            state_file=Path(os.path.expandvars(state_file)),
            poll_interval=float(raw.get("poll_interval", 1.0)),
            state_max_age=float(raw.get("state_max_age", 10)),
            min_update_interval=float(raw.get("min_update_interval", 4)),
            exit_with_game=bool(raw.get("exit_with_game", True)),
            activity_name=str(raw.get("activity_name") or "").strip(),
            images=raw.get("images", {}),
            texts=raw.get("texts", {}),
        )


def default_state_path() -> str:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    return str(Path(base) / "GTASADEBetterPresence" / "state.json")


# --------------------------------------------------------------------------- #
# État du jeu (contrat avec le mod Lua)
# --------------------------------------------------------------------------- #
@dataclass
class GameState:
    """Ce que le mod UE4SS nous transmet. Tous les champs sont optionnels."""

    timestamp: float = 0.0
    in_game: bool = False
    paused: bool = False
    zone: Optional[str] = None
    city: Optional[str] = None
    vehicle: Optional[str] = None
    in_vehicle: Optional[bool] = None   # None = inconnu (mod ancien / donnée absente)
    mission: Optional[str] = None
    wanted: int = 0
    dead: Optional[str] = None          # "wasted" / "busted"
    radio: Optional[str] = None
    money: Optional[str] = None
    time: Optional[str] = None
    x: Optional[float] = None
    y: Optional[float] = None
    z: Optional[float] = None

    @staticmethod
    def from_json(data: dict[str, Any]) -> "GameState":
        def clean(v: Any) -> Optional[str]:
            if v is None:
                return None
            s = str(v).strip()
            return s or None

        def num(v: Any) -> Optional[float]:
            try:
                return float(v) if v is not None else None
            except (TypeError, ValueError):
                return None

        try:
            wanted = int(data.get("wanted") or 0)
        except (TypeError, ValueError):
            wanted = 0
        in_vehicle = data.get("in_vehicle")
        x, y, z = num(data.get("x")), num(data.get("y")), num(data.get("z"))
        city = clean(data.get("city")) or city_from_ue(x, y, z)
        return GameState(
            timestamp=float(data.get("timestamp") or 0),
            in_game=bool(data.get("in_game", False)),
            paused=bool(data.get("paused", False)),
            zone=clean(data.get("zone")),
            city=city,
            vehicle=clean(data.get("vehicle")),
            in_vehicle=bool(in_vehicle) if in_vehicle is not None else None,
            mission=clean(data.get("mission")),
            wanted=max(0, min(6, wanted)),
            dead=clean(data.get("dead")),
            radio=clean(data.get("radio")),
            money=clean(data.get("money")),
            time=clean(data.get("time")),
            x=x, y=y, z=z,
        )


def read_state(path: Path, max_age: float) -> Optional[GameState]:
    """Lit le fichier d'état. Renvoie None s'il est absent, corrompu ou périmé.

    Le mod peut être en train d'écrire le fichier : une erreur JSON est donc
    normale de temps en temps, on réessaiera au prochain tour.
    """
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except OSError as exc:
        log.debug("Lecture de %s impossible : %s", path, exc)
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    if int(data.get("version", 1)) != STATE_SCHEMA_VERSION:
        log.warning("Version de state.json inattendue : %s", data.get("version"))

    state = GameState.from_json(data)
    # Le mod écrit un timestamp Unix (os.time()). On tolère aussi l'absence de
    # timestamp en se rabattant sur la date de modification du fichier.
    ts = state.timestamp or path.stat().st_mtime
    if time.time() - ts > max_age:
        return None
    return state


# --------------------------------------------------------------------------- #
# Construction de la présence
# --------------------------------------------------------------------------- #
def stars(level: int) -> str:
    return "★" * level


def build_activity(cfg: Config, state: Optional[GameState], start_ts: int) -> dict[str, Any]:
    """Transforme l'état du jeu en payload Rich Presence."""
    t = cfg.texts
    img = cfg.images
    sep = t.get("separator", " · ")

    act: dict[str, Any] = {"start": start_ts}
    # Nom d'activité personnalisé : Discord l'accepte dans SET_ACTIVITY (champ "name"),
    # ce qui contourne les limites du nom d'application (32 caractères, pas de ":").
    if cfg.activity_name:
        act["name"] = cfg.activity_name[:128]
    if img.get("large"):
        act["large_image"] = img["large"]
        act["large_text"] = img.get("large_text") or None

    # --- Pas de données détaillées : présence basique -----------------------
    if state is None:
        act["details"] = t.get("basic_details", "In game")
        act["state"] = t.get("basic_state", "San Andreas")
        return act

    # --- Menus / chargement ------------------------------------------------
    if not state.in_game:
        act["details"] = t.get("menu_details", "In the menus")
        act["state"] = t.get("menu_state") or None
        if img.get("menu"):
            act["small_image"] = img["menu"]
            act["small_text"] = act["details"]
        return act

    # --- En jeu : ligne 1 = lieu --------------------------------------------
    if state.zone and state.city:
        details = t.get("location", "{zone}, {city}").format(zone=state.zone, city=state.city)
    elif state.zone:
        details = t.get("location_no_city", "{zone}").format(zone=state.zone)
    elif state.city:
        details = state.city
    else:
        details = t.get("location_unknown", "Somewhere in San Andreas")
    act["details"] = details

    # --- Ligne 2 = [étoiles] · à pied / véhicule · mission ------------------
    in_vehicle = state.in_vehicle if state.in_vehicle is not None else bool(state.vehicle)
    if in_vehicle and state.vehicle:
        transport = t.get("in_vehicle", "In a {vehicle}").format(vehicle=state.vehicle)
    elif in_vehicle:
        transport = t.get("in_vehicle_unknown", "In a vehicle")
    else:
        transport = t.get("on_foot", "On foot")

    parts: list[str] = []
    if state.dead == "wasted":
        parts.append(t.get("wasted", "Wasted"))
    elif state.dead == "busted":
        parts.append(t.get("busted", "Busted"))
    elif state.paused:
        parts.append(t.get("paused", "Paused"))
    else:
        if state.wanted > 0:
            parts.append(stars(state.wanted))
        parts.append(transport)
    if state.mission:
        parts.append(t.get("mission", "Mission: {mission}").format(mission=state.mission))
    elif not state.dead and not state.paused:
        parts.append(t.get("free_roam", "Free roam"))
    act["state"] = sep.join(parts)

    # --- Petite image : pause > niveau de recherche > véhicule > à pied ------
    if state.paused and img.get("menu"):
        act["small_image"] = img["menu"]
        act["small_text"] = t.get("paused", "Paused")
    elif state.wanted > 0 and img.get("wanted_prefix"):
        act["small_image"] = f"{img['wanted_prefix']}{state.wanted}"
        act["small_text"] = t.get("wanted_small_text", "Wanted level: {level} star(s)").format(level=state.wanted)
    elif in_vehicle and img.get("vehicle"):
        act["small_image"] = img["vehicle"]
        act["small_text"] = transport
    elif not in_vehicle and img.get("on_foot"):
        act["small_image"] = img["on_foot"]
        act["small_text"] = transport

    return act


def truncate_fields(act: dict[str, Any]) -> dict[str, Any]:
    """Discord refuse les champs texte > 128 caractères et < 2 caractères."""
    out = {}
    for k, v in act.items():
        if v is None:
            continue
        if isinstance(v, str) and k in ("details", "state", "large_text", "small_text"):
            v = v.strip()
            if len(v) < 2:
                continue
            if len(v) > 128:
                v = v[:125] + "…"
        out[k] = v
    return out


# --------------------------------------------------------------------------- #
# Instance unique (mutex Windows nommé)
# --------------------------------------------------------------------------- #
MUTEX_NAME = r"Local\GTASADEBetterPresence_Client"
ERROR_ALREADY_EXISTS = 183
_mutex_handle = None  # gardé vivant pour la durée du processus


def acquire_single_instance() -> bool:
    """True si nous sommes la seule instance ; False si une autre tourne déjà."""
    global _mutex_handle
    if os.name != "nt":
        return True
    kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
    handle = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if not handle:
        return True  # impossible de créer le mutex : on ne bloque pas le démarrage
    if kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
        kernel32.CloseHandle(handle)
        return False
    _mutex_handle = handle
    return True


# --------------------------------------------------------------------------- #
# Détection du jeu
# --------------------------------------------------------------------------- #
def find_game(process_name: str) -> Optional[psutil.Process]:
    target = process_name.lower()
    for proc in psutil.process_iter(["name", "create_time"]):
        try:
            if (proc.info["name"] or "").lower() == target:
                return proc
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return None


# --------------------------------------------------------------------------- #
# Boucle principale
# --------------------------------------------------------------------------- #
class PresenceClient:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.rpc: Optional[Presence] = None
        self.last_payload: Optional[dict[str, Any]] = None
        self.last_sent_at = 0.0
        self.next_connect_attempt = 0.0
        self.connect_backoff = 2.0
        self.last_city: Optional[str] = None

    # -- connexion Discord ---------------------------------------------------
    def ensure_connected(self) -> bool:
        if self.rpc is not None:
            return True
        now = time.monotonic()
        if now < self.next_connect_attempt:
            return False
        try:
            rpc = Presence(self.cfg.client_id)
            rpc.connect()
        except (DiscordNotFound, DiscordError, PipeClosed, OSError, ConnectionError) as exc:
            log.info("Discord injoignable (%s). Nouvel essai dans %.0fs.", exc, self.connect_backoff)
            self.next_connect_attempt = now + self.connect_backoff
            self.connect_backoff = min(self.connect_backoff * 2, 60)
            return False
        except Exception as exc:  # noqa: BLE001 — pypresence lève parfois des erreurs génériques
            log.warning("Erreur de connexion Discord inattendue : %s", exc)
            self.next_connect_attempt = now + self.connect_backoff
            self.connect_backoff = min(self.connect_backoff * 2, 60)
            return False
        self.rpc = rpc
        self.connect_backoff = 2.0
        self.last_payload = None
        log.info("Connecté à Discord (client_id=%s).", self.cfg.client_id)
        return True

    def drop_connection(self) -> None:
        if self.rpc is None:
            return
        try:
            self.rpc.clear()
        except Exception:  # noqa: BLE001
            pass
        try:
            self.rpc.close()
        except Exception:  # noqa: BLE001
            pass
        self.rpc = None
        self.last_payload = None
        log.info("Déconnecté de Discord.")

    # -- envoi ---------------------------------------------------------------
    def push(self, payload: dict[str, Any]) -> None:
        if payload == self.last_payload:
            return
        if time.monotonic() - self.last_sent_at < self.cfg.min_update_interval:
            return  # on coalesce, on renverra au prochain tour
        if not self.ensure_connected():
            return
        assert self.rpc is not None
        try:
            self.rpc.update(**payload)
        except (PipeClosed, DiscordError, OSError, ConnectionError) as exc:
            log.warning("Envoi à Discord échoué (%s), reconnexion.", exc)
            self.rpc = None
            self.last_payload = None
            return
        except Exception as exc:  # noqa: BLE001
            log.warning("Erreur d'envoi inattendue : %s", exc)
            self.rpc = None
            self.last_payload = None
            return
        self.last_payload = payload
        self.last_sent_at = time.monotonic()
        log.info("Présence → %s | %s", payload.get("details"), payload.get("state"))

    # -- boucle --------------------------------------------------------------
    def run(self) -> None:
        log.info("Surveillance de %s… (Ctrl+C pour quitter)", self.cfg.process_name)
        game_seen = False
        while True:
            try:
                proc = find_game(self.cfg.process_name)
                if proc is None:
                    if game_seen:
                        log.info("Jeu fermé.")
                        game_seen = False
                        self.drop_connection()
                        if self.cfg.exit_with_game:
                            log.info("Arrêt du client (exit_with_game).")
                            return
                    self.drop_connection()
                    time.sleep(max(self.cfg.poll_interval, 2.0))
                    continue

                if not game_seen:
                    log.info("Jeu détecté (PID %s).", proc.pid)
                    game_seen = True

                state = read_state(self.cfg.state_file, self.cfg.state_max_age)
                if state is not None:
                    # En intérieur (ou position inconnue) on garde la dernière ville vue dehors.
                    if state.city:
                        self.last_city = state.city
                    elif state.in_game:
                        state.city = self.last_city
                start_ts = int(proc.info.get("create_time") or time.time())
                payload = truncate_fields(build_activity(self.cfg, state, start_ts))
                self.push(payload)
                time.sleep(self.cfg.poll_interval)
            except KeyboardInterrupt:
                raise
            except Exception as exc:  # noqa: BLE001 — la boucle ne doit jamais mourir
                log.exception("Erreur dans la boucle principale : %s", exc)
                time.sleep(5)


# --------------------------------------------------------------------------- #
# Entrée
# --------------------------------------------------------------------------- #
def setup_logging(verbose: bool) -> None:
    # La console Windows est souvent en cp1252 : on force l'UTF-8 pour les ★ et accents.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
        except (AttributeError, ValueError):
            pass
    fmt = "%(asctime)s %(levelname)-7s %(message)s"
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    try:
        handlers.append(logging.FileHandler(LOG_PATH, encoding="utf-8"))
    except OSError:
        pass
    logging.basicConfig(level=logging.DEBUG if verbose else logging.INFO, format=fmt, handlers=handlers)


def main() -> int:
    parser = argparse.ArgumentParser(description="Discord Rich Presence pour GTA SA DE")
    parser.add_argument("--once", action="store_true", help="Affiche le payload calculé puis quitte")
    parser.add_argument("--stay", action="store_true", help="Continue de tourner après la fermeture du jeu")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    setup_logging(args.verbose)

    try:
        cfg = Config.load()
    except (OSError, json.JSONDecodeError) as exc:
        log.error("Impossible de lire %s : %s", CONFIG_PATH, exc)
        return 1
    if args.stay:
        cfg.exit_with_game = False

    # Le dossier du fichier d'état doit exister pour que le mod Lua puisse y écrire.
    try:
        cfg.state_file.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        log.warning("Création de %s impossible : %s", cfg.state_file.parent, exc)

    if args.once:
        proc = find_game(cfg.process_name)
        state = read_state(cfg.state_file, cfg.state_max_age)
        start_ts = int(proc.info.get("create_time") or time.time()) if proc else int(time.time())
        print("Jeu :", f"PID {proc.pid}" if proc else "non détecté")
        print("État :", state)
        print("Payload :", json.dumps(truncate_fields(build_activity(cfg, state, start_ts)), ensure_ascii=False, indent=2))
        return 0

    if not cfg.client_id or not cfg.client_id.isdigit():
        log.error("discord_client_id manquant ou invalide dans config.json "
                  "(crée une application sur https://discord.com/developers/applications).")
        return 1

    if not acquire_single_instance():
        log.info("Une autre instance du client tourne déjà, on s'arrête.")
        return 0

    client = PresenceClient(cfg)
    try:
        client.run()
    except KeyboardInterrupt:
        log.info("Arrêt demandé.")
    finally:
        client.drop_connection()
    return 0


if __name__ == "__main__":
    sys.exit(main())
