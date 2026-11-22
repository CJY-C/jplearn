import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n2_conditions import check_prior_changes, check_sources


class ConditionsChapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.items = {w["id"]: w for w in cls.pack["items"]}

    def test_original_functions_have_real_practice_and_isolated_assessments(self):
        proof = check_sources()
        self.assertEqual((proof["n3FoundationRoots"], proof["n2Roots"], proof["additionalSenses"]), (7, 8, 1))
        self.assertEqual((proof["grammarFunctions"], proof["grammarContexts"], proof["referencePatterns"]), (13, 78, 12))
        self.assertEqual((proof["ordinaryReadings"], proof["assessments"], proof["readingQuestions"]), (8, 2, 20))
        self.assertEqual(proof["heldoutLeaks"], 0)
        self.assertTrue(all(n >= 350 for n in proof["japaneseCharacterCounts"]))
        self.assertEqual(proof["independentLanguageReviews"], 0)
        self.assertFalse(proof["nativeIOSCompiled"])

    def test_exact_history_proof_rejects_text_answers_and_wrong_sense_links(self):
        proof = check_prior_changes(self.pack)
        self.assertEqual(proof["oldSourcesChecked"], 89)
        self.assertEqual((proof["changedAssociations"], proof["preservedPhysicalAssociations"]), (5, 2))
        for collection, field in [("items", "meaning"), ("sentences", "translation"),
                                  ("exercises", "prompt"), ("learningRules", "explanation"), ("references", "title")]:
            changed = copy.deepcopy(self.pack)
            changed[collection][0][field] = "Unreviewed prior change"
            with self.assertRaises(AssertionError): check_prior_changes(changed)
        changed = copy.deepcopy(self.pack)
        sentence = next(s for s in changed["sentences"] if s["id"] == "svn5766a")
        next(s for s in sentence["segments"] if s["itemID"] == "vn5766")["itemID"] = "vn3s004"
        with self.assertRaises(AssertionError): check_prior_changes(changed)

    def test_transfer_forms_share_a_function_but_distinct_functions_do_not_merge(self):
        self.assertNotEqual(self.items["gn2c009"]["meaning"], self.items["gn2c010"]["meaning"])
        self.assertNotEqual(self.items["gn2c006"]["meaning"], self.items["gn2c008"]["meaning"])
        self.assertNotEqual(self.items["gn527"]["meaning"], self.items["gn2c013"]["meaning"])
        self.assertIn("gn434", self.items["gn2c010"]["prerequisiteIDs"])
        syllabus = json.loads((ROOT / "content/syllabus.json").read_text())
        self.assertEqual(syllabus["grammarCoverage"]["N2:mono-nara"]["itemIDs"], ["gn2c009", "gn2c010"])
        self.assertEqual(syllabus["grammarCoverage"]["N2:kagiri"]["itemIDs"], ["gn2c006", "gn2c008"])
        self.assertEqual(syllabus["grammarCoverage"]["N2:kara-ni-wa"]["itemIDs"], ["gn2c001"])
        self.assertEqual(syllabus["grammarCoverage"]["N2:ijou-wa"]["itemIDs"], ["gn2c001"])

    def test_meaning_transfer_does_not_duplicate_reading_or_count_earlier_words_as_n2(self):
        sense, root = [self.items[i] for i in ["vn3s004", "vn5766"]]
        self.assertEqual(sense["lexemeID"], root["id"])
        self.assertEqual(sense["readingOwnerID"], root["id"])
        self.assertNotEqual(sense["meaning"], root["meaning"])
        self.assertEqual(self.items["vn3s008"]["level"], "N3")
        self.assertEqual(self.items["vn2f002"]["jmdictEntryID"], 2825953)
        for sid in ["svn5766a", "svn5766b"]:
            sentence = next(s for s in self.pack["sentences"] if s["id"] == sid)
            self.assertIn("vn5766", [s["itemID"] for s in sentence["segments"]])
            self.assertNotIn("vn3s004", [s["itemID"] for s in sentence["segments"]])

    def test_observed_advanced_forms_remain_explicit_prerequisites(self):
        readings = {r["id"]: r for r in self.pack["readings"]}
        for rid, required in {"rn2201": {"gn2a006"}, "rn2203": {"gn2a006"},
                              "rn2204": {"gn310"}, "rn2206": {"gn2a006", "gn481"},
                              "rn2208": {"gn323", "gn2a006"}}.items():
            self.assertTrue(required <= set(readings[rid]["grammarIDs"]))


if __name__ == "__main__": unittest.main()
