"""Extract compact, reviewable datasheet candidates from user-provided PDFs.

This tool deliberately keeps only statlines, weapon rows, points snippets and
page/source metadata. It does not copy rules prose into the project.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pdfplumber


STAT_RE = re.compile(
    r"(?P<m>[0-9-]+[\"”]?)\s+(?P<t>[0-9-]+)\s+(?P<sv>[0-9-]+\+?)\s+"
    r"(?P<w>[0-9-]+)\s+(?P<ld>[0-9-]+\+?)\s+(?P<oc>[0-9-]+)", re.I
)
WEAPON_RE = re.compile(
    r"^(?P<name>.+?)\s+(?P<range>近战|[0-9]+[\"”]?)\s+"
    r"(?P<attacks>[0-9Dd+\-]+)\s+(?P<skill>[0-9NnAa]+\+?)\s+"
    r"(?P<strength>[0-9-]+)\s+(?P<ap>-?[0-9]+)\s+(?P<damage>[0-9Dd+\-]+)(?P<tail>\s+.*)?$"
)
TAG_RE = re.compile(r"\[([^\]]+)\]")
UNIT_KEYWORD_RE = re.compile(
    r"^(?:关键词|關鍵字)\s*[:：]?\s*(?P<unit>.*?)(?:\s+(?:阵营关键词|陣營關鍵字)\s*[:：]?\s*(?P<faction>.*))?$"
)
COMBINED_KEYWORD_RE = re.compile(
    r"^(?:关键词|關鍵字)\s*[:：]?\s*(?P<unit>.*?)\s+(?:阵营关键词|陣營關鍵字)\s*[:：]?\s*(?P<faction>.*)$"
)
FACTION_KEYWORD_RE = re.compile(r"^(?:阵营关键词|陣營關鍵字)\s*[:：]?\s*(?P<faction>.+)$")
POINT_RE = re.compile(r"(?P<count>[0-9]+)\s*个\s*模型.*?(?P<points>[0-9]+)\s*分")
POINT_SHORT_RE = re.compile(r"(?P<count>[0-9]+)\s*\+\s*个(?:\s*模型)?\s*(?P<points>[0-9]+)\s*分")
POINT_PAIR_RE = re.compile(r"(?P<base>[0-9]+)\s*分\s+(?P<count>[0-9]+)\s*\+\s*个(?:\s*模型)?\s*(?P<points>[0-9]+)\s*分")
POINT_COMPOSITION_RE = re.compile(r"(?:单位构成|单位组成).*?(?P<points>[0-9]+)\s*分")
POINT_SIMPLE_RE = re.compile(r"(?P<points>[0-9]+)\s*分\s*$")
BASE_MM_RE = re.compile(r"[⌀Ø]\s*(?P<base>[0-9]+(?:\.[0-9]+)?)\s*mm", re.I)


def _clean(line: str) -> str:
    return re.sub(r"\s+", " ", line.replace("\u3000", " ")).strip()


def _name(lines: list[str], stat_index: int) -> str:
    for line in reversed(lines[max(0, stat_index - 5) : stat_index]):
        line = _clean(line)
        if line and not re.fullmatch(r"[A-Z0-9 ()'’\-]+", line):
            return line
    for line in reversed(lines[max(0, stat_index - 5) : stat_index]):
        line = _clean(line)
        if line and not line.startswith("M T "):
            return line
    return "Unnamed datasheet"


def _weapon_tags(line: str, match: re.Match[str]) -> list[str]:
    tags = TAG_RE.findall(line)
    tail = (match.group("tail") or "").strip()
    if not tags and tail:
        tags = [part.strip() for part in re.split(r"[，,、;；]", tail.strip("[] ")) if part.strip()]
    return [tag for tag in tags if tag.strip() not in {"", "无", "-", "—", "none", "N/A"}]


def extract(pdf_path: Path, edition: str = "", max_pages: int = 0) -> dict:
    candidates: list[dict] = []
    with pdfplumber.open(pdf_path) as pdf:
        pages = pdf.pages[:max_pages] if max_pages else pdf.pages
        for page_number, page in enumerate(pages, 1):
            raw = page.extract_text() or ""
            lines = [_clean(x) for x in raw.splitlines() if _clean(x)]
            for i, line in enumerate(lines):
                if not line.startswith("M T "):
                    continue
                # PDF extraction commonly places the column header and values
                # on adjacent lines ("M T SV W LD OC" then "10” 4 ...").
                stat_line = line[4:]
                if i + 1 < len(lines):
                    stat_line = lines[i + 1]
                match = STAT_RE.search(stat_line)
                if not match:
                    continue
                stat = {k: v for k, v in match.groupdict().items()}
                weapons: list[dict] = []
                points: list[dict] = []
                unit_keywords: list[str] = []
                faction_keywords: list[str] = []
                for keyword_line in lines:
                    combined_match = COMBINED_KEYWORD_RE.match(keyword_line)
                    unit_match = combined_match or UNIT_KEYWORD_RE.match(keyword_line)
                    if unit_match:
                        unit_keywords = [x.strip() for x in re.split(r"[，,、]", unit_match.group("unit")) if x.strip()]
                        if unit_match.group("faction"):
                            faction_keywords = [x.strip() for x in re.split(r"[，,、]", unit_match.group("faction")) if x.strip()]
                    faction_match = FACTION_KEYWORD_RE.match(keyword_line)
                    if faction_match:
                        faction_keywords = [x.strip() for x in re.split(r"[，,、]", faction_match.group("faction")) if x.strip()]
                base_diameter_mm = ""
                for source_line in lines[: max(i + 1, 8)]:
                    base_match = BASE_MM_RE.search(source_line)
                    if base_match:
                        base_diameter_mm = float(base_match.group("base"))
                        break
                # A datasheet can place abilities and section headers between
                # the statline and its weapon table. Stop only at the next
                # statline, which is the reliable page-level record boundary.
                for candidate_line in lines[i + 2 :]:
                    if candidate_line.startswith("M T "):
                        break
                    weapon = WEAPON_RE.match(candidate_line)
                    if weapon:
                        item = {k: weapon.group(k) for k in ["name", "range", "attacks", "skill", "strength", "ap", "damage"]}
                        item["tags"] = _weapon_tags(candidate_line, weapon)
                        weapons.append(item)
                    for point in POINT_RE.finditer(candidate_line):
                        points.append({"models": int(point.group("count")), "points": int(point.group("points"))})
                # Points are often printed after the keyword/leader section.
                # Keep only compact model-count/cost pairs from this page.
                for candidate_line in lines:
                    for point in POINT_RE.finditer(candidate_line):
                        entry = {"models": int(point.group("count")), "points": int(point.group("points"))}
                        if entry not in points:
                            points.append(entry)
                    composition = POINT_COMPOSITION_RE.search(candidate_line)
                    if composition:
                        entry = {"models": 1, "points": int(composition.group("points"))}
                        if entry not in points:
                            points.append(entry)
                # Single-model profiles frequently print only "Name 415分".
                # Limit this fallback to the heading immediately before the
                # statline, avoiding arbitrary numbers in rules prose.
                has_composition_points = False
                for candidate_line in lines:
                    if POINT_COMPOSITION_RE.search(candidate_line):
                        has_composition_points = True
                        break
                # Header prices such as "265分 3+个 280分" are useful only
                # when the page has no explicit unit-composition price. Prefer
                # the composition table when both are present.
                if not has_composition_points:
                    for candidate_line in lines[max(0, i - 8) : i + 1]:
                        for pair in POINT_PAIR_RE.finditer(candidate_line):
                            base_entry = {"models": 1, "points": int(pair.group("base"))}
                            count_entry = {"models": int(pair.group("count")), "points": int(pair.group("points"))}
                            if base_entry not in points:
                                points.append(base_entry)
                            if count_entry not in points:
                                points.append(count_entry)
                        for short in POINT_SHORT_RE.finditer(candidate_line):
                            entry = {"models": int(short.group("count")), "points": int(short.group("points"))}
                            if entry not in points:
                                points.append(entry)
                        simple = POINT_SIMPLE_RE.search(candidate_line)
                        if simple and not POINT_RE.search(candidate_line) and not POINT_PAIR_RE.search(candidate_line) and not POINT_SHORT_RE.search(candidate_line):
                            entry = {"models": 1, "points": int(simple.group("points"))}
                            if entry not in points:
                                points.append(entry)
                candidates.append(
                    {
                        "source_file": pdf_path.name,
                        "source_page": page_number,
                        "edition": edition,
                        "name": _name(lines, i),
                        "statline": stat,
                        "weapons": weapons,
                        "points": points,
                        "keywords": unit_keywords,
                        "faction_keywords": faction_keywords,
                        "base_diameter_mm": base_diameter_mm,
                        "review_status": "candidate_needs_manual_review",
                    }
                )
                break
    return {"schema_version": 1, "source_file": pdf_path.name, "candidates": candidates}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--edition", default="")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-pages", type=int, default=0)
    args = parser.parse_args()
    result = extract(args.pdf, args.edition, args.max_pages)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"extracted {len(result['candidates'])} candidates -> {args.output}")


if __name__ == "__main__":
    main()
