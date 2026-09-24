"""Promote a reviewed draft to the engine profile schema.

The command is intentionally strict: unsupported expressions or missing physical
measurements fail instead of silently inventing values.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

try:
    from tools.weapon_tag_support import unsupported_tags
except ModuleNotFoundError:  # Direct ``python tools/script.py`` invocation.
    from weapon_tag_support import unsupported_tags


def number(value: object, label: str) -> int:
    text = str(value).replace("”", "").replace('"', "").strip()
    if not re.fullmatch(r"\d+", text):
        raise ValueError(f"{label} is not a fixed numeric value: {value}")
    return int(text)


def signed_number(value: object, label: str) -> int:
    text = str(value).strip()
    if not re.fullmatch(r"-?\d+", text):
        raise ValueError(f"{label} is not a fixed numeric value: {value}")
    return int(text)


def number_or_expression(value: object, label: str) -> object:
    text = str(value).replace("”", "").replace('"', "").strip().upper()
    if re.fullmatch(r"\d+", text):
        return int(text)
    if re.fullmatch(r"(?:\d+)?D\d+(?:[+-]\d+)?", text):
        return text
    raise ValueError(f"{label} is not a supported dice expression: {value}")


def inches(value: object, label: str) -> float:
    text = str(value).replace("”", "").replace('"', "").strip()
    try:
        return float(text)
    except ValueError as exc:
        raise ValueError(f"{label} is not a distance: {value}") from exc


def promote(draft: dict, faction: str, base_mm: float, coherency: float) -> dict:
    model = draft["models"][0]
    result = {
        "id": draft["id"].replace("draft_", ""),
        "display_name": draft["display_name"],
        "edition": int(draft["edition"]),
        "faction": faction,
        "import_status": "ready",
        "abilities": list(draft.get("abilities", [])),
        "keywords": list(draft.get("keywords", [])),
        "faction_keywords": list(draft.get("faction_keywords", [])),
        "models": [{
            "name": model["name"],
            "movement_inches": inches(model["movement"], "movement"),
            "toughness": number(model["toughness"], "toughness"),
            "wounds": number(model["wounds"], "wounds"),
            "base_diameter_mm": base_mm,
            "coherency_inches": coherency,
            "save_on": number(str(model["save"]).replace("+", ""), "save"),
            "leadership": number(model["leadership"].replace("+", ""), "leadership"),
            "objective_control": number(model["objective_control"], "objective_control"),
        }],
        "weapons": [],
        "points": [{"models": int(option["models"]), "cost": int(option["points"])} for option in draft.get("points", [])],
        "provenance": draft.get("provenance", {}),
        "review_notes": draft.get("review_notes", []),
    }
    for weapon in draft.get("weapons", []):
        result["weapons"].append({
            "name": weapon["name"],
            "range_inches": inches(weapon["range"], "weapon range"),
            "attacks": number_or_expression(weapon["attacks"], "attacks"),
            "hit_on": number(weapon["skill"].replace("+", ""), "hit skill"),
            "strength": number(weapon["strength"], "strength"),
            "ap": signed_number(weapon["ap"], "AP"),
            "damage": number_or_expression(weapon["damage"], "damage"),
            "abilities": weapon.get("tags", []),
        })
    if not result["points"] or not result["weapons"]:
        raise ValueError("draft has no usable points or weapon rows")
    unsupported: list[str] = []
    for weapon in draft.get("weapons", []):
        for tag in unsupported_tags(weapon.get("tags", [])):
            if tag not in unsupported:
                unsupported.append(tag)
    if unsupported:
        raise ValueError("unsupported weapon keywords: " + ", ".join(unsupported))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("draft", type=Path)
    parser.add_argument("--faction", required=True)
    parser.add_argument("--base-mm", type=float, required=True)
    parser.add_argument("--coherency", type=float, default=2.0)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    draft = json.loads(args.draft.read_text(encoding="utf-8"))
    result = promote(draft, args.faction, args.base_mm, args.coherency)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"promoted {result['display_name']} -> {args.output}")


if __name__ == "__main__":
    main()
