#!/usr/bin/env python3
"""Check original dialogue transfer readings and exact prior-course preservation.

This verifies explicit evidence/annotation records, not independent language
review or an empirical claim about how quickly a learner will improve.
"""
from collections import Counter
from functools import lru_cache
import copy
import hashlib
import json
import re
import subprocess

from build_content import ROOT, validate
from compile_grammar import RUBY
from compile_readings import compile_manuscript
from word_links import resolve_word, word_lookup

BASELINE = "4ecbbf1ffae5d406ba3efa47e424d54a5327f5f7"
BASELINE_SHA256 = "55e783e2bd05532616c5ad3dfe16e3a21970f420496800b27b00a1b40cfac05d"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
MANUSCRIPT = "n2-dialogue-bridge-readings.tsv"
ENTRY = dict(kind="reading", source=MANUSCRIPT, batch="102-n2-dialogue-bridge-readings.json")
REVIEW = "content/staging/n2-dialogue-bridge-review.json"
LEDGER = ROOT / "content/source-checks/n2-dialogue-bridge.json"
IDS = ["rnbd001", "rnbd002", "rnbd003"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


@lru_cache(maxsize=None)
def previous(path):
    return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT)


def text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(value):
    return {value[i:i + 20] for i in range(len(value) - 19)}


