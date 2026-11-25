#!/usr/bin/env python3
"""Reconstruct unregistered motion/sensation vocabulary without changing quotas.

Checks source facts, word-sense links, stage prerequisites and heldout isolation.
Does not certify independent Japanese review or a released native iOS build.
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
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "content/staging")]
from build_content import validate
from check_n3_similarity import word_index
from compile_grammar import RUBY
from compile_words import compile_manuscript
from word_links import kana, lexical_words, resolve_word, word_lookup

BASELINE = "3db1dba63cb2f0d3b5fa5eb11c9b4ec318b9a702"
BASELINE_SHA256 = "d19e1c7025a6d9bd5384b1220369e6c419b64261dcd4d00ca014c0087ce3f6f5"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
FILES = ["n5-winding-foundation-word.tsv", "n4-motion-foundation-words.tsv",
         "n3-motion-foundation-words.tsv", "n2-motion-and-sensation.tsv"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def previous(path):
    return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT)


def text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(value):
    return {value[i:i + 20] for i in range(len(value) - 19)}


def check():
    review = json.loads((ROOT / "content/staging/n2-motion-review.json").read_text())
    assert review["registered"] is False
    assert review["independentLanguageReviews"] == 0 and review["nativeIOSCompiled"] is False
    assert review["baselineCommit"] == BASELINE and review["baselineResourceSHA256"] == BASELINE_SHA256
    assert review["dictionarySHA256"] == "96baa24218c052fef29de6d0f6fdb1aa35070ca5215f71580b62e8d03b671d36"
    before = previous(RESOURCE)
    assert sha(before) == BASELINE_SHA256
    assert (ROOT / RESOURCE).read_bytes() == before, "Unregistered draft must not change runtime course"
    base = json.loads(before)
    manifest = json.loads(previous("content/manuscripts.json"))
    assert not set(FILES) & {r["source"] for r in manifest["entries"]}
    for name in ["catalog.json", "syllabus.json", "manuscripts.json"]:
        assert (ROOT / "content" / name).read_bytes() == previous("content/" + name)
    for entry in manifest["entries"]:
        path = "content/authoring/" + entry["source"]
        assert (ROOT / path).read_bytes() == previous(path), (path, "prior source changed")
    paths = [ROOT / "content/staging" / name for name in FILES]
    assert review["manuscripts"] == FILES
    for path in paths:
        assert sha(path.read_bytes()) == review["sourceSHA256"][path.name], (path.name, "stale review")
    indexed = word_index(base, paths)
    for _ in range(2):
        for path in paths:
            batch = compile_manuscript(path, indexed)
            ids = {w["id"] for w in batch["items"]}
            indexed["items"] = [w for w in indexed["items"] if w["id"] not in ids] + batch["items"]
    batches = [compile_manuscript(path, indexed) for path in paths]
    new = [w for b in batches for w in b["items"]]
    sentences = [s for b in batches for s in b["sentences"]]
    assert len(new) == len(lexical_words(new)) == len({w["jmdictEntryID"] for w in new}) == 129
    assert Counter(w["level"] for w in new) == {"N5": 2, "N4": 5, "N3": 8, "N2": 114}
    assert len(sentences) == 258 and sum(len(b["exercises"]) for b in batches) == 129
    facts = {r["itemID"]: r for r in review["wordEntries"]}
    assert facts.keys() == {w["id"] for w in new}
    old_roots = lexical_words(base["items"])
    for word in new:
        fact = facts[word["id"]]
        assert (word["text"], word["reading"], word["meaning"], word["partOfSpeech"], word["level"], word["jmdictEntryID"]) == (
            fact["text"], fact["primaryReading"], fact["authoredMeaning"], fact["authoredPartOfSpeech"], fact["level"], fact["entryID"])
        assert word.get("acceptedReadings", []) == fact["acceptedAlternativeReadings"]
        assert word["jmdictEntryID"] not in {w.get("jmdictEntryID") for w in old_roots}
        assert word["text"] not in {w["text"] for w in old_roots}
        assert word["text"] in fact["spellings"] or kana(word["text"]) == kana(word["reading"])
        assert {s["ordinal"] for s in fact["selectedSenseFacts"]} == set(fact["senseOrdinals"])
        for value in [word["reading"]] + word.get("acceptedReadings", []):
            if not re.search(r"[一-龯]", word["text"]):
                assert kana(value) == kana(word["text"]), "Printed kana is its own reading"
            options = [r for r in fact["readingFacts"] if kana(r["reading"]) == kana(value)
                and (not r["restrictions"] or word["text"] in r["restrictions"])
                and not any(flag in info for info in r["information"] for flag in ["obsolete", "out-dated", "search-only"])]
            assert options, (word["id"], value)
            for sense in fact["selectedSenseFacts"]:
                assert not sense["spellingRestrictions"] or word["text"] in sense["spellingRestrictions"]
                assert not sense["readingRestrictions"] or any(r["reading"] in sense["readingRestrictions"] for r in options)
    items = {w["id"]: w for w in indexed["items"]}
    levels = {name: i for i, name in enumerate(["N5", "N4", "N3", "N2"])}
    lookup = word_lookup(indexed["items"])
    excluded = []
    for path in paths:
        for line in path.read_text().splitlines():
            row = line.split("\t")
            if row[0] != "E":
                continue
            assert not re.search(r"\[見\|み\|見る\](?:え|つめ)", row[3]), "Use the actual perception/staring lemma"
            for surface, reading, lemma in RUBY.findall(row[3]):
                if lemma == "-":
                    assert surface in {"方", "一冊", "もう一度"}, (row[1], surface)
                    excluded.append(dict(source=path.name, target=row[1], key=row[2], surface=surface, reading=reading))
                    continue
                assert lemma != "?" and resolve_word(lookup, surface, reading, lemma), (row[1], surface, lemma)
    assert excluded == review["boundGrammarAnnotations"]
    sentence_map = {s["id"]: s for s in sentences}
    for word in new:
        assert len(word["exampleSentenceIDs"]) == 2
        for sid in word["exampleSentenceIDs"]:
            assert any(s.get("itemID") == word["id"] for s in sentence_map[sid]["segments"])
            for segment in sentence_map[sid]["segments"]:
                if wid := segment.get("itemID"):
                    assert levels[items[wid]["level"]] <= levels[word["level"]], (word["id"], wid, "later-stage prerequisite")
    new_texts = {text(s) for s in sentences}
    assert len(new_texts) == 258 and not new_texts & {text(s) for s in base["sentences"]}
    heldout = {sid for r in base["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    old_fragments = set().union(*(fragments(text(s)) for s in base["sentences"] if s["id"] in heldout))
    for sentence in sentences:
        assert not fragments(text(sentence)) & old_fragments, (sentence["id"], "exposes earlier heldout text")
    composed = copy.deepcopy(base)
    for batch in batches:
        for key, rows in batch.items():
            assert not {r["id"] for r in rows} & {r["id"] for r in composed[key]}
            composed[key] += rows
    composed["lessons"].sort(key=lambda r: levels[r["level"]])
    validate(composed)
    prior = json.loads((ROOT / "content/staging/n2-motion-prior-links-review.json").read_text())
    assert prior["baselineCommit"] == BASELINE and prior["runtimeAssociationsApplied"] is False
    assert prior["independentLanguageReviews"] == 0
    assert prior["changesReviewed"] == len(prior["changes"]) == 27
    assert prior["sentencesReviewed"] == len({r["sentenceID"] for r in prior["changes"]}) == 26
    assert prior["explicitBindingsRequired"] == sum(r["requiresExplicitSourceBinding"] for r in prior["changes"]) == 3
    assert prior["oldSourceSHA256"].keys() == {r["source"] for r in manifest["entries"]}
    old_lookup = word_lookup(base["items"])
    actual_auto = []
    for entry in manifest["entries"]:
        name = entry["source"]
        data = previous("content/authoring/" + name)
        assert sha(data) == prior["oldSourceSHA256"][name]
        for line in data.decode().splitlines():
            row = line.split("\t")
            if row[0] not in {"C", "E", "S", "X"}:
                continue
            column = 4 if row[0] == "S" else 2 if row[0] == "X" else 3
            for surface, reading, lemma in RUBY.findall(row[column]):
                lemma = lemma or None
                old = resolve_word(old_lookup, surface, reading, lemma)
                after = resolve_word(lookup, surface, reading, lemma)
                if (old["id"] if old else None) != (after["id"] if after else None):
                    actual_auto.append((name, row[0], tuple(row[1:3] if row[0] != "X" else row[1:2]),
                        surface, reading, lemma, old["id"] if old else None, after["id"] if after else None))

    def identity(record):
        return (record["source"], record["tag"], tuple(record["key"]), record["surface"], record["reading"],
                record["lemma"], record["old"], record["new"])

    assert Counter(actual_auto) == Counter(identity(r) for r in prior["changes"] if not r["requiresExplicitSourceBinding"])
    selected_uses = []
    for wid, fact in facts.items():
        for use in fact["oldUses"]:
            selected_uses.append((use["source"], use["tag"], tuple(use["key"]), use["surface"],
                use["reading"], use["lemma"] or None, use["old"], wid))
    assert Counter(selected_uses) == Counter(identity(r) for r in prior["changes"])
    old_sentences = {s["id"]: s for s in base["sentences"]}
    for change in prior["changes"]:
        assert change["tag"] in {"C", "E"} and change["old"] is None
        segment = old_sentences[change["sentenceID"]]["segments"][change["segmentIndex"]]
        assert (segment["text"], segment["reading"], segment["itemID"]) == (change["surface"], change["reading"], None)
        after = resolve_word(lookup, change["surface"], change["reading"], change["lemma"])
        assert (after is None) == change["requiresExplicitSourceBinding"]
        if after:
            assert after["id"] == change["new"]
    return dict(registered=False, runtimeChanged=False, plannedRoots=129, plannedN2Roots=114,
                earlierBackfills={"N5": 2, "N4": 5, "N3": 8}, originalContexts=258,
                meaningQuestions=129, lessons=sum(len(b["lessons"]) for b in batches),
                allMarkedWordsLearnable=True, laterStageContextWords=0, oldHeldoutLeaks=0,
                prospectiveOldAssociations=27, explicitBindingsRequired=3,
                oldRegisteredSourcesPreserved=len(manifest["entries"]),
                actualN2Roots=sum(w["level"] == "N2" for w in old_roots),
                independentLanguageReviews=0, nativeIOSCompiled=False)


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False))
