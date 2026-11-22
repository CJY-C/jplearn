import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n2_social import check_prior_changes, check_sources


class SocialVocabularyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.items = {w["id"]: w for w in cls.pack["items"]}

    def test_sources_have_two_original_contexts_and_preserve_stage_quotas(self):
        proof = check_sources()
        self.assertEqual((proof["n2Roots"], proof["n3Roots"], proof["n4Roots"]), (111, 12, 1))
        self.assertEqual((proof["targets"], proof["contexts"], proof["lessons"]), (125, 250, 18))
        self.assertEqual((proof["heldoutLeaks"], proof["unresolvedContextForms"]), (0, 0))
        self.assertEqual(proof["independentLanguageReviews"], 0)
        self.assertFalse(proof["nativeIOSCompiled"])

    def test_only_seven_reviewed_earlier_links_change(self):
        proof = check_prior_changes(self.pack)
        self.assertEqual(proof["oldSourcesChecked"], 86)
        self.assertEqual((proof["changedSentences"], proof["changedAssociations"]), (7, 7))
        for key, field in [("items", "meaning"), ("learningRules", "explanation"), ("references", "title")]:
            broken = copy.deepcopy(self.pack)
            broken[key][0][field] = "unreviewed change"
            with self.assertRaises(AssertionError): check_prior_changes(broken)
        broken = copy.deepcopy(self.pack)
        sentence = next(s for s in broken["sentences"] if s["id"] == "svn3j173b")
        next(s for s in sentence["segments"] if s["text"] == "保護")["itemID"] = "vn3r003"
        with self.assertRaises(AssertionError): check_prior_changes(broken)

    def test_collecting_and_donating_share_only_reading_not_meaning(self):
        collecting, donating = [self.items[i] for i in ["vn2e106", "vn2e112"]]
        self.assertEqual((collecting["text"], collecting["reading"]), (donating["text"], donating["reading"]))
        self.assertNotEqual(collecting["meaning"], donating["meaning"])
        self.assertEqual(donating["lexemeID"], collecting["id"])
        self.assertEqual(donating["readingOwnerID"], collecting["id"])
        questions = {q["targetID"]: q for q in self.pack["exercises"] if q["targetID"] in {collecting["id"], donating["id"]}}
        self.assertEqual(len(questions), 2)
        self.assertNotEqual(questions[collecting["id"]]["sentenceID"], questions[donating["id"]]["sentenceID"])
        for word in [collecting, donating]:
            q = questions[word["id"]]
            self.assertEqual(q["choices"][q["answerIndex"]], word["meaning"])

    def test_alternative_readings_keep_their_actual_dictionary_senses(self):
        main = json.loads((ROOT / "content/staging/n2-social-and-work-words-review.json").read_text())
        facts = {x["itemID"]: x for x in main["entries"]}
        household = facts["vn2e012"]
        alternate = next(r for r in household["acceptedReadingSources"] if r["acceptedReading"] == "しょたい")
        self.assertEqual((household["entryID"], alternate["entryID"]), (1374170, 2869002))
        self.assertIn("世帯", alternate["dictionarySpellings"])
        self.assertEqual(facts["vn2e027"]["senseOrdinals"], [1])
        self.assertEqual(facts["vn2e027"]["acceptedAlternativeReadings"], ["せこう"])
        self.assertEqual(facts["vn2e078"]["senseOrdinals"], [1])
        self.assertIn("ちんきん", facts["vn2e078"]["acceptedAlternativeReadings"])
        earlier = json.loads((ROOT / "content/staging/n3-social-foundation-words-review.json").read_text())
        scholarship = next(e for e in earlier["entries"] if e["itemID"] == "vn3r009")
        self.assertEqual(scholarship["senseOrdinals"], [1, 2])
        self.assertEqual(scholarship["acceptedAlternativeReadings"], ["しょうがっきん"])


if __name__ == "__main__": unittest.main()
