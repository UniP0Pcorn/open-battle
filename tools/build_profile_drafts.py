"""Turn compact extraction candidates into reviewable, non-playable profiles."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def safe_id(value: str, fallback: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9]+", "_", value.lower()).strip("_")
    return value or fallback


def draft(candidate: dict) -> dict:
    stat = candidate.get("statline", {})
    source = candidate.get("source_file", "")
    page = int(candidate.get("source_page", 0))
    base = safe_id(str(candidate.get("name", "unit")), f"unit_page_{page}")
    return {
        "id": f"draft_{base}_p{page}",
        "display_name": candidate.get("name", "Unnamed datasheet"),
        "edition": candidate.get("edition", ""),
        "faction": "pending_import",
        "import_status": "pending_manual_review",
        "keywords": candidate.get("keywords", []),
        "faction_keywords": candidate.get("faction_keywords", []),
        "abilities": candidate.get("abilities", []),
        "models": [{
            "name": candidate.get("name", "Unnamed datasheet"),
            "movement": stat.get("m", ""),
            "toughness": stat.get("t", ""),
            "save": stat.get("sv", ""),
            "wounds": stat.get("w", ""),
            "leadership": stat.get("ld", ""),
            "objective_control": stat.get("oc", ""),
            "raw_statline": stat,
        }],
        "weapons": candidate.get("weapons", []),
        "points": candidate.get("points", []),
        "provenance": {"source_file": source, "source_page": page},
        "review_notes": ["Confirm translation, weapon line grouping, base size, abilities and options before promotion."],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate_dir", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    written = 0
    seen: set[str] = set()
    for path in sorted(args.candidate_dir.glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        for item in document.get("candidates", []):
            result = draft(item)
            stem = result["id"]
            if stem in seen:
                stem += f"_{path.stem}"
            seen.add(stem)
            (args.output_dir / f"{stem}.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            written += 1
    print(f"wrote {written} review drafts to {args.output_dir}")


if __name__ == "__main__":
    main()
