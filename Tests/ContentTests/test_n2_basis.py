import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n2_basis import check_prior_changes, check_sources


class BasisChapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()

    def test_sources_exercise_all_functions_and_keep_assessments_separate(self):
        proof = check_sources()
        self.assertEqual((proof["grammarFunctions"], proof["grammarContexts"]), (10, 60))
        self.assertEqual((proof["ordinaryReadings"], proof["assessments"], proof["readingQuestions"]), (6, 2, 16))
        self.assertEqual((proof["n5FoundationRoots"], proof["n2Roots"]), (1, 0))
        self.assertEqual(proof["wordContextGaps"], [])
        self.assertTrue(all(length >= 350 for length in proof["japaneseCharacterCounts"]))
        self.assertEqual(proof["independentLanguageReviews"], 0)

    def test_full_reconstruction_preserves_history_except_one_reviewed_link(self):
        proof = check_prior_changes(self.pack)
        self.assertEqual(proof["oldSourcesChecked"], 83)
        self.assertEqual((proof["changedSentences"], proof["changedAssociations"]), (1, 1))
        sentence = next(s for s in self.pack["sentences"] if s["id"] == "svn5956a")
        self.assertEqual("".join(s["text"] for s in sentence["segments"]), "駅員に乗り場を聞きました。")
        self.assertEqual([s["itemID"] for s in sentence["segments"] if s["text"] == "乗り場"], ["vn5b001"])

    def test_unreviewed_old_data_or_new_answers_cannot_pass_compatibility(self):
        for key, field in [("items", "meaning"), ("learningRules", "explanation"), ("references", "title")]:
            broken = copy.deepcopy(self.pack)
            broken[key][0][field] = "unreviewed change"
            with self.assertRaises(AssertionError):
                check_prior_changes(broken)
        broken = copy.deepcopy(self.pack)
        question = next(r for r in broken["readings"] if r["id"] == "rn2107")["questions"][0]
        question["answerIndex"] = (question["answerIndex"] + 1) % 3
        with self.assertRaises(AssertionError):
            check_prior_changes(broken)

    def test_near_synonyms_and_productive_forms_do_not_inflate_coverage(self):
        ledger = json.loads((ROOT / "content/source-checks/n2-basis-chapter.json").read_text())
        items = {w["id"]: w for w in self.pack["items"]}
        self.assertEqual([i for i in ledger["newIDs"]["items"] if items[i]["kind"] == "word"], ["vn5b001"])
        self.assertEqual(items["vn5b001"]["level"], "N5")
        syllabus = json.loads((ROOT / "content/syllabus.json").read_text())
        self.assertNotIn("N2:ni-soui-nai", syllabus["grammarCoverage"])
        self.assertNotIn("N2:ni-motozuite", syllabus["grammarCoverage"])
        self.assertEqual(syllabus["grammarCoverage"]["N2:kara-suru-to-kara-sureba"]["itemIDs"], ["gn2b004", "gn2b005"])
        self.assertEqual(next(r for r in syllabus["levels"] if r["level"] == "N2")["words"], 2500)
        self.assertTrue(all(not bridge["readingIDs"] for bridge in syllabus["readingBridges"]))


if __name__ == "__main__":
    unittest.main()
