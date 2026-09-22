"""Index candidates that are structurally ready for explicit human promotion."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def fixed(value: object, signed: bool = False) -> bool:
    pattern = r"-?\d+" if signed else r"\d+"
    return re.fullmatch(pattern, str(value).replace("+", "").replace("”", "").replace('"', "").strip()) is not None


def reason(candidate: dict) -> list[str]:
    problems: list[str] = []
    stat = candidate.get("statline", {})
    for field in ["m", "t", "sv", "w", "ld", "oc"]:
        if not fixed(stat.get(field, "")):
            problems.append("non_numeric_" + field)
    if not candidate.get("points"):
        problems.append("missing_points")
    if not candidate.get("weapons"):
        problems.append("missing_weapons")
    for weapon in candidate.get("weapons", []):
        for field in ["range", "attacks", "skill", "strength", "damage"]:
            if not fixed(weapon.get(field, "")):
                problems.append("complex_weapon_" + field)
        if not fixed(weapon.get("ap", ""), True):
            problems.append("complex_weapon_ap")
    return sorted(set(problems))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate_dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    promotable: list[dict] = []
    rejected: dict[str, int] = {}
    for path in sorted(args.candidate_dir.glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        for candidate in document.get("candidates", []):
            problems = reason(candidate)
            if problems:
                for problem in problems:
                    rejected[problem] = rejected.get(problem, 0) + 1
                continue
            promotable.append({
                "name": candidate.get("name"),
                "source_file": candidate.get("source_file"),
                "source_page": candidate.get("source_page"),
                "edition": candidate.get("edition"),
                "points": candidate.get("points"),
                "weapon_count": len(candidate.get("weapons", [])),
                "promotion_status": "needs_explicit_base_and_faction",
            })
    result = {"schema_version": 1, "promotable_count": len(promotable), "promotable": promotable, "rejected_reasons": rejected}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"promotable={len(promotable)} rejected={sum(rejected.values())}")


if __name__ == "__main__":
    main()
