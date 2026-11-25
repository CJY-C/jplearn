#!/usr/bin/env python3
"""Check an unregistered chapter draft without changing runtime content.

This checks authored forms, selected dictionary facts and prerequisite links.
It does not certify naturalness, teaching effectiveness or a completed chapter.
"""
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "content/staging"
sys.path[:0] = [str(ROOT / "scripts"), str(STAGING)]
from check_n3_similarity import word_index
from build_content import validate
from compile_grammar import RUBY, compile_manuscript as grammar
from compile_readings import compile_manuscript as readings
from compile_words import compile_manuscript as words
from word_links import kana, lexical_words, resolve_word, word_lookup

WORD_FILES = ["n4-change-foundation-word.tsv", "n3-change-foundation-words.tsv", "n2-change-prerequisite-words.tsv"]
GRAMMAR_FILE = "n2-change-and-scope.tsv"
READING_FILE = "n2-change-readings.tsv"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
LEVEL = {name: i for i, name in enumerate(["N5", "N4", "N3", "N2"])}
WITNESSES = {
    "gn2d001": ("rn2301sb", "開館に伴い"),
    "gn2d002": ("rn2301sb", "人数に応じて"),
    "gn2d003": ("rn2302sb", "予想に反して"),
    "gn2d004": ("rn2304sb", "長い期間にわたった"),
    "gn2d005": ("rn2302sa", "川に沿って"),
    "gn2d006": ("rn2303sb", "写真に加えて"),
    "gn2d007": ("rn2304sb", "土地の利用をめぐって"),
    "gn2d008": ("rn2303sa", "写真を中心にした"),
    "gn2d009": ("rn2305sb", "発言を聞きつつ"),
    "gn2d010": ("rn2305sc", "分かりつつも"),
    "gn2d011": ("rn2306sb", "広まりつつある"),
    "gn2d012": ("rn2306sb", "便利な反面"),
}