@lru_cache(maxsize=1)
def source_review():
    before_bytes = previous(RESOURCE)
    assert sha(before_bytes) == BASELINE_SHA256
    before = json.loads(before_bytes)
    review = json.loads((ROOT / REVIEW).read_text())
    assert review["baselineCommit"] == BASELINE
    assert review["independentLanguageReviews"] == 0
    assert review["nativeIOSCompiled"] is False
    path = ROOT / "content/authoring" / MANUSCRIPT
    assert sha(path.read_bytes()) == review["manuscriptSHA256"], "Dialogue review needs updating"
    batch = compile_manuscript(path, before)
    assert list(batch) == ["sentences", "readings"]
    assert [r["id"] for r in batch["readings"]] == IDS
    assert len(batch["sentences"]) == 18
    assert Counter(r["purpose"] for r in batch["readings"]) == {"practice": 2, "assessment": 1}
    lookup = word_lookup(before["items"])
    # Only bound inflection/grammar parts may be outside the word denominator.
    # Kana endings/interjections are manually reviewed; this is not NLP coverage.
    excluded = []
    for line in path.read_text().splitlines():
        row = line.split("\t")
        if row[0] != "S":
            continue
        for surface, reading, lemma in RUBY.findall(row[4]):
            if lemma == "-":
                excluded.append([row[1], row[2], surface, reading])
            else:
                assert lemma != "?" and resolve_word(lookup, surface, reading, lemma), (row[1:3], surface)
    assert excluded == review["boundGrammarAnnotations"]
    sentences = {s["id"]: s for s in batch["sentences"]}
    items = {w["id"]: w for w in before["items"]}
    questions = {q["id"]: q for r in batch["readings"] for q in r["questions"]}
    assert len(questions) == 9 and questions.keys() == review["questionEvidence"].keys()
    checks = []
    for passage in batch["readings"]:
        assert passage["level"] == "N2"
        assert len(passage["paragraphs"]) == 2 and len(passage["sentenceIDs"]) == 6
        assert len(passage["questions"]) == 3
        assert all(v["itemID"] in items for v in passage["vocabulary"])
        assert all(items[g]["kind"] == "grammar" for g in passage["grammarIDs"])
        japanese = sum(len(re.findall(r"[一-龯ぁ-ゖァ-ヺ]", text(sentences[sid]))) for sid in passage["sentenceIDs"])
        assert japanese >= 350, (passage["id"], japanese)
        for question in passage["questions"]:
            fact = review["questionEvidence"][question["id"]]
            assert fact["answer"] == question["choices"][question["answerIndex"]]
            assert fact["ability"] == question["ability"]
            assert fact["evidenceSentenceIDs"] == question["evidenceSentenceIDs"]
            assert fact["reasoning"] and fact["rejectedInferences"]
            assert {a["sentenceID"] for a in fact["anchors"]} <= set(question["evidenceSentenceIDs"])
            for anchor in fact["anchors"]:
                assert anchor["text"] in text(sentences[anchor["sentenceID"]]), (question["id"], anchor)
        witnesses = review["grammarWitnesses"][passage["id"]]
        assert witnesses.keys() == set(passage["grammarIDs"])
        for gid, witness in witnesses.items():
            assert witness["sentenceID"] in passage["sentenceIDs"]
            assert witness["text"] in text(sentences[witness["sentenceID"]]), (gid, witness)
        checks.append(dict(id=passage["id"], purpose=passage["purpose"], japaneseCharacters=japanese,
                           annotatedOccurrences=len(passage["vocabulary"]), unlinkedOccurrences=0, questions=3))
    new_texts = [text(s) for s in batch["sentences"]]
    assert len(set(new_texts)) == 18
    assert not set(new_texts) & {text(s) for s in before["sentences"]}
    old_heldout = {sid for r in before["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    heldout_fragments = set().union(*(fragments(text(s)) for s in before["sentences"] if s["id"] in old_heldout))
    for sentence in batch["sentences"]:
        assert not fragments(text(sentence)) & heldout_fragments, (sentence["id"], "exposes earlier assessment")
    heldout = set(batch["readings"][-1]["sentenceIDs"])
    training_fragments = set().union(*(fragments(text(s)) for s in before["sentences"] + batch["sentences"] if s["id"] not in heldout))
    for sid in heldout:
        assert not fragments(text(sentences[sid])) & training_fragments, (sid, "assessment repeats training")
    expected = copy.deepcopy(before)
    for key, values in batch.items():
        assert not {r["id"] for r in values} & {r["id"] for r in expected[key]}
        expected[key] += values
    assert not any(l.get("readingID") in IDS for l in expected["lessons"])
    validate(expected)
    return expected, batch, dict(readings=3, practiceReadings=2, assessments=1, questions=9,
        newRoots=0, newGrammarCards=0, passageChecks=checks, independentLanguageReviews=0,
        nativeIOSCompiled=False, scope="Original project reading transfer; not an official N2 level certification")


def check_sources():
    return source_review()[2]


def check_prior_changes(current=None):
    ledger = json.loads(LEDGER.read_text())
    assert (ledger["baselineCommit"], ledger["baselineRuntimeSHA256"]) == (BASELINE, BASELINE_SHA256)
    expected, batch, _ = source_review()
    actual = current if current is not None else json.loads((ROOT / RESOURCE).read_text())
    assert actual == expected, "Dialogue bridge or historical course differs from reconstruction"
    assert sha((ROOT / RESOURCE).read_bytes()) == ledger["runtimeSHA256"]
    assert ledger["manuscripts"] == [MANUSCRIPT] and ledger["manifestAdditions"] == [ENTRY]
    assert sha((ROOT / "content/authoring" / MANUSCRIPT).read_bytes()) == ledger["manuscriptSHA256"]
    assert ledger["reviewSHA256"] == {REVIEW: sha((ROOT / REVIEW).read_bytes())}
    manifest = json.loads(previous("content/manuscripts.json"))
    assert json.loads((ROOT / "content/manuscripts.json").read_text()) == dict(manifest, entries=manifest["entries"] + [ENTRY])
    old_sources = {r["source"] for r in manifest["entries"]}
    assert old_sources == ledger["oldSourceInputSHA256"].keys()
    for source in old_sources:
        old = previous("content/authoring/" + source)
        assert sha(old) == ledger["oldSourceInputSHA256"][source]
        assert (ROOT / "content/authoring" / source).read_bytes() == old, (source, "old source changed")
    assert json.loads((ROOT / "content/batches" / ENTRY["batch"]).read_text()) == batch
    assert (ROOT / "content/catalog.json").read_bytes() == previous("content/catalog.json")
    syllabus = json.loads(previous("content/syllabus.json"))
    bridge = next(b for b in syllabus["readingBridges"] if b["id"] == "dialogue")
    assert bridge["minimumReadings"] == 3 and bridge["readingIDs"] == []
    bridge["readingIDs"] = IDS
    assert json.loads((ROOT / "content/syllabus.json").read_text()) == syllabus
    assert ledger["newIDs"] == {key: [r["id"] for r in values] for key, values in batch.items()}
    return dict(baselineCommit=BASELINE, oldSourcesChecked=len(old_sources), newReadings=3,
                allOldCollectionsPreserved=True, changedPriorAssociations=0)


if __name__ == "__main__":
    print(json.dumps(dict(source=check_sources(), compatibility=check_prior_changes()), ensure_ascii=False))
