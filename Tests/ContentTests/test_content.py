import importlib.util
from collections import Counter
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ContentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = json.loads((ROOT / "Sources/LearningCore/Resources/foundation.json").read_text())
        cls.groups = {key: {item["id"]: item for item in cls.pack[key]}
                      for key in ["items", "sentences", "exercises", "lessons", "readings", "references"]}

    def test_sample_delivery_counts(self):
        self.assertGreaterEqual(len(self.groups["lessons"]), 30)
        self.assertGreaterEqual(len(self.groups["readings"]), 40)
        self.assertGreaterEqual(len(self.groups["exercises"]), 571)
        self.assertGreaterEqual(sum(i["kind"] == "word" for i in self.groups["items"].values()), 300)
        self.assertGreaterEqual(sum(i["kind"] == "grammar" for i in self.groups["items"].values()), 72)

    def test_identifiers_are_unique_and_stable(self):
        for key, values in self.groups.items():
            self.assertEqual(len(values), len(self.pack[key]), key)
            self.assertTrue(all(re.fullmatch(r"[a-z0-9]+", identifier) for identifier in values))
        words = [item for item in self.pack["items"] if item["kind"] == "word"]
        self.assertEqual(words[0]["id"], "v0001")
        self.assertEqual(words[0]["text"], "今日")
        self.assertEqual(words[149]["id"], "v0150")
        self.assertEqual(words[149]["text"], "結局")
        self.assertEqual(words[181]["id"], "v0182")

    def test_every_word_has_reading_gloss_and_romanization(self):
        for item in self.groups["items"].values():
            self.assertTrue(item["meaning"] and item["explanation"], item["id"])
            if item["kind"] == "word":
                self.assertRegex(item["reading"], r"^[ぁ-ゖー]+$")
                self.assertTrue(item["romaji"], item["id"])

    def test_references_and_trial_labels(self):
        for item in self.groups["items"].values():
            self.assertEqual(item["status"], "trial")
            self.assertTrue(item["sourceIDs"])
            self.assertTrue(set(item["sourceIDs"]) <= self.groups["references"].keys())
        for reference in self.groups["references"].values():
            self.assertTrue(reference["url"].startswith("https://"))

    def test_all_kanji_in_sample_sentences_have_ruby(self):
        for sentence in self.groups["sentences"].values():
            self.assertTrue(sentence["translation"], sentence["id"])
            for segment in sentence["segments"]:
                self.assertTrue(segment["text"])
                if re.search(r"[一-龯]", segment["text"]):
                    self.assertTrue(segment["reading"], (sentence["id"], segment))
                if segment["itemID"]:
                    self.assertIn(segment["itemID"], self.groups["items"])

    def test_exercises_have_valid_unique_choices(self):
        for exercise in self.groups["exercises"].values():
            self.assertIn(exercise["targetID"], self.groups["items"])
            self.assertIn(exercise["sentenceID"], self.groups["sentences"])
            self.assertGreaterEqual(len(exercise["choices"]), 2)
            self.assertEqual(len(exercise["choices"]), len(set(exercise["choices"])))
            self.assertIn(exercise["answerIndex"], range(len(exercise["choices"])))
            self.assertTrue(exercise["explanation"] and exercise["hint"])

    def test_inflected_verb_stems_link_to_dictionary_form(self):
        exercise = self.groups["exercises"]["e003a"]
        sentence = self.groups["sentences"][exercise["sentenceID"]]
        stem = next(segment for segment in sentence["segments"] if segment["text"] == "読")
        self.assertEqual(self.groups["items"][stem["itemID"]]["text"], "読む")
        expected = {"新": "新しい", "大": "大きい", "考": "考える"}
        for sentence in self.groups["sentences"].values():
            for segment in sentence["segments"]:
                if segment["text"] in expected:
                    self.assertEqual(self.groups["items"][segment["itemID"]]["text"], expected[segment["text"]])

    def test_each_grammar_has_a_different_transfer_sentence(self):
        for item in self.groups["items"].values():
            if item["kind"] != "grammar":
                continue
            related = [e for e in self.groups["exercises"].values() if e["targetID"] == item["id"]]
            self.assertEqual({e["transfer"] for e in related}, {False, True})
            self.assertGreaterEqual(len({e["sentenceID"] for e in related}), 6)

    def test_lesson_references_and_complete_item_coverage(self):
        covered = set()
        for lesson in self.groups["lessons"].values():
            self.assertTrue(lesson["itemIDs"] and lesson["exerciseIDs"] and lesson["sentenceIDs"])
            for key, group in [("itemIDs", "items"), ("exerciseIDs", "exercises"), ("sentenceIDs", "sentences")]:
                self.assertTrue(set(lesson[key]) <= self.groups[group].keys(), lesson["id"])
            if lesson["readingID"]:
                self.assertIn(lesson["readingID"], self.groups["readings"])
            covered.update(lesson["itemIDs"])
        self.assertEqual(covered, self.groups["items"].keys())

    def test_passage_questions_are_answerable_and_linked(self):
        for reading in self.groups["readings"].values():
            self.assertGreaterEqual(len(reading["sentenceIDs"]), 3)
            self.assertTrue(set(reading["sentenceIDs"]) <= self.groups["sentences"].keys())
            self.assertIn(reading["answerIndex"], range(len(reading["choices"])))
            self.assertTrue(reading["explanation"])

    def test_roadmap_counts_are_distinct_from_shipped_content(self):
        self.assertEqual(sum(stage["vocabularyTarget"] for stage in self.pack["stages"]), 6000)
        self.assertEqual(sum(stage["grammarTarget"] for stage in self.pack["stages"]), 400)
        self.assertEqual(sum(stage["readingTarget"] for stage in self.pack["stages"]), 440)
        self.assertIn("分批补充", self.pack["notice"])

    def test_reading_coverage_has_explicit_occurrences_and_prerequisites(self):
        for reading in self.groups["readings"].values():
            words = reading["vocabulary"]
            self.assertTrue(words, reading["id"])
            self.assertTrue(reading["grammarIDs"], reading["id"])
            for word in words:
                self.assertTrue(word["text"])
                self.assertIsNotNone(word["itemID"], (reading["id"], word))
                self.assertEqual(self.groups["items"][word["itemID"]]["text"], word["text"])
            for identifier in reading["grammarIDs"]:
                self.assertEqual(self.groups["items"][identifier]["kind"], "grammar")
            linked = Counter(segment["itemID"] for sid in reading["sentenceIDs"]
                             for segment in self.groups["sentences"][sid]["segments"] if segment["itemID"])
            listed = Counter(word["itemID"] for word in words)
            self.assertFalse(linked - listed, (reading["id"], linked - listed))
        first = self.groups["readings"]["r001"]["vocabulary"]
        self.assertEqual(sum(word["text"] == "私" for word in first), 2)

    def test_every_word_has_two_distinct_context_examples(self):
        for word in self.pack["items"]:
            if word["kind"] != "word": continue
            self.assertGreaterEqual(len(set(word.get("exampleSentenceIDs", []))), 2, word["id"])
            self.assertTrue(set(word["exampleSentenceIDs"]) <= self.groups["sentences"].keys())
            texts = {"".join(segment["text"] for segment in self.groups["sentences"][sid]["segments"])
                     for sid in word["exampleSentenceIDs"]}
            self.assertGreaterEqual(len(texts), 2, word["id"])

    def test_assessments_have_evidence_and_are_not_reused_as_lesson_reading(self):
        assessments = [r for r in self.pack["readings"] if r.get("purpose") == "assessment"]
        self.assertGreaterEqual(len(assessments), 8)
        lesson_readings = {l["readingID"] for l in self.pack["lessons"]}
        self.assertFalse(lesson_readings & {r["id"] for r in assessments})
        for reading in self.pack["readings"]:
            for q in reading.get("questions", []):
                self.assertTrue(q["evidenceSentenceIDs"])
                self.assertTrue(set(q["evidenceSentenceIDs"]) <= set(reading["sentenceIDs"]))

    def test_source_licenses_and_intro_modules_are_explicit(self):
        self.assertEqual(len(self.pack["introModules"]), 6)
        for module in self.pack["introModules"]:
            self.assertEqual(len(module["questions"]), 5)
            self.assertTrue(module["citations"])
        for source in ["taekim", "project", "pdx"]:
            self.assertTrue(self.groups["references"][source]["license"])
            self.assertTrue(self.groups["references"][source]["attribution"])

    def test_generated_resource_matches_authoring_source(self):
        spec = importlib.util.spec_from_file_location("authoring", ROOT / "scripts/build_content.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.make_pack(), self.pack)


if __name__ == "__main__":
    unittest.main()
