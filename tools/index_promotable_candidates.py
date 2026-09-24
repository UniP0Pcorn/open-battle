"""Index candidates that are structurally ready for explicit human promotion."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

try:
    from tools.weapon_tag_support import unsupported_tags
except ModuleNotFoundError:
    from weapon_tag_support import unsupported_tags


def fixed(value: object, signed: bool = False) -> bool:
    pattern = r"-?\d+" if signed else r"\d+"
    return re.fullmatch(pattern, str(value).replace("+", "").replace("”", "").replace('"', "").strip()) is not None


def fixed_or_dice(value: object, signed: bool = False) -> bool:
    text = str(value).replace("”", "").replace('"', "").strip()
    if fixed(text, signed):
        return True
    return re.fullmatch(r"(?:\d+)?D(?:3|6)(?:[+-]\d+)?", text, re.I) is not None


def weapon_range_fixed(value: object) -> bool:
    return str(value).strip().lower() in {"近战", "melee"} or fixed(value)


def reason(candidate: dict) -> list[str]:
    problems: list[str] = []
    stat = candidate.get("statline", {})
    for field in ["m", "t", "sv", "w", "ld", "oc"]:
        if not fixed(stat.get(field, "")):
            problems.append("non_numeric_" + field)
    if not candidate.get("faction_keywords"):
        problems.append("missing_faction_keywords")
    if not candidate.get("points"):
        problems.append("missing_points")
    if not candidate.get("weapons"):
        problems.append("missing_weapons")
    for weapon in candidate.get("weapons", []):
        for field in ["range", "attacks", "skill", "strength", "damage"]:
            if field == "range":
                valid = weapon_range_fixed(weapon.get(field, ""))
            elif field in {"attacks", "damage"}:
                valid = fixed_or_dice(weapon.get(field, ""))
            else:
                valid = fixed(weapon.get(field, ""))
            if not valid:
                problems.append("complex_weapon_" + field)
        if not fixed(weapon.get("ap", ""), True):
            problems.append("complex_weapon_ap")
        if unsupported_tags(weapon.get("tags", [])):
            problems.append("unsupported_weapon_keywords")
    return sorted(set(problems))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate_dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    promotable: list[dict] = []
    rejected: dict[str, int] = {}
    candidate_total = 0
    candidate_payload_total = 0
    for path in sorted(args.candidate_dir.glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        candidate_total += int(document.get("candidate_count", 0) or 0)
        candidate_payload_total += len(document.get("candidates", []))
        if int(document.get("candidate_count", 0) or 0) > 0 and not document.get("candidates"):
            rejected["candidate_payload_missing"] = rejected.get("candidate_payload_missing", 0) + int(document.get("candidate_count", 0))
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
    result = {"schema_version": 1, "candidate_count": candidate_total, "candidate_payload_count": candidate_payload_total, "promotable_count": len(promotable), "promotable": promotable, "rejected_reasons": rejected}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"promotable={len(promotable)} rejected={sum(rejected.values())}")


if __name__ == "__main__":
    main()
