import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from audit_curriculum import audit
from build_content import make_pack
from compile_grammar import compile_manuscript
from compile_readings import compile_manuscript as compile_readings, markup_sentence
from compile_words import compile_manuscript as compile_words
import compile_course


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

    def test_reading_and_word_manuscripts_match_committed_batches(self):
        for compiler, source, batch in [
            (compile_readings, "n5-readings.tsv", "003-n5-readings.json"),
            (compile_words, "n5-reading-words.tsv", "004-n5-reading-vocabulary.json"),
            (compile_words, "n5-core-words.tsv", "005-n5-core-vocabulary.json"),
            (compile_words, "n5-everyday-words.tsv", "006-n5-everyday-vocabulary.json"),
            (compile_words, "n5-numbers-and-reading-words.tsv", "007-n5-numbers-and-reading-vocabulary.json"),
            (compile_words, "n5-expanded-context-words.tsv", "008-n5-expanded-context-vocabulary.json"),
            (compile_words, "n5-scene-words.tsv", "009-n5-scene-vocabulary.json"),
            (compile_words, "n5-foundation-actions.tsv", "010-n5-foundation-actions.json")]:
            self.assertEqual(compiler(ROOT / "content/authoring" / source, self.pack),
                json.loads((ROOT / "content/batches" / batch).read_text()))

    def test_n5_reading_delivery_includes_real_heldout_questions(self):
        n5 = [r for r in self.pack["readings"] if r["level"] == "N5"]
        self.assertGreaterEqual(len(n5), 80)
        self.assertGreaterEqual(sum(r.get("purpose") == "assessment" for r in n5), 16)
        new = [r for r in n5 if r["id"].startswith("rn5")]
        self.assertEqual(len(new), 56)
        for reading in new:
            self.assertEqual(len(reading["questions"]), 2)
            self.assertEqual(len(reading["paragraphs"]), 2)
        for n in range(1, 43):
            lesson = next(l for l in self.pack["lessons"] if l["id"] == f"lgn5{n:02d}")
            self.assertEqual(lesson["readingID"], f"rn5{n:03d}")

    def test_new_homophones_keep_separate_targets_and_sense_cues(self):
        words = {w["text"]: w for w in self.pack["items"] if w["kind"] == "word"}
        for first, second in [("早い", "速い"), ("いる", "要る"), ("閉める", "締める"), ("箸", "橋")]:
            self.assertNotEqual(words[first]["id"], words[second]["id"])
            self.assertEqual(words[first]["reading"], words[second]["reading"])
            self.assertTrue(words[second].get("readingCue"), second)
        _, occurrences = markup_sentence(
            "[ネクタイ|ねくたい]を[締|し|締める]めて、[ドア|どあ]を[閉|し|閉める]めます。", words)
        self.assertEqual([w["itemID"] for w in occurrences],
            [words[t]["id"] for t in ["ネクタイ", "締める", "ドア", "閉める"]])

    def test_alternative_readings_are_same_sense_with_a_source(self):
        words = {w["text"]: w for w in self.pack["items"] if w["kind"] == "word"}
        for spelling, variant in [("毎月", "まいげつ"), ("毎年", "まいねん"),
                ("昨夜", "さくや"), ("一昨日", "いっさくじつ"), ("一昨年", "いっさくねん")]:
            word = words[spelling]
            self.assertIn(variant, word["acceptedReadings"])
            self.assertTrue(any(c["sourceID"] == "jmdict" and c["status"] == "reference"
                for c in word["citations"]))
        self.assertNotIn("つらい", words["辛い"].get("acceptedReadings", []))

    def test_new_words_cannot_claim_other_readings_of_the_same_spelling(self):
        words = {w["text"]: w for w in self.pack["items"] if w["kind"] == "word"}
        segments, occurrences = markup_sentence(
            "[空|から]の[箱|はこ]。[一日|ついたち]。[方|ほう]。[年|ねん]。", words)
        self.assertEqual([o["itemID"] for o in occurrences],
            [None, words["箱"]["id"], None, None, None])
        self.assertIsNone(segments[0]["itemID"])
        _, known = markup_sentence("[何|なん]。[四|し]。[読|よ|読む]みます。", words)
        self.assertEqual([o["itemID"] for o in known],
            [words[t]["id"] for t in ["何", "四", "読む"]])
        train = next(s for s in self.pack["sentences"] if s["id"] == "sgn531e")
        self.assertIsNone(next(s for s in train["segments"] if s["text"] == "空")["itemID"])

    def test_a_new_words_own_examples_can_use_its_alternative_reading(self):
        source = "\n".join([
            "L\tlesson\t测试",
            "W\tword\t明日\tあした\tashita\t明天\t名词\tlesson\t昨天\t后天",
            "E\tword\ta\t[明日|あした]です。\t是明天。",
            "E\tword\tb\t[明日|あす]にします。\t改到明天。",
            "A\tword\tあす\tjmdict\t同义读音",
            "N\tword\t明天的两种读音。"])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "words.tsv"; path.write_text(source)
            result = compile_words(path, {"items": []})
        self.assertEqual(result["items"][0]["acceptedReadings"], ["あす"])
        self.assertTrue(result["items"][0]["explanation"].endswith("明天的两种读音。"))
        for sentence in result["sentences"]:
            self.assertEqual(sentence["segments"][0]["itemID"], "word")

    def test_n5_foundation_stage_meets_its_existing_delivery_contract(self):
        n5 = audit(self.pack, self.syllabus, self.reference)["stages"][0]
        self.assertTrue(n5["complete"])
        self.assertFalse(n5["deficits"])

    def test_all_registered_manuscripts_match_batches_in_either_compile_order(self):
        normal = compile_course.compile_all()
        records = compile_course.entries()
        with patch.object(compile_course, "entries", return_value=list(reversed(records))):
            self.assertEqual(normal, compile_course.compile_all())
        for path, batch in normal.items():
            self.assertEqual(batch, json.loads(path.read_text()), path.name)

    def test_new_n4_batches_keep_their_level_and_actual_contexts(self):
        for name in ["011-n4-structures.json", "012-n4-reading-vocabulary.json"]:
            batch = json.loads((ROOT / "content/batches" / name).read_text())
            self.assertTrue(all(i["level"] == "N4" for i in batch["items"] + batch["lessons"]))
        result = audit(self.pack, self.syllabus, self.reference)
        n4 = result["stages"][1]
        self.assertGreaterEqual(n4["grammarPatterns"]["covered"], 37)
        self.assertEqual(n4["required"]["words"], 1000)
        self.assertEqual(n4["required"]["readings"], 100)
        self.assertFalse(result["errors"])
        words = {w["id"]: w for w in self.pack["items"]}
        self.assertEqual(words["vn4037"]["register"], "较正式")
        self.assertIn("にっぽん", words["vn4026"]["acceptedReadings"])

    def test_invalid_or_late_level_headers_fail_instead_of_relabeling_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.tsv"
            for compiler, content in [(compile_words, "H\tN1"),
                    (compile_words, "L\tlesson\t标题\nH\tN4"),
                    (compile_manuscript, "H\tN4\nH\tN3")]:
                path.write_text(content)
                with self.assertRaises(ValueError): compiler(path, self.pack)

    def test_registry_cannot_silently_omit_a_new_manuscript(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); folder = root / "content/authoring"; folder.mkdir(parents=True)
            (folder / "unregistered.tsv").write_text("H\tN4\n")
            (root / "content/manuscripts.json").write_text(json.dumps(dict(version=1, entries=[], staticBatches=[])))
            with patch.object(compile_course, "ROOT", root), self.assertRaisesRegex(AssertionError, "Unregistered"):
                compile_course.entries()

    def test_new_n4_readings_keep_assessments_and_unknown_senses_separate(self):
        new = [r for r in self.pack["readings"] if r["id"].startswith("rn40")]
        self.assertGreaterEqual(len(new), 20)
        self.assertGreaterEqual(sum(r["purpose"] == "assessment" for r in new), 4)
        for reading in new:
            self.assertEqual(len(reading["questions"]), 2)
            self.assertEqual(len(reading["paragraphs"]), 2)
        ordinary_out = next(w["id"] for w in self.pack["items"] if w["kind"] == "word" and w["text"] == "出る")
        for sid in ["rn4011s2", "rn4013s3"]:
            sentence = next(s for s in self.pack["sentences"] if s["id"] == sid)
            response = next(s for s in sentence["segments"] if "出" in s["text"])
            self.assertNotEqual(response["itemID"], ordinary_out, "An exit-word review does not prove the telephone-answering sense")

    def test_heldout_sentences_cannot_become_word_examples(self):
        pack = copy.deepcopy(self.pack)
        pack["items"][0]["exampleSentenceIDs"].append("rn5045s1")
        result = audit(pack, self.syllabus, self.reference)
        self.assertTrue(any("Held-out sentence leaked" in e for e in result["errors"]))
        self.assertFalse(result["complete"])

    def test_same_text_under_another_id_cannot_leak_heldout_sentences(self):
        pack = copy.deepcopy(self.pack)
        original = next(s for s in pack["sentences"] if s["id"] == "rn5045s1")
        duplicate = copy.deepcopy(original); duplicate["id"] = "leakcopy"
        pack["sentences"].append(duplicate)
        pack["items"][0]["exampleSentenceIDs"].append("leakcopy")
        self.assertTrue(any("leakcopy" in e for e in audit(pack, self.syllabus, self.reference)["errors"]))

    def test_proper_names_and_grammar_are_not_false_word_mastery(self):
        words = {"森": dict(id="forest", text="森"), "本": dict(id="book", text="本")}
        _, occurrences = markup_sentence("[森|もり|?]で[本|ほん]を[読|よ|読む]みます。[方|ほう|-]", words)
        self.assertEqual(occurrences[0], dict(text="森", itemID=None))
        self.assertEqual(occurrences[1], dict(text="本", itemID="book"))
        self.assertEqual(occurrences[2], dict(text="読む", itemID=None))
        self.assertEqual(len(occurrences), 3)

    def test_historical_exposure_cannot_be_undone_by_deleting_references(self):
        retired = {r["id"]: r for r in self.syllabus["retiredAssessments"]}
        self.assertEqual(set(retired), {"r036", "r039"})
        pack = copy.deepcopy(self.pack)
        for reading in pack["readings"]:
            if reading["id"] == "r039": reading["purpose"] = "assessment"
        result = audit(pack, self.syllabus, self.reference)
        self.assertTrue(any("Historically exposed assessment must stay retired: r039" == e for e in result["errors"]))
