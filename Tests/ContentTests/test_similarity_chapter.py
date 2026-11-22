import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from audit_curriculum import audit
from build_content import make_pack
from word_links import lexical_words


class SimilarityChapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = make_pack()
        cls.items = {i["id"]: i for i in cls.pack["items"]}
        cls.sentences = {s["id"]: s for s in cls.pack["sentences"]}
        cls.readings = {r["id"]: r for r in cls.pack["readings"] if r["id"] in {f"rn{n}" for n in range(3111, 3131)}}

    def test_four_word_sources_retain_checked_senses_and_do_not_inflate_roots(self):
        targets = []
        for source, review_name, roots, count in [
            ("n4-similarity-sense-prerequisites.tsv", "n4-similarity-sense-word-review.json", 1, 2),
            ("n3-similarity-theme-words.tsv", "n3-similarity-theme-word-review.json", 120, 124),
            ("n3-similarity-prerequisite-words.tsv", "n3-similarity-prerequisite-word-review.json", 65, 67),
            ("n3-similarity-reading-prerequisite-words.tsv", "n3-similarity-reading-word-review.json", 92, 93),
        ]:
            review = json.loads((ROOT / "content/staging" / review_name).read_text())
            self.assertEqual(hashlib.sha256((ROOT / "content/authoring" / source).read_bytes()).hexdigest(),
                             review["manuscriptSHA256"])
            words = [self.items[e["itemID"]] for e in review["entries"]]
            self.assertEqual((len(lexical_words(words)), len(words)), (roots, count))
            for fact, word in zip(review["entries"], words):
                self.assertEqual((word["text"], word["reading"], word["meaning"]),
                                 (fact["text"], fact["primaryReading"], fact["authoredMeaning"]))
                self.assertEqual(word.get("acceptedReadings", []), fact["acceptedAlternativeReadings"])
                contexts = [self.sentences[sid] for sid in word["exampleSentenceIDs"]]
                self.assertGreaterEqual(len({self.text(s) for s in contexts}), 2)
                self.assertTrue(all(word["id"] in [s["itemID"] for s in c["segments"]] for c in contexts))
            targets.extend(words)
        self.assertEqual((len(lexical_words(targets)), len(targets)), (278, 286))
        self.assertEqual(sum(w["level"] == "N3" for w in lexical_words(targets)), 277)
        self.assertEqual(self.items["vn3n007"]["lexemeID"], "vn4r001")
        self.assertEqual(self.items["vn4r001"]["level"], "N4")

    @staticmethod
    def text(sentence):
        return "".join(segment["text"] for segment in sentence["segments"])

    def test_every_new_function_has_six_contexts_and_an_ordinary_reading(self):
        functions = {f"gn3b{n:03d}" for n in range(1, 34)}
        self.assertTrue(functions <= self.items.keys())
        for gid in functions:
            exercises = [e for e in self.pack["exercises"] if e["targetID"] == gid]
            self.assertGreaterEqual(len({self.text(self.sentences[e["sentenceID"]]) for e in exercises}), 6, gid)
            lesson = next(l for l in self.pack["lessons"] if gid in l["itemIDs"])
            passage = self.readings[lesson["readingID"]]
            self.assertEqual(passage["purpose"], "practice")
            self.assertIn(gid, passage["grammarIDs"])

    def test_twenty_readings_keep_names_unknown_and_assessments_isolated(self):
        self.assertEqual(len(self.readings), 20)
        self.assertEqual({r["id"] for r in self.readings.values() if r["purpose"] == "assessment"},
                         {"rn3127", "rn3128", "rn3129", "rn3130"})
        held = {sid for r in self.pack["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
        training = [self.text(s) for s in self.pack["sentences"] if s["id"] not in held]
        fragments = {t[i:i + 20] for t in training for i in range(len(t) - 19)}
        for passage in self.readings.values():
            self.assertEqual((len(passage["paragraphs"]), len(passage["questions"]), len(passage["sentenceIDs"])), (2, 2, 6))
            self.assertGreaterEqual(sum(len(self.text(self.sentences[sid])) for sid in passage["sentenceIDs"]), 350)
            for word in passage["vocabulary"]:
                if word["itemID"] is None:
                    self.assertEqual((passage["id"], word["text"], word.get("properName")), ("rn3130", "ミオ", True))
                else:
                    self.assertIn(self.items[word["itemID"]]["level"], ["N5", "N4", "N3"])
            if passage["purpose"] == "assessment":
                for sid in passage["sentenceIDs"]:
                    text = self.text(self.sentences[sid])
                    self.assertFalse(fragments.intersection(text[i:i + 20] for i in range(len(text) - 19)), sid)
        names = self.readings["rn3130"]
        self.assertEqual(names["properNames"], ["ミオ"])
        self.assertEqual(sum(w["itemID"] is None for w in names["vocabulary"]), 4)

    def test_reviewed_old_links_use_the_actual_contextual_sense(self):
        review = json.loads((ROOT / "content/staging/n3-similarity-prior-link-candidates.json").read_text())
        self.assertEqual(len(review["entries"]), 98)
        self.assertEqual(sum(d["decision"] == "preserveExisting" for d in review["entries"]), 4)
        self.assertEqual(sum(d["decision"] == "redirectUntaughtSense" for d in review["entries"]), 10)
        for decision in review["entries"]:
            sentence = self.sentences[decision["context"]]
            self.assertIn(decision["chosenTargetID"], [s["itemID"] for s in sentence["segments"]], decision["context"])
        for sid, target in [("svn3j007b", "vn3l123"), ("svn3j084b", "vn3m066"),
                            ("svn3b077b", "vn3m067"), ("svn3h123a", "vn3l124"),
                            ("svn4i092a", "vn4r002")]:
            self.assertIn(target, [s["itemID"] for s in self.sentences[sid]["segments"]])

    def test_n3_source_delivery_passes_without_borrowing_the_n2_quota(self):
        result = audit(self.pack, json.loads((ROOT / "content/syllabus.json").read_text()),
                       json.loads((ROOT / "content/reference/openjlpt-grammar.json").read_text()))
        n3, n2 = result["stages"][2:]
        self.assertTrue(n3["complete"])
        self.assertEqual(n3["grammarPatterns"]["covered"], 101)
        self.assertEqual(n3["actual"]["words"], 1658)
        self.assertEqual(n2["required"]["words"], 2500)
        self.assertFalse(n2["complete"])
        self.assertFalse(result["complete"])
        self.assertFalse(result["errors"])
