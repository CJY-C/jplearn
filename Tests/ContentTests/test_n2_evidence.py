import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n2_evidence import check_sources, check_prior_changes


class EvidenceVocabularyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()

    def test_independent_sources_have_real_contexts_and_no_heldout_reuse(self):
        result = check_sources()
        self.assertEqual((result["wordRoots"], result["n2Roots"], result["earlierRoots"]), (101, 96, 5))
        self.assertEqual((result["contexts"], result["exercises"], result["lessons"]), (202, 101, 14))
        self.assertEqual((result["heldoutLeaks"], result["unresolvedContextForms"]), (0, 0))
        self.assertTrue(result["completeRebuiltPackValidated"])

    def test_only_reviewed_old_associations_can_change(self):
        proof = check_prior_changes(self.pack)
        self.assertEqual((proof["changedSentences"], proof["changedAssociations"], proof["oldSourcesChecked"]), (17, 17, 81))
        bad = copy.deepcopy(self.pack)
        bad["sentences"][0]["translation"] = "unreviewed"
        with self.assertRaises(AssertionError): check_prior_changes(bad)
        bad = copy.deepcopy(self.pack)
        bad["learningRules"][0]["explanation"] = "unreviewed"
        with self.assertRaises(AssertionError): check_prior_changes(bad)
        bad = copy.deepcopy(self.pack)
        next(w for w in bad["items"] if w["id"] == "vn3q002")["acceptedReadings"] = ["がくう"]
        with self.assertRaises(AssertionError): check_prior_changes(bad)

    def test_n3_prerequisites_and_existing_adverb_are_reused(self):
        items = {w["id"]: w for w in self.pack["items"]}
        for identifier in ["vn3q001", "vn3q002", "vn3q003", "vn3q004", "vn3q005"]:
            self.assertEqual(items[identifier]["level"], "N3")
        sentence = next(s for s in self.pack["sentences"] if s["id"] == "svn3g009b")
        self.assertIn("vn3c076", {s["itemID"] for s in sentence["segments"]})
        self.assertNotIn("vn2d073", {s["itemID"] for s in sentence["segments"]})

    def test_readings_follow_the_selected_sense(self):
        items = {w["id"]: w for w in self.pack["items"]}
        self.assertEqual(items["vn3q002"].get("acceptedReadings", []), [])
        self.assertEqual(items["vn3q002"]["reading"], "かくう")
        self.assertNotIn("ゆうむ", items["vn3q003"].get("acceptedReadings", []))
        self.assertNotIn("しろと", items["vn2d066"].get("acceptedReadings", []))
        self.assertEqual(items["vn2d020"].get("acceptedReadings"), ["てっかく"])
