"""Export pending profile drafts to a compact manual-review CSV.

The sheet intentionally contains structured fields and provenance only. It does
not copy source prose, so reviewers can fill physical base data and approve a
candidate without turning the repository into a text dump of the source PDFs.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def rows(root: Path):
    for path in sorted(root.glob("*.json")):
        draft = json.loads(path.read_text(encoding="utf-8"))
        model = (draft.get("models") or [{}])[0]
        yield {
            "draft_file": path.name,
            "id": draft.get("id", ""),
            "display_name": draft.get("display_name", ""),
            "edition": draft.get("edition", ""),
            "faction": "",
            "faction_keywords": "|".join(draft.get("faction_keywords", [])),
            "source_file": draft.get("provenance", {}).get("source_file", ""),
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
            "decision": "pending_manual_review",
        }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--draft-dir", type=Path, default=Path("work/profile_drafts"))
    parser.add_argument("--output", type=Path, default=Path("work/profile_review.csv"))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fields = list(next(rows(args.draft_dir)).keys())
    with args.output.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows(args.draft_dir))
    print(f"exported review sheet: {args.output}")


if __name__ == "__main__":
    main()
