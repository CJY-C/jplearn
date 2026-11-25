import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n2_emotions import SENSE_PAIRS, check_prior_changes, check_sources


class EmotionsVocabularyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.items = {w["id"]: w for w in cls.pack["items"]}

    def test_two_original_contexts_per_target_without_quota_inflation(self):
        proof = check_sources()
        self.assertEqual((proof["n2Roots"], proof["n3FoundationRoots"], proof["additionalSenses"]), (93, 3, 2))
        self.assertEqual((proof["targets"], proof["contexts"], proof["exercises"], proof["lessons"]), (98, 196, 98, 17))
        self.assertEqual((proof["heldoutLeaks"], proof["unresolvedContextForms"]), (0, 0))
        self.assertEqual(proof["independentLanguageReviews"], 0)
        self.assertFalse(proof["nativeIOSCompiled"])

    def test_only_six_declared_old_links_can_change(self):
        proof = check_prior_changes(self.pack)
        self.assertEqual(proof["oldSourcesChecked"], 93)
        self.assertEqual((proof["changedSentences"], proof["changedAssociations"]), (6, 6))
        for collection, field in [("items", "meaning"), ("sentences", "translation"),
                                  ("exercises", "prompt"), ("learningRules", "explanation"), ("references", "title")]:
            changed = copy.deepcopy(self.pack)
            changed[collection][0][field] = "Unreviewed historical change"
            with self.assertRaises(AssertionError): check_prior_changes(changed)
        changed = copy.deepcopy(self.pack)
        sentence = next(s for s in changed["sentences"] if s["id"] == "svn3j135b")
        next(s for s in sentence["segments"] if s["text"] == "柵")["itemID"] = "vn3t002"
        with self.assertRaises(AssertionError): check_prior_changes(changed)

    def test_negative_emphasis_and_sarcasm_event_pairs_share_only_reading(self):
        for rid, sid, identity, root_senses, extra_senses in SENSE_PAIRS:
            root, sense = self.items[rid], self.items[sid]
            self.assertEqual((sense["lexemeID"], sense["readingOwnerID"]), (rid, rid))
            self.assertNotEqual(root["meaning"], sense["meaning"])
            self.assertEqual((root["jmdictEntryID"], sense["jmdictEntryID"]), (identity, identity))
            questions = [q for q in self.pack["exercises"] if q["targetID"] in [rid, sid]]
            self.assertEqual(len(questions), 2)
            self.assertNotEqual(questions[0]["sentenceID"], questions[1]["sentenceID"])
            for q in questions: self.assertEqual(q["choices"][q["answerIndex"]], self.items[q["targetID"]]["meaning"])

    def test_readings_respect_actual_spelling_sense_and_current_usage(self):
        self.assertEqual(self.items["vn2g026"]["acceptedReadings"], ["めんどくさい"])
        self.assertEqual(self.items["vn2g039"]["acceptedReadings"], ["えばる"])
        for wid in ["vn2g027", "vn2g030", "vn2g036", "vn2g057", "vn2g078", "vn2g091", "vn2g095"]:
            self.assertFalse(self.items[wid].get("acceptedReadings"))
        self.assertEqual((self.items["vn2g057"]["reading"], self.items["vn2g057"]["jmdictEntryID"]), ("めした", 1535320))
        self.assertEqual((self.items["vn2g091"]["reading"], self.items["vn2g091"]["jmdictEntryID"]), ("しゃれ", 1568640))
        review = json.loads((ROOT / "content/staging/n2-emotions-and-relationships-review.json").read_text())
        restraint = next(s for s in review["senseChecks"] if s.get("itemID") == "vn2g036")
        self.assertEqual(restraint["accepted"], ["こらえる"])
        self.assertTrue(restraint["primaryCorroboration"]["url"].startswith("https://kotobank.jp/"))

    def test_acquaintance_verb_substrings_keep_their_existing_owner(self):
        self.assertEqual(self.items["vn4s003"]["text"], "知り合う")
        self.assertEqual(self.items["vn2g046"]["text"], "知り合い")
        for sid in ["svn4s003a", "sgn2a004c"]:
            sentence = next(s for s in self.pack["sentences"] if s["id"] == sid)
            self.assertIn("vn4s003", [s["itemID"] for s in sentence["segments"]])
            self.assertNotIn("vn2g046", [s["itemID"] for s in sentence["segments"]])


if __name__ == "__main__": unittest.main()
