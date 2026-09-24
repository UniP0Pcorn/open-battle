"""Keep data import aligned with the executable weapon keyword subset."""
from __future__ import annotations

import re


ALIASES = {
    "喷射": "torrent",
    "torrent": "torrent",
    "忽略掩体": "ignores_cover",
    "ignores cover": "ignores_cover",
    "危险": "hazardous",
    "hazardous": "hazardous",
    "毁灭伤害": "devastating_wounds",
    "devastating wounds": "devastating_wounds",
    "致命一击": "lethal_hits",
    "lethal hits": "lethal_hits",
    "双联": "twin_linked",
    "twin-linked": "twin_linked",
    "twin linked": "twin_linked",
    "突击": "assault",
    "assault": "assault",
    "手枪": "pistol",
    "pistol": "pistol",
    "曲射": "indirect",
    "indirect": "indirect",
    "重型": "heavy",
    "heavy": "heavy",
    "爆炸": "blast",
    "blast": "blast",
}


def canonical_tag(value: object) -> str:
    text = str(value).strip().lower()
    if text in {"", "无", "-", "—", "none", "n/a"}:
        return ""
    compact = text.replace(" ", "").replace("　", "")
    rapid = re.fullmatch(r"速射(\d+)|连击(\d+)|rapidfire(\d+)", compact)
    if rapid:
        return "rapid_fire_" + next(group for group in rapid.groups() if group is not None)
    melta = re.fullmatch(r"热熔(\d+)|melta(\d+)", compact)
    if melta:
        return "melta_" + next(group for group in melta.groups() if group is not None)
    anti = re.fullmatch(r"(?:针对|anti[-_]?)([^+]+)([2-6])\+", compact)
    if anti:
        return "anti_" + anti.group(1) + "_" + anti.group(2)
    sustained = re.fullmatch(r"持续命中(\d+)|sustainedhits(\d+)", compact)
    if sustained:
        return "sustained_hits_" + next(group for group in sustained.groups() if group is not None)
    return ALIASES.get(text, text)


def is_supported(value: object) -> bool:
    tag = canonical_tag(value)
    return (
        tag == ""
        or
        tag in {"torrent", "ignores_cover", "assault", "pistol", "indirect", "hazardous", "devastating_wounds", "lethal_hits", "twin_linked", "heavy", "blast"}
        or re.fullmatch(r"rapid_fire_\d+", tag) is not None
        or re.fullmatch(r"melta_\d+", tag) is not None
        or re.fullmatch(r"anti_[^_]+_\d", tag) is not None
        or re.fullmatch(r"sustained_hits_\d+", tag) is not None
    )


def unsupported_tags(values: list[object]) -> list[str]:
    result: list[str] = []
    for value in values:
        if canonical_tag(value) and not is_supported(value) and str(value) not in result:
            result.append(str(value))
    return result
