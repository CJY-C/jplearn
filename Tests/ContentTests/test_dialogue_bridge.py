import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from audit_curriculum import audit
from build_content import make_pack
from check_dialogue_bridge import check_sources, check_prior_changes, IDS


class DialogueBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.readings = {r["id"]: r for r in cls.pack["readings"]}

    def test_three_distinct_dialogues_complete_only_the_first_bridge(self):
        result = check_sources()
        self.assertEqual((result["readings"], result["practiceReadings"], result["assessments"], result["questions"]), (3, 2, 1, 9))
        self.assertEqual((result["newRoots"], result["newGrammarCards"]), (0, 0))
        self.assertTrue(all(p["japaneseCharacters"] >= 350 and p["unlinkedOccurrences"] == 0 for p in result["passageChecks"]))
        syllabus = json.loads((ROOT / "content/syllabus.json").read_text())
        reference = json.loads((ROOT / "content/reference/openjlpt-grammar.json").read_text())
        actual = audit(self.pack, syllabus, reference)
        self.assertFalse(actual["complete"])
        self.assertFalse(actual["errors"])
        self.assertEqual([(b["actual"], b["required"]) for b in actual["readingBridges"]], [(3, 3)] + [(0, 3)] * 5)
        self.assertEqual(actual["stages"][-1]["required"]["words"], 2500)
        self.assertEqual(result["independentLanguageReviews"], 0)

    def test_old_content_and_new_question_answers_cannot_change_silently(self):
        self.assertTrue(check_prior_changes(self.pack)["allOldCollectionsPreserved"])
        old_sid = self.readings["r009"]["sentenceIDs"][0]
        for sid in ["rnbd001sc", "rnbd003se", "rn2305sd", old_sid]:
            changed = copy.deepcopy(self.pack)
            sentence = next((s for s in changed["sentences"] if s["id"] == sid), None)
            self.assertIsNotNone(sentence, sid)
            sentence["translation"] = "Unreviewed alteration"
            with self.subTest(sentence=sid), self.assertRaises(AssertionError):
                check_prior_changes(changed)
        changed = copy.deepcopy(self.pack)
        question = next(r for r in changed["readings"] if r["id"] == "rnbd003")["questions"][0]
        question["answerIndex"] = (question["answerIndex"] + 1) % 3
        with self.assertRaises(AssertionError):
            check_prior_changes(changed)

    def test_transfer_assessment_is_not_exposed_as_an_example_or_lesson(self):
        assessment = self.readings["rnbd003"]
        self.assertEqual(assessment["purpose"], "assessment")
        heldout = set(assessment["sentenceIDs"])
        self.assertTrue(all(r["purpose"] == "practice" for r in [self.readings[i] for i in IDS[:2]]))
        self.assertTrue(all(not heldout.intersection(w.get("exampleSentenceIDs", [])) for w in self.pack["items"]))
        self.assertTrue(all(e["sentenceID"] not in heldout for e in self.pack["exercises"]))
        self.assertTrue(all(l.get("readingID") not in IDS for l in self.pack["lessons"]))

    def test_word_senses_match_the_dialogue_action(self):
        sentences = {s["id"]: s for s in self.pack["sentences"]}
        self.assertIn("vn6157", [s.get("itemID") for s in sentences["rnbd001sc"]["segments"]])
        self.assertNotIn("vn3g010", [s.get("itemID") for s in sentences["rnbd001sc"]["segments"]])
        self.assertIn("vn4i171", [s.get("itemID") for s in sentences["rnbd002sc"]["segments"]])
        self.assertNotIn("vn2b020", [s.get("itemID") for s in sentences["rnbd002sc"]["segments"]])
        self.assertTrue(all(v["itemID"] for rid in IDS for v in self.readings[rid]["vocabulary"]))
