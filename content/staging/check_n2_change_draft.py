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
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "content/staging"
sys.path[:0] = [str(ROOT / "scripts"), str(STAGING)]
from check_n3_similarity import word_index
from compile_grammar import RUBY, compile_manuscript as grammar
from compile_words import compile_manuscript as words
from word_links import kana, lexical_words, resolve_word, word_lookup

WORD_FILES = ["n3-change-foundation-words.tsv", "n2-change-prerequisite-words.tsv"]
GRAMMAR_FILE = "n2-change-and-scope.tsv"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
LEVEL = {name: i for i, name in enumerate(["N5", "N4", "N3", "N2"])}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check():
    review = json.loads((STAGING / "n2-change-draft-review.json").read_text())
    assert review["status"].startswith("UNREGISTERED DRAFT")
    assert review["independentLanguageReviews"] == 0
    assert review["nativeIOSCompiled"] is False
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    assert not set(WORD_FILES + [GRAMMAR_FILE]) & {r["source"] for r in manifest["entries"]}
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
    assert len(new_words) == len(lexical_words(new_words)) == 17
    assert Counter(w["level"] for w in new_words) == {"N3": 8, "N2": 9}
    assert sum(len(b["sentences"]) for b in word_batches) == 34
    assert len({w["jmdictEntryID"] for w in new_words}) == 17
    assert len({w["text"] for w in new_words}) == 17
    assert all(w.get("lexemeID") is None and w.get("readingOwnerID") is None for w in new_words)
    facts = {r["itemID"]: r for r in review["wordEntries"]}
    assert facts.keys() == {w["id"] for w in new_words}
    earlier = lexical_words(before["items"])
    for word in new_words:
        fact = facts[word["id"]]
        assert (word["text"], word["reading"], word["meaning"], word["level"], word["jmdictEntryID"]) == (
            fact["text"], fact["primaryReading"], fact["authoredMeaning"], fact["level"], fact["entryID"])
        assert word.get("acceptedReadings", []) == fact["acceptedAlternativeReadings"]
        assert word["text"] in fact["spellings"]
        assert not {w["text"] for w in earlier} & set(fact["spellings"]), (word["id"], "reuse an earlier spelling")
        assert fact["entryID"] not in {w.get("jmdictEntryID") for w in earlier}
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
    assert len(set(s["id"] for b in word_batches + [batch] for s in b["sentences"])) == 106
    lookup = word_lookup(indexed["items"])
    allowed_fragments = {"方", "時", "反面", "半面"}
    for path in paths + [STAGING / GRAMMAR_FILE]:
        rows = [line.split("\t") for line in path.read_text().splitlines() if line and not line.startswith("#")]
        for row in rows:
            if row[0] not in {"C", "E"}:
                continue
            for match in RUBY.finditer(row[3]):
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
    assert before == original, "Draft check must not change the pinned runtime pack"
    return dict(status=review["status"], wordRoots=17, n3FoundationRoots=8, n2Roots=9,
        wordContexts=34, grammarFunctions=12, grammarContexts=72, referencePatterns=11,
        readings=0, independentLanguageReviews=0, registered=False, nativeIOSCompiled=False,
        pending=["naturalness and answer review", "practice and heldout reading authoring",
                 "historical-link review", "registration and full content checks"])


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False, indent=2))
