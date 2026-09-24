"""Regression tests for the review-sheet data boundary."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.export_profile_review_sheet import review_flags, rows, source_lookup
from tools.weapon_tag_support import unsupported_tags


class ReviewSheetTests(unittest.TestCase):
    def test_manifest_defaults_do_not_approve_profiles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"sources": [{"id": "tau_11_cn", "filename": "tau.pdf"}]}), encoding="utf-8")
            drafts = root / "drafts"
            drafts.mkdir()
            (drafts / "unit.json").write_text(json.dumps({
                "id": "draft_unit",
                "display_name": "Unit",
                "edition": 11,
                "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2"}],
                "weapons": [],
                "points": [],
                "provenance": {"source_file": "tau.pdf", "source_page": 1},
            }), encoding="utf-8")
            source_map = source_lookup(manifest)
            row = next(rows(drafts, source_map))
            self.assertEqual(row["source_id"], "tau_11_cn")
            self.assertEqual(row["faction"], "tau_11_cn")
            self.assertEqual(row["review_bucket"], "needs_field_review")
            self.assertIn("missing_points", row["review_flags"])
            self.assertIn("missing_weapons", row["review_flags"])
            self.assertEqual(row["decision"], "pending_manual_review")

    def test_complete_candidate_only_needs_explicit_base_and_faction(self) -> None:
        draft = {
            "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"range": "24", "attacks": "2", "skill": "3", "strength": "5", "damage": "2", "ap": "-1"}],
            "points": [{"models": 5, "points": 100}],
        }
        self.assertEqual(review_flags(draft), [])

    def test_unimplemented_weapon_keywords_stay_in_review(self) -> None:
        self.assertEqual(unsupported_tags(["突击", "手枪"]), ["手枪"])
        draft = {
            "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"range": "24", "attacks": "2", "skill": "3", "strength": "5", "damage": "2", "ap": "-1", "tags": ["手枪"]}],
            "points": [{"models": 5, "points": 100}],
        }
        self.assertIn("unsupported_weapon_keywords", review_flags(draft))


if __name__ == "__main__":
    unittest.main()
