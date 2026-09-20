"""
Géographie de San Andreas : ville / comté à partir des coordonnées.

Le mod envoie la position en unités Unreal (cm, axe Y inversé). Conversion
vérifiée empiriquement : SA_x = UE_x / 100, SA_y = -UE_y / 100, SA_z = UE_z / 100.

Les frontières ci-dessous reprennent (approximativement) les grandes zones
« niveau » de info.zon du jeu original : LA / SF / VE et les comtés.
"""

from __future__ import annotations

from typing import Optional


def ue_to_sa(x: float, y: float, z: float = 0.0) -> tuple[float, float, float]:
    return x / 100.0, -y / 100.0, z / 100.0


def city_from_sa(x: float, y: float) -> str:
    """Ville ou comté pour des coordonnées SA (mètres)."""
    # Bande sud (Los Santos, Flint County, Whetstone)
    if y < -768:
        if x < -1213:
            return "Whetstone"
        if x < 44:
            return "Flint County"
        return "Los Santos"
    # Bande centrale (San Fierro à l'ouest, Red County à l'est)
    if y < 596:
        if x < -1213:
            return "San Fierro"
        return "Red County"
    # Bande nord (San Fierro nord / Tierra Robada / Bone County / Las Venturas)
    if x < -1213:
        return "San Fierro" if y < 1659 else "Tierra Robada"
    if x < -480:
        return "Tierra Robada"
    if x < 869:
        return "Bone County"
    return "Las Venturas"


INTERIOR_MIN_Z = 500.0  # les intérieurs de SA sont placés très haut (≈ 1000 m), hors carte


def is_interior_ue(z: Optional[float]) -> bool:
    return z is not None and z / 100.0 > INTERIOR_MIN_Z


def city_from_ue(x: Optional[float], y: Optional[float], z: Optional[float] = None) -> Optional[str]:
    """Ville pour une position Unreal. None si inconnue, hors carte ou en intérieur
    (les intérieurs ont des coordonnées sans rapport avec le quartier réel)."""
    if x is None or y is None or is_interior_ue(z):
        return None
    sx, sy, _ = ue_to_sa(x, y)
    if abs(sx) > 3500 or abs(sy) > 3500:
        return None
    return city_from_sa(sx, sy)
