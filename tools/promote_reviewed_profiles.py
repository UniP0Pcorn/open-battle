"""Promote approved rows from the profile review CSV.

Only rows with decision=approved are touched. The tool delegates all numeric
strictness to promote_profile_draft.promote and reports row-level failures so a
single unresolved datasheet cannot silently enter the ready catalogue.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from promote_profile_draft import promote


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("review_csv", type=Path)
    parser.add_argument("--draft-dir", type=Path, default=Path("work/profile_drafts"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/units/imported"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    promoted = 0
    failures: list[str] = []
    with args.review_csv.open(newline="", encoding="utf-8-sig") as handle:
        for row_number, row in enumerate(csv.DictReader(handle), start=2):
            if str(row.get("decision", "")).strip().lower() != "approved":
                continue
            draft_path = args.draft_dir / str(row.get("draft_file", ""))
            try:
                if not draft_path.is_file():
                    raise ValueError(f"missing draft: {draft_path}")
                base_mm = float(str(row.get("base_mm", "")).strip())
                if base_mm <= 0:
                    raise ValueError("base_mm must be positive")
                coherency = float(str(row.get("coherency_inches", "2.0")).strip())
                faction = str(row.get("faction", "")).strip()
                if not faction:
                    raise ValueError("faction is required")
                draft = json.loads(draft_path.read_text(encoding="utf-8"))
                result = promote(draft, faction, base_mm, coherency)
                output_path = args.output_dir / f"{result['id']}.json"
                output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
                promoted += 1
            except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
                failures.append(f"row {row_number}: {exc}")
    print(f"promoted {promoted} approved profiles")
    if failures:
        print("failures:")
        print("\n".join(failures))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
