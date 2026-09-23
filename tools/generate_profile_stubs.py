"""Create metadata-only unit profile stubs from the source manifest.

The generated files intentionally contain no invented rules values. They are
review queues for an authorized, structured import from each local source.
"""
from __future__ import annotations

import json
import argparse
import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "sources" / "manifest.json"
OUTPUT = ROOT / "data" / "units" / "pending"


def review_counts(path: Path) -> dict[str, int]:
    if not path.is_file():
        return {}
    counts: dict[str, int] = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            source_id = str(row.get("source_id", "")).strip()
            if source_id:
                counts[source_id] = counts.get(source_id, 0) + 1
    return counts


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--review-csv", type=Path, default=Path("work/profile_review.csv"))
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    counts = review_counts(args.review_csv)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for source in manifest["sources"]:
        profile = {
            "id": source["id"],
            "display_name": source["display_name"],
            "edition": source["edition"],
            "faction": source["id"],
            "source": {
                "filename": source["filename"],
                "category": source["category"],
                "pages": source["pages"],
                "status": source["status"],
            },
            "models": [],
            "weapons": [],
            "points": [],
            "import_status": "pending_extraction",
            "candidate_count": counts.get(source["id"], 0),
            "review_sheet": str(args.review_csv).replace("\\", "/"),
        }
        (OUTPUT / f"{source['id']}.json").write_text(
            json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(f"generated {len(manifest['sources'])} profile stubs in {OUTPUT}")


if __name__ == "__main__":
    main()
