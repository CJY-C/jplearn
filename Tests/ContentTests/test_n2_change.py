import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n2_change import check_prior_changes, check_sources


class ChangeChapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.items = {w["id"]: w for w in cls.pack["items"]}

    def test_real_roots_and_earlier_backfills_are_not_counted_as_n2_quota(self):
        proof = check_sources()
        self.assertEqual((proof["wordRoots"], proof["wordTargets"]), (30, 31))
        self.assertEqual((proof["n4FoundationRoots"], proof["n3FoundationRoots"], proof["n2Roots"]), (1, 18, 11))
        self.assertEqual((proof["grammarFunctions"], proof["grammarContexts"], proof["referencePatterns"]), (12, 72, 11))
        self.assertEqual((proof["readings"], proof["assessments"]), (10, 2))
        self.assertTrue(all(r["japaneseCharacters"] >= 350 and r["unlinkedOccurrences"] == 0 for r in proof["passageChecks"]))
        self.assertEqual(proof["independentLanguageReviews"], 0)
        self.assertFalse(proof["nativeIOSCompiled"])

    def test_exact_history_and_new_answers_reject_unreviewed_changes(self):
        self.assertEqual(check_prior_changes(self.pack)["changedAssociations"], 22)
        for sid in ["svn4854a", "rn2305sd", "rn2309se"]:
            changed = copy.deepcopy(self.pack)
            next(s for s in changed["sentences"] if s["id"] == sid)["translation"] = "Unreviewed change"
            with self.subTest(sentence=sid), self.assertRaises(AssertionError):
                check_prior_changes(changed)
        changed = copy.deepcopy(self.pack)
        passage = next(r for r in changed["readings"] if r["id"] == "rn2310")
        passage["questions"][0]["answerIndex"] = (passage["questions"][0]["answerIndex"] + 1) % 3
        with self.assertRaises(AssertionError):
            check_prior_changes(changed)

    def test_abstract_holding_cannot_reuse_body_meaning_or_broader_reading(self):
        physical, abstract = self.items["vn4854"], self.items["vn3u015"]
        self.assertEqual(abstract["lexemeID"], physical["id"])
        self.assertIsNone(abstract.get("readingOwnerID"))
        self.assertEqual(abstract["reading"], "いだく")
        self.assertFalse(abstract.get("acceptedReadings"))
        self.assertIn("いだく", physical["acceptedReadings"])
        sentence = next(s for s in self.pack["sentences"] if s["id"] == "rn2305sd")
        self.assertEqual(next(s["itemID"] for s in sentence["segments"] if s["text"] == "抱"), abstract["id"])

    def test_heldout_passages_are_absent_from_ordinary_lesson_links(self):
        heldout = {"rn2309", "rn2310"}
        self.assertEqual({r["id"] for r in self.pack["readings"] if r["id"] in heldout and r["purpose"] == "assessment"}, heldout)
        self.assertFalse(heldout & {r.get("readingID") for r in self.pack["lessons"]})
        review = json.loads((ROOT / "content/staging/n2-change-review.json").read_text())
        market = next(w for w in review["wordEntries"] if w["itemID"] == "vn3u011")
        self.assertEqual((market["entryID"], market["primaryReading"]), (1308300, "いちば"))
        self.assertFalse(market["acceptedAlternativeReadings"])


if __name__ == "__main__":
    unittest.main()
