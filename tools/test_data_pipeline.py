"""Regression tests for the review-sheet data boundary."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.export_profile_review_sheet import rows, source_lookup


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
            self.assertEqual(row["decision"], "pending_manual_review")


if __name__ == "__main__":
    unittest.main()
