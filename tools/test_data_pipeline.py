"""Regression tests for the review-sheet data boundary."""
from __future__ import annotations

import json
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path

from tools.export_profile_review_sheet import review_flags, rows, source_lookup
from tools.extract_profile_candidates import BASE_MM_RE, COMBINED_KEYWORD_RE, FACTION_KEYWORD_RE, POINT_COMPOSITION_RE, POINT_PAIR_RE, POINT_RE, POINT_SHORT_RE, UNIT_KEYWORD_RE, WEAPON_RE, _weapon_tags
from tools.index_promotable_candidates import reason, weapon_range_fixed, main as index_main
from tools.promote_profile_draft import inches, promote
from tools.promote_reviewed_profiles import approved_profile
from tools.weapon_tag_support import unsupported_tags


class ReviewSheetTests(unittest.TestCase):
    def review_fixture(self) -> dict:
        return {
            "id": "draft_fixture", "display_name": "Original test fixture", "edition": 11,
            "keywords": ["INFANTRY"], "faction_keywords": ["FIXTURE"],
            "models": [{"name": "Fixture", "movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"name": "Fixture weapon", "range": "24", "attacks": "2", "skill": "3+", "strength": "5", "damage": "2", "ap": "-1", "tags": []}],
            "points": [{"models": 5, "points": 100}],
        }

    def test_approval_is_bound_to_exact_reviewed_draft(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "fixture.json"
            path.write_text(json.dumps(self.review_fixture()), encoding="utf-8")
            row = next(rows(root))
            self.assertEqual(row["reviewed_by"], "")
            with self.assertRaisesRegex(ValueError, "explicit approval"):
                approved_profile(row, root)
            row.update(decision="approved", faction="fixture", base_mm="40")
            with self.assertRaisesRegex(ValueError, "reviewed_by"):
                approved_profile(row, root)
            row.update(reviewed_by="test-reviewer", reviewed_at="2026-09-25")
            result = approved_profile(row, root)
            self.assertEqual(result["review"]["draft_sha256"], row["draft_sha256"])
            self.assertEqual(result["import_status"], "ready")
            changed = self.review_fixture()
            changed["points"][0]["points"] = 101
            path.write_text(json.dumps(changed), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "draft changed"):
                approved_profile(row, root)

    def test_promotion_retains_four_priority_review_blockers(self) -> None:
        for field, expected in [("points", "missing_points"), ("weapons", "missing_weapons"), ("faction_keywords", "missing_faction_keywords")]:
            with self.subTest(field=field):
                draft = self.review_fixture()
                draft[field] = []
                with self.assertRaisesRegex(ValueError, expected):
                    promote(draft, "fixture", 40, 2)
        draft = self.review_fixture()
        draft["weapons"][0]["tags"] = ["unknown_fixture_rule"]
        with self.assertRaisesRegex(ValueError, "unsupported_weapon_keywords"):
            promote(draft, "fixture", 40, 2)

    def test_promotion_rejects_nonfinite_physical_values(self) -> None:
        for base, coherency in [(float("nan"), 2), (float("inf"), 2), (-1, 2), (40, float("nan")), (40, -1)]:
            with self.subTest(base=base, coherency=coherency):
                with self.assertRaises(ValueError):
                    promote(self.review_fixture(), "fixture", base, coherency)

    def test_approval_rejects_invalid_identity_date_and_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fixture.json").write_text(json.dumps(self.review_fixture()), encoding="utf-8")
            row = next(rows(root))
            row.update(decision="approved", faction="fixture", base_mm="40", reviewed_by="reviewer", reviewed_at="2026-09-25")
            for field, value in [("id", "other"), ("reviewed_at", "not-a-date"), ("draft_file", "../fixture.json"), ("draft_file", "sub/fixture.json"), ("draft_sha256", "")]:
                with self.subTest(field=field):
                    invalid = dict(row)
                    invalid[field] = value
                    with self.assertRaises(ValueError):
                        approved_profile(invalid, root)

    def test_candidate_summary_without_payload_is_never_promotable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "summary.json").write_text(json.dumps({"candidate_count": 3, "import_status": "pending_extraction"}), encoding="utf-8")
            output = root / "index.json"
            result = subprocess.run([sys.executable, "-m", "tools.index_promotable_candidates", directory, "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            document = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(document["candidate_count"], 3)
            self.assertEqual(document["candidate_payload_count"], 0)
            self.assertEqual(document["promotable_count"], 0)
            self.assertEqual(document["rejected_reasons"]["candidate_payload_missing"], 3)
            self.assertIn("promotable=0", result.stdout)

    def test_empty_review_export_reports_actionable_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "review.csv"
            result = subprocess.run([sys.executable, "-m", "tools.export_profile_review_sheet", "--draft-dir", directory, "--output", str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("build review drafts first", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertFalse(output.exists())

    def test_signed_ap_is_preserved_and_positive_ap_requires_review(self) -> None:
        draft = self.review_fixture()
        result = promote(draft, "fixture", 40, 2)
        self.assertEqual(result["weapons"][0]["ap"], -1)
        draft["weapons"][0]["ap"] = "1"
        self.assertIn("invalid_weapon_ap", review_flags(draft))
        with self.assertRaisesRegex(ValueError, "invalid_weapon_ap"):
            promote(draft, "fixture", 40, 2)
        draft["weapons"][0]["ap"] = "0"
        self.assertEqual(promote(draft, "fixture", 40, 2)["weapons"][0]["ap"], 0)

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
            "keywords": ["步兵"],
            "faction_keywords": ["沃坦联盟"],
            "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"range": "24", "attacks": "2", "skill": "3", "strength": "5", "damage": "2", "ap": "-1"}],
            "points": [{"models": 5, "points": 100}],
        }
        self.assertEqual(review_flags(draft), [])

    def test_melee_weapon_rows_are_valid(self) -> None:
        match = WEAPON_RE.match("链锯剑 近战 4 3+ 4 0 1")
        self.assertIsNotNone(match)
        draft = {
            "keywords": ["步兵"],
            "faction_keywords": ["沃坦联盟"],
            "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"range": "近战", "attacks": "4", "skill": "3+", "strength": "4", "damage": "1", "ap": "0"}],
            "points": [{"models": 1, "points": 100}],
        }
        self.assertEqual(review_flags(draft), [])
        self.assertEqual(inches("近战", "weapon range"), 0.0)
        self.assertTrue(weapon_range_fixed("近战"))

    def test_unimplemented_weapon_keywords_stay_in_review(self) -> None:
        self.assertEqual(unsupported_tags(["突击", "手枪", "曲射", "一次性", "一次性武器", "精准"]), [])
        self.assertEqual(unsupported_tags(["反步兵4+", "反载具3+", "反飞行2+", "反巨兽4+"]), [])
        self.assertEqual(unsupported_tags(["速射D3", "连击D6+3"]), [])
        self.assertEqual(unsupported_tags(["熱熔2", "連擊1", "雙聯", "無", "無視掩體"]), [])
        self.assertEqual(unsupported_tags(["曲射，双联", "爆炸、危险"]), [])
        self.assertEqual(unsupported_tags(["爆炸，灵能"]), ["爆炸，灵能"])
        draft = {
            "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"range": "24", "attacks": "2", "skill": "3", "strength": "5", "damage": "2", "ap": "-1", "tags": ["灵能"]}],
            "points": [{"models": 5, "points": 100}],
        }
        self.assertIn("unsupported_weapon_keywords", review_flags(draft))

    def test_supported_dice_expressions_do_not_create_complex_flags(self) -> None:
        draft = {
            "keywords": ["步兵"],
            "faction_keywords": ["沃坦联盟"],
            "models": [{"movement": "6", "toughness": "4", "save": "4+", "wounds": "2", "leadership": "7", "objective_control": "1"}],
            "weapons": [{"range": "24", "attacks": "D3", "skill": "3+", "strength": "5", "damage": "D6+1", "ap": "-1"}],
            "points": [{"models": 5, "points": 100}],
        }
        self.assertNotIn("complex_weapon_attacks", review_flags(draft))
        self.assertNotIn("complex_weapon_damage", review_flags(draft))
        self.assertNotIn("complex_weapon_attacks", reason({"statline": {"m": "6", "t": "4", "sv": "4+", "w": "2", "ld": "7+", "oc": "1"}, "weapons": draft["weapons"], "points": draft["points"]}))

    def test_extractor_accepts_bare_range_and_spaced_points(self) -> None:
        match = WEAPON_RE.match("脉冲激光炮 36 2D6 2+ 7 -1 2 爆炸，连击1")
        self.assertIsNotNone(match)
        assert match is not None
        self.assertEqual(match.group("range"), "36")
        self.assertEqual(_weapon_tags(match.group(0), match), ["爆炸", "连击1"])
        self.assertEqual(POINT_RE.search("单位构成 1 个模型，415 分").group("points"), "415")
        noisy = WEAPON_RE.match("循环离子炮 18 3 4+ 7 -1 1 阵营：为了上上善道")
        self.assertIsNotNone(noisy)
        assert noisy is not None
        self.assertEqual(_weapon_tags(noisy.group(0), noisy), [])
        unit = UNIT_KEYWORD_RE.match("关键词 步兵、人物")
        faction = FACTION_KEYWORD_RE.match("阵营关键词 沃坦联盟")
        combined = COMBINED_KEYWORD_RE.match("关键词：载具，飞行器 阵营关键词：钛帝国")
        combined_explicit = COMBINED_KEYWORD_RE.match("关键词： 阵营关键词：钛帝国")
        traditional = UNIT_KEYWORD_RE.match("關鍵字 載具、煙幕")
        traditional_faction = FACTION_KEYWORD_RE.match("陣營關鍵字 帝國特勤")
        self.assertIsNotNone(unit)
        self.assertIsNotNone(faction)
        self.assertIsNotNone(combined)
        self.assertIsNotNone(combined_explicit)
        self.assertIsNotNone(traditional)
        self.assertIsNotNone(traditional_faction)
        assert unit is not None and faction is not None and combined is not None and combined_explicit is not None and traditional is not None and traditional_faction is not None
        self.assertEqual(unit.group("unit"), "步兵、人物")
        self.assertEqual(faction.group("faction"), "沃坦联盟")
        self.assertEqual(combined.group("unit"), "载具，飞行器")
        self.assertEqual(combined.group("faction"), "钛帝国")
        self.assertEqual(combined_explicit.group("unit"), "")
        self.assertEqual(combined_explicit.group("faction"), "钛帝国")
        self.assertEqual(traditional.group("unit"), "載具、煙幕")
        self.assertEqual(traditional_faction.group("faction"), "帝國特勤")

    def test_extractor_accepts_compact_multi_model_points(self) -> None:
        pair = POINT_PAIR_RE.search("战马骑士 265分 3+个 280分")
        self.assertIsNotNone(pair)
        assert pair is not None
        self.assertEqual((pair.group("base"), pair.group("count"), pair.group("points")), ("265", "3", "280"))
        short = POINT_SHORT_RE.search("3+个模型 280分")
        self.assertIsNotNone(short)
        assert short is not None
        self.assertEqual((short.group("count"), short.group("points")), ("3", "280"))
        composition = POINT_COMPOSITION_RE.search("单位构成 一台战马骑士，250分")
        self.assertIsNotNone(composition)
        assert composition is not None
        self.assertEqual(composition.group("points"), "250")
        base = BASE_MM_RE.search("ARKANYST EVALUATOR [⌀32mm]")
        self.assertIsNotNone(base)
        assert base is not None
        self.assertEqual(base.group("base"), "32")


if __name__ == "__main__":
    unittest.main()