def text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(value):
    return {value[i:i + 20] for i in range(len(value) - 19)}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check():
    review = json.loads((STAGING / "n2-change-draft-review.json").read_text())
    assert review["status"].startswith("UNREGISTERED DRAFT")
    assert review["independentLanguageReviews"] == 0
    assert review["nativeIOSCompiled"] is False
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    assert not set(WORD_FILES + [GRAMMAR_FILE, READING_FILE]) & {r["source"] for r in manifest["entries"]}
    for name, digest in review["sourceSHA256"].items():
        assert sha((STAGING / name).read_bytes()) == digest, (name, "stale draft review")
    data = subprocess.check_output(["git", "show", review["baselineCommit"] + ":" + RESOURCE], cwd=ROOT)
    assert sha(data) == review["baselineResourceSHA256"]
    assert sha((ROOT / RESOURCE).read_bytes()) == review["baselineResourceSHA256"], "Runtime content changed; review draft against the new baseline"
    before = json.loads(data)
    original = copy.deepcopy(before)
    paths = [STAGING / name for name in WORD_FILES]
    indexed = word_index(before, paths)
    for _ in range(2):
        for path in paths:
            batch = words(path, indexed)
            ids = {w["id"] for w in batch["items"]}
            indexed["items"] = [w for w in indexed["items"] if w["id"] not in ids] + batch["items"]
    word_batches = [words(path, indexed) for path in paths]
    new_words = [w for b in word_batches for w in b["items"]]
    assert len(new_words) == 31 and len(lexical_words(new_words)) == 30
    assert Counter(w["level"] for w in new_words) == {"N4": 1, "N3": 19, "N2": 11}
    assert Counter(w["level"] for w in lexical_words(new_words)) == {"N4": 1, "N3": 18, "N2": 11}
    assert sum(len(b["sentences"]) for b in word_batches) == 62
    assert len({w["jmdictEntryID"] for w in new_words}) == 31
    assert len({w["text"] for w in new_words}) == 31
    senses = [w for w in new_words if w.get("lexemeID")]
    assert len(senses) == 1 and senses[0]["id"] == "vn3u015"
    assert senses[0]["lexemeID"] == "vn4854" and not senses[0].get("readingOwnerID")
    assert senses[0]["reading"] == "いだく" and not senses[0].get("acceptedReadings")
    facts = {r["itemID"]: r for r in review["wordEntries"]}
    assert facts.keys() == {w["id"] for w in new_words}
    earlier = lexical_words(before["items"])
    for word in new_words:
        fact = facts[word["id"]]
        assert (word["text"], word["reading"], word["meaning"], word["level"], word["jmdictEntryID"]) == (
            fact["text"], fact["primaryReading"], fact["authoredMeaning"], fact["level"], fact["entryID"])
        assert word.get("acceptedReadings", []) == fact["acceptedAlternativeReadings"]
        assert word["text"] in fact["spellings"]
        if not word.get("lexemeID"):
            assert not {w["text"] for w in earlier} & set(fact["spellings"]), (word["id"], "reuse an earlier spelling")
        assert fact["entryID"] not in {w.get("jmdictEntryID") for w in earlier}
        assert word.get("lexemeID") == fact.get("lexemeID")
        assert word.get("readingOwnerID") == fact.get("readingOwnerID")
        assert {s["ordinal"] for s in fact["selectedSenseFacts"]} == set(fact["senseOrdinals"])
        for reading in [word["reading"]] + word.get("acceptedReadings", []):
            options = [r for r in fact["readingFacts"] if kana(r["reading"]) == kana(reading)
                and (not r["restrictions"] or word["text"] in r["restrictions"])
                and not any(flag in info for info in r["information"] for flag in ["obsolete", "out-dated", "search-only"])]
            assert options, (word["id"], reading)
            for sense in fact["selectedSenseFacts"]:
                assert not sense["spellingRestrictions"] or word["text"] in sense["spellingRestrictions"]
                assert not sense["readingRestrictions"] or any(r["reading"] in sense["readingRestrictions"] for r in options)
    references = json.loads((STAGING / "n2-change-references.json").read_text())["references"]
    assert len({r["id"] for r in references}) == len(references)
    assert not {r["id"] for r in references} & {r["id"] for r in before["references"]}
    indexed["references"] = indexed["references"] + references
    batch, coverage = grammar(STAGING / GRAMMAR_FILE, indexed)
    assert len(batch["items"]) == len(batch["lessons"]) == 12
    assert len(batch["sentences"]) == len(batch["exercises"]) == 72
    assert len(coverage) == 11
    assert Counter(e["targetID"] for e in batch["exercises"]) == {w["id"]: 6 for w in batch["items"]}
    all_ids = {w["id"] for w in indexed["items"] + batch["items"]}
    for item in batch["items"]:
        assert set(item["prerequisiteIDs"]) <= all_ids
    assert len(set(s["id"] for b in word_batches + [batch] for s in b["sentences"])) == 134
    lookup = word_lookup(indexed["items"])
    allowed_fragments = {"方", "時", "反面", "半面", "直", "限"}
    for path in paths + [STAGING / GRAMMAR_FILE, STAGING / READING_FILE]:
        rows = [line.split("\t") for line in path.read_text().splitlines() if line and not line.startswith("#")]
        for row in rows:
            if row[0] not in {"C", "E", "S"}:
                continue
            for match in RUBY.finditer(row[4] if row[0] == "S" else row[3]):
                surface, reading, lemma = match.groups()
                if lemma == "-":
                    assert surface in allowed_fragments, (row[1], "unreviewed excluded word", surface)
                    continue
                assert lemma != "?", (row[1], "unresolved draft word")
                assert resolve_word(lookup, surface, reading, lemma) is not None, (row[1], surface, reading, lemma)
    levels = {w["id"]: w["level"] for w in indexed["items"]}
    for word_batch in word_batches:
        level = word_batch["items"][0]["level"]
        for sentence in word_batch["sentences"]:
            assert all(not s.get("itemID") or LEVEL[levels[s["itemID"]]] <= LEVEL[level] for s in sentence["segments"])
    reading_batch = readings(STAGING / READING_FILE, indexed)
    passage_map = {r["id"]: r for r in reading_batch["readings"]}
    sentence_map = {s["id"]: s for s in reading_batch["sentences"]}
    assert len(passage_map) == 10 and len(sentence_map) == 60
    assert Counter(r["purpose"] for r in passage_map.values()) == {"practice": 8, "assessment": 2}
    passage_checks = []
    for passage in passage_map.values():
        assert passage["level"] == "N2" and len(passage["paragraphs"]) == 2
        assert len(passage["sentenceIDs"]) == 6 and len(passage["questions"]) == 2
        assert set(passage["grammarIDs"]) <= all_ids
        assert all(v["itemID"] for v in passage["vocabulary"]), passage["id"]
        length = sum(len(text(sentence_map[sid])) for sid in passage["sentenceIDs"])
        assert length >= 350, (passage["id"], length)
        japanese = sum(len(re.findall(r"[一-龯ぁ-ゖァ-ヺ]", text(sentence_map[sid]))) for sid in passage["sentenceIDs"])
        assert japanese >= 350, (passage["id"], "Japanese characters", japanese)
        for question in passage["questions"]:
            assert question["evidenceSentenceIDs"] and set(question["evidenceSentenceIDs"]) <= set(passage["sentenceIDs"])
        passage_checks.append(dict(id=passage["id"], purpose=passage["purpose"], characters=length,
            japaneseCharacters=japanese, annotatedOccurrences=len(passage["vocabulary"]), unlinkedOccurrences=0))
    assert any(s["text"] == "抱" and s["itemID"] == "vn3u015" for s in sentence_map["rn2305sd"]["segments"])
    assert not any(s.get("itemID") == "vn4854" for s in sentence_map["rn2305sd"]["segments"])
    assert next(w for w in new_words if w["id"] == "vn3u011")["reading"] == "いちば"
    assert not next(w for w in new_words if w["id"] == "vn3u011").get("acceptedReadings")
    assert next(w for w in new_words if w["id"] == "vn3u013")["reading"] == "ぶん"
    for gid, (sid, anchor) in WITNESSES.items():
        passage = next(r for r in passage_map.values() if sid in r["sentenceIDs"])
        assert passage["purpose"] == "practice" and gid in passage["grammarIDs"]
        assert anchor in text(sentence_map[sid]), (gid, sid, "ordinary grammar witness")
    for lesson in batch["lessons"]:
        passage = passage_map[lesson["readingID"]]
        assert passage["purpose"] == "practice" and set(lesson["itemIDs"]) <= set(passage["grammarIDs"])
    all_new = [s for b in word_batches + [batch, reading_batch] for s in b["sentences"]]
    assert len({s["id"] for s in all_new}) == len({text(s) for s in all_new}) == 194
    assert not {text(s) for s in before["sentences"]} & {text(s) for s in all_new}
    old_heldout = {sid for r in before["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    old_fragments = set().union(*(fragments(text(s)) for s in before["sentences"] if s["id"] in old_heldout))
    for sentence in all_new:
        assert not fragments(text(sentence)) & old_fragments, (sentence["id"], "reuses old assessment text")
    new_heldout = {sid for r in passage_map.values() if r["purpose"] == "assessment" for sid in r["sentenceIDs"]}
    used = before["sentences"] + [s for s in all_new if s["id"] not in new_heldout]
    used_fragments = set().union(*(fragments(text(s)) for s in used))
    for sid in new_heldout:
        assert not fragments(text(sentence_map[sid])) & used_fragments, (sid, "heldout overlaps training")
    held_passages = [r for r in passage_map.values() if r["purpose"] == "assessment"]
    first_fragments = set().union(*(fragments(text(sentence_map[sid])) for sid in held_passages[0]["sentenceIDs"]))
    assert not any(first_fragments & fragments(text(sentence_map[sid])) for sid in held_passages[1]["sentenceIDs"])
    composed = copy.deepcopy(before)
    composed["references"] += references
    for addition in word_batches + [batch, reading_batch]:
        for key, values in addition.items():
            assert not {r["id"] for r in values} & {r["id"] for r in composed[key]}
            composed[key] += values
    validate(composed)
    prior = json.loads((STAGING / "n2-change-prior-links-review.json").read_text())
    assert prior["baselineCommit"] == review["baselineCommit"]
    assert prior["independentLanguageReviews"] == 0
    assert prior["changesReviewed"] == 22 and prior["physicalReferencesToKeep"] == 5
    old_lookup = word_lookup(before["items"])
    actual_changes, actual_ambiguities = [], []
    for name, digest in prior["oldSourceSHA256"].items():
        path = ROOT / "content/authoring" / name
        assert sha(path.read_bytes()) == digest, (name, "old source changed before registration review")
        for line in path.read_text().splitlines():
            row = line.split("\t")
            if row[0] not in {"C", "E", "S", "X"}:
                continue
            column = 4 if row[0] == "S" else 2 if row[0] == "X" else 3
            for surface, reading, lemma in RUBY.findall(row[column]):
                lemma = lemma or None
                old = resolve_word(old_lookup, surface, reading, lemma)
                identity = (name, row[0], tuple(row[1:3] if row[0] != "X" else row[1:2]), surface, reading, lemma,
                            old["id"] if old else None)
                try:
                    new = resolve_word(lookup, surface, reading, lemma)
                except ValueError:
                    actual_ambiguities.append(identity)
                    continue
                if (old["id"] if old else None) != (new["id"] if new else None):
                    actual_changes.append(identity + (new["id"] if new else None,))

    def identity(record):
        return (record["source"], record["tag"], tuple(record["key"]), record["surface"], record["reading"], record["lemma"], record["old"])

    assert Counter(actual_changes) == Counter(identity(r) + (r["new"],) for r in prior["changes"])
    assert Counter(actual_ambiguities) == Counter(identity(r) for r in prior["ambiguities"])
    assert all(r["expectedAfter"] == r["old"] == "vn4854" and r["reading"] == "だ" for r in prior["ambiguities"])
    assert before == original, "Draft check must not change the pinned runtime pack"
    return dict(status=review["status"], wordRoots=30, wordTargets=31, n4FoundationRoots=1, n3FoundationRoots=18, n3AdditionalSenses=1, n2Roots=11,
        wordContexts=62, grammarFunctions=12, grammarContexts=72, referencePatterns=11,
        readings=10, assessments=2, passageChecks=passage_checks,
        priorAssociationsReviewed=22, physicalBindingsPending=5, oldSourcesUnchanged=len(prior["oldSourceSHA256"]),
        independentLanguageReviews=0, registered=False, nativeIOSCompiled=False,
        pending=["naturalness and answer review",
                 "historical-link review", "registration and full content checks"])


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False, indent=2))
