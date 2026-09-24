"""Promote approved rows from the profile review CSV.

Only rows with decision=approved are touched. The tool delegates all numeric
strictness to promote_profile_draft.promote and reports row-level failures so a
single unresolved datasheet cannot silently enter the ready catalogue.
"""
from __future__ import annotations

import argparse
import csv
import json
import hashlib
import re
from datetime import date
from pathlib import Path

try:
    from tools.promote_profile_draft import promote
except ModuleNotFoundError:
    from promote_profile_draft import promote


def approved_profile(row: dict, draft_dir: Path) -> dict:
    """Bind explicit human approval to the exact reviewed draft bytes."""
    if str(row.get("decision", "")).strip().lower() != "approved":
        raise ValueError("explicit approval required")
    reviewer = str(row.get("reviewed_by", "")).strip()
    if not reviewer:
        raise ValueError("reviewed_by is required")
    reviewed_at = str(row.get("reviewed_at", "")).strip()
    try:
        date.fromisoformat(reviewed_at)
    except ValueError as exc:
        raise ValueError("reviewed_at must be an ISO date") from exc
    filename = str(row.get("draft_file", ""))
    if not filename or Path(filename).name != filename or "/" in filename or "\\" in filename:
        raise ValueError("draft_file must name one file in draft-dir")
    draft_path = (draft_dir / filename).resolve()
    if draft_path.parent != draft_dir.resolve():
        raise ValueError("draft is outside draft-dir")
    raw = draft_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if str(row.get("draft_sha256", "")).strip().lower() != digest:
        raise ValueError("draft changed or review hash missing; review again")
    draft = json.loads(raw.decode("utf-8"))
    if str(row.get("id", "")) != str(draft.get("id", "")):
        raise ValueError("review row does not match draft id")
    result = promote(draft, str(row.get("faction", "")).strip(), float(row.get("base_mm", "")), float(row.get("coherency_inches", "2.0")))
    if not re.fullmatch(r"[A-Za-z0-9_-]+", str(result["id"])):
        raise ValueError("profile id is not a safe file name")
    result["review"] = {"reviewed_by": reviewer, "reviewed_at": reviewed_at, "draft_sha256": digest}
    return result


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
            try:
                result = approved_profile(row, args.draft_dir)
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
