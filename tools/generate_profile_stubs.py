"""Create metadata-only unit profile stubs from the source manifest.

The generated files intentionally contain no invented rules values. They are
review queues for an authorized, structured import from each local source.
"""
from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "sources" / "manifest.json"
OUTPUT = ROOT / "data" / "units" / "pending"


def main() -> None:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
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
        }
        (OUTPUT / f"{source['id']}.json").write_text(
            json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    print(f"generated {len(manifest['sources'])} profile stubs in {OUTPUT}")


if __name__ == "__main__":
    main()
