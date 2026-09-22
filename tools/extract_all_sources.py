"""Batch-extract compact profile candidates for every local source manifest entry."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from extract_profile_candidates import extract


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=Path("data/sources/manifest.json"))
    parser.add_argument("--output-dir", type=Path, default=Path("work/source_candidates"))
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    done = 0
    skipped = 0
    for entry in manifest.get("sources", []):
        source = args.source_root / str(entry["filename"])
        if not source.exists():
            skipped += 1
            continue
        result = extract(source, str(entry.get("edition", "")))
        output = args.output_dir / f"{entry['id']}.json"
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{entry['id']}: {len(result['candidates'])} candidates")
        done += 1
    print(f"processed={done} skipped={skipped}")


if __name__ == "__main__":
    main()
