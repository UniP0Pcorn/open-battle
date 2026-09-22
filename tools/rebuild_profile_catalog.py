"""Rebuild the repository's human-readable unit profile index."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("data/units"))
    parser.add_argument("--output", type=Path, default=Path("data/units/catalog.json"))
    args = parser.parse_args()
    profiles: list[dict] = []
    for path in sorted(args.root.rglob("*.json")):
        if path.resolve() == args.output.resolve() or path.name == "catalog.json":
            continue
        try:
            profile = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not isinstance(profile, dict) or not profile.get("id") or "edition" not in profile or "models" not in profile:
            continue
        relative = path.resolve().relative_to(Path.cwd().resolve()).as_posix()
        profiles.append({
            "id": profile["id"],
            "path": "res://" + relative,
            "edition": int(profile.get("edition", 0)),
            "faction": profile.get("faction", ""),
            "status": profile.get("import_status", "ready"),
        })
    result = {"schema_version": 1, "profiles": profiles}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"indexed {len(profiles)} profiles -> {args.output}")


if __name__ == "__main__":
    main()
