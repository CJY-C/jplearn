import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from audit_curriculum import audit
from build_content import make_pack
from compile_grammar import compile_manuscript


class CurriculumDeliveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.syllabus = json.loads((ROOT / "content/syllabus.json").read_text())
        cls.reference = json.loads((ROOT / "content/reference/openjlpt-grammar.json").read_text())

    def test_full_goal_is_not_shrunk_to_the_delivered_batch(self):
        requirements = self.syllabus["levels"]
        self.assertEqual([r["level"] for r in requirements], ["N5", "N4", "N3", "N2"])
        self.assertEqual(sum(r["words"] for r in requirements), 6000)
        self.assertEqual(sum(r["knowledgePoints"] for r in requirements), 400)
        self.assertEqual(sum(r["readings"] for r in requirements), 440)
        self.assertEqual(sum(r["lessons"] for r in requirements), 260)
        self.assertEqual(len(self.syllabus["readingBridges"]), 6)

    def test_n5_reference_patterns_have_actual_teaching_and_contexts(self):
        result = audit(self.pack, self.syllabus, self.reference)
        n5 = result["stages"][0]
        self.assertEqual(n5["grammarPatterns"]["covered"], 81)
        self.assertEqual(n5["grammarPatterns"]["missing"], [])
        self.assertFalse(result["errors"])
        self.assertFalse(result["wordContextGaps"])

    def test_manuscript_compiles_to_the_committed_batch(self):
        compiled, _ = compile_manuscript(ROOT / "content/authoring/n5-structures.tsv", self.pack)
        expected = json.loads((ROOT / "content/batches/002-n5-structures.json").read_text())
        self.assertEqual(compiled, expected)
        self.assertEqual(len(compiled["items"]), 42)
        self.assertEqual(len(compiled["exercises"]), 252)

    def test_lesson_recommendation_order_preserves_beginner_progression(self):
        order = {level: index for index, level in enumerate(["N5", "N4", "N3", "N2"])}
        levels = [order[l["level"]] for l in self.pack["lessons"]]
        self.assertEqual(levels, sorted(levels))

    def test_relabeling_a_later_stage_does_not_prove_beginner_coverage(self):
        syllabus = copy.deepcopy(self.syllabus)
        syllabus["grammarCoverage"]["N5:ga-subject"]["itemIDs"] = ["g017"]
        result = audit(self.pack, syllabus, self.reference)
        self.assertIn("N5:ga-subject", result["stages"][0]["grammarPatterns"]["missing"])
        self.assertTrue(any("taught after" in e for e in result["errors"]))

    def test_duplicate_sentence_ids_are_not_distinct_contexts(self):
        pack = copy.deepcopy(self.pack)
        first = next(e for e in pack["exercises"] if e["targetID"] == "gn501")["sentenceID"]
        for exercise in pack["exercises"]:
            if exercise["targetID"] == "gn501": exercise["sentenceID"] = first
        result = audit(pack, self.syllabus, self.reference)
        self.assertIn("N5:ga-subject", result["stages"][0]["grammarPatterns"]["missing"])
        self.assertTrue(any("distinct contexts" in e for e in result["errors"]))

    def test_a_missing_mapping_stays_missing_even_with_enough_items(self):
        syllabus = copy.deepcopy(self.syllabus)
        del syllabus["grammarCoverage"]["N5:ga-subject"]
        result = audit(self.pack, syllabus, self.reference)
        self.assertGreaterEqual(result["stages"][0]["actual"]["knowledgePoints"], 60)
        self.assertIn("N5:ga-subject", result["stages"][0]["grammarPatterns"]["missing"])
        self.assertFalse(result["stages"][0]["complete"])
