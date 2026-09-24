"""Export pending profile drafts to a compact manual-review CSV.

The sheet intentionally contains structured fields and provenance only. It does
not copy source prose, so reviewers can fill physical base data and approve a
candidate without turning the repository into a text dump of the source PDFs.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path


def source_lookup(manifest_path: Path) -> dict[str, dict]:
    if not manifest_path.is_file():
        return {}
    document = json.loads(manifest_path.read_text(encoding="utf-8"))
    return {str(entry.get("filename", "")): entry for entry in document.get("sources", [])}


def _fixed(value: object, signed: bool = False) -> bool:
    pattern = r"-?\d+" if signed else r"\d+"
    return re.fullmatch(pattern, str(value).replace("+", "").replace("”", "").replace('"', "").strip()) is not None


def review_flags(draft: dict) -> list[str]:
    """Return structural flags without deciding whether a profile is approved."""
    flags: list[str] = []
    model = (draft.get("models") or [{}])[0]
    for field in ["movement", "toughness", "save", "wounds", "leadership", "objective_control"]:
        if not _fixed(model.get(field, "")):
            flags.append("non_numeric_" + field)
    if not draft.get("points"):
        flags.append("missing_points")
    if not draft.get("weapons"):
        flags.append("missing_weapons")
    for weapon in draft.get("weapons", []):
        for field in ["range", "attacks", "skill", "strength", "damage"]:
            if not _fixed(weapon.get(field, "")):
                flags.append("complex_weapon_" + field)
        if not _fixed(weapon.get("ap", ""), signed=True):
            flags.append("complex_weapon_ap")
    return sorted(set(flags))


def rows(root: Path, sources: dict[str, dict] | None = None):
    sources = sources or {}
    for path in sorted(root.glob("*.json")):
        draft = json.loads(path.read_text(encoding="utf-8"))
        model = (draft.get("models") or [{}])[0]
        source_file = draft.get("provenance", {}).get("source_file", "")
        source = sources.get(source_file, {})
        source_id = str(source.get("id", ""))
        flags = review_flags(draft)
        yield {
            "draft_file": path.name,
            "id": draft.get("id", ""),
            "display_name": draft.get("display_name", ""),
            "edition": draft.get("edition", ""),
            "source_id": source_id,
            "faction": source_id,
            "faction_keywords": "|".join(draft.get("faction_keywords", [])),
            "source_file": source_file,
            "source_page": draft.get("provenance", {}).get("source_page", ""),
            "model_count": len(draft.get("models", [])),
            "weapon_count": len(draft.get("weapons", [])),
            "points": "|".join(f"{p.get('models')}:{p.get('points')}" for p in draft.get("points", [])),
            "movement": model.get("movement", ""),
            "toughness": model.get("toughness", ""),
            "save": model.get("save", ""),
            "wounds": model.get("wounds", ""),
            "base_mm": "",
            "coherency_inches": "2.0",
            "review_bucket": "needs_field_review" if flags else "ready_for_base_faction_review",
            "review_flags": "|".join(flags),
            "decision": "pending_manual_review",
        }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--draft-dir", type=Path, default=Path("work/profile_drafts"))
    parser.add_argument("--output", type=Path, default=Path("work/profile_review.csv"))
    parser.add_argument("--manifest", type=Path, default=Path("data/sources/manifest.json"))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    source_map = source_lookup(args.manifest)
    fields = list(next(rows(args.draft_dir, source_map)).keys())
    with args.output.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows(args.draft_dir, source_map))
    print(f"exported review sheet: {args.output}")


if __name__ == "__main__":
    main()
