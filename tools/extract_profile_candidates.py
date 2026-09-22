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
    r"^(?P<name>.+?)\s+(?P<range>近战|[0-9]+[\"”])\s+"
    r"(?P<attacks>[0-9Dd+\-]+)\s+(?P<skill>[0-9NnAa]+\+?)\s+"
    r"(?P<strength>[0-9-]+)\s+(?P<ap>-?[0-9]+)\s+(?P<damage>[0-9Dd+\-]+)(?:\s+.*)?$"
)
TAG_RE = re.compile(r"\[([^\]]+)\]")
KEYWORD_RE = re.compile(r"关键词：(?P<unit>.*?)(?:阵营关键词：(?P<faction>.*))?$")
POINT_RE = re.compile(r"(?P<count>[0-9]+)个模型.*?(?P<points>[0-9]+)分")


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
                    keyword_match = KEYWORD_RE.search(keyword_line)
                    if keyword_match:
                        unit_keywords = [x.strip() for x in re.split(r"[，,、]", keyword_match.group("unit")) if x.strip()]
                        faction_text = keyword_match.group("faction") or ""
                        faction_keywords = [x.strip() for x in re.split(r"[，,、]", faction_text) if x.strip()]
                        break
                for candidate_line in lines[i + 2 : i + 24]:
                    weapon = WEAPON_RE.match(candidate_line)
                    if weapon and weapon.group("range") != "近战":
                        item = {k: v for k, v in weapon.groupdict().items()}
                        item["tags"] = TAG_RE.findall(candidate_line)
                        weapons.append(item)
                    for point in POINT_RE.finditer(candidate_line):
                        points.append({"models": int(point.group("count")), "points": int(point.group("points"))})
                    if candidate_line.startswith("关键词：") or candidate_line.startswith("Keywords:"):
                        break
                # Points are often printed after the keyword/leader section.
                # Keep only compact model-count/cost pairs from this page.
                for candidate_line in lines:
                    for point in POINT_RE.finditer(candidate_line):
                        entry = {"models": int(point.group("count")), "points": int(point.group("points"))}
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
