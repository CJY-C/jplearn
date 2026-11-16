#!/usr/bin/env python3
"""Check the unregistered N3 chapter without changing the runtime pack.

Run from any directory. --update-report refreshes the tracked draft review and
reading gap list. Success certifies structure and isolation, not Japanese quality
or delivery. Dictionary candidates and language review remain separate work.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "content/staging"
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from compile_grammar import KANJI, RUBY, compile_manuscript as grammar
from compile_readings import compile_manuscript as readings
from compile_words import compile_manuscript as words
from word_links import resolve_word, word_lookup

GRAMMAR_FILES = [
    "n3-similarity-and-tendencies.tsv", "n3-similarity-extensions.tsv",
    "n3-tendency-and-coverage.tsv", "n3-state-and-surface.tsv",
    "n3-completion-and-inception.tsv", "n3-retrial-and-difficulty.tsv",
    "n3-boundaries-and-near-misses.tsv", "n3-models-and-correspondence.tsv",
]


def merge(pack, batch):
    for key, values in batch.items():
        existing = {item["id"] for item in pack.get(key, [])}
        identifiers = [item["id"] for item in values]
        assert len(set(identifiers)) == len(identifiers), (key, "duplicate draft ID")
        assert not existing.intersection(identifiers), (key, "registered ID collision")
        pack.setdefault(key, []).extend(values)


def text(sentence):
    return "".join(segment["text"] for segment in sentence["segments"])


def encode(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def review():
    pack = make_pack()
    prior_heldout_ids = {sid for r in pack["readings"] if r.get("purpose") == "assessment"
                         for sid in r["sentenceIDs"]}
    word_path = STAGING / "n3-similarity-theme-words.tsv"
    word_batch = words(word_path, pack)
    merge(pack, word_batch)
    grammar_batches, coverage = [], defaultdict(list)
    for name in GRAMMAR_FILES:
        batch, mapping = grammar(STAGING / name, pack)
        merge(pack, batch)
        grammar_batches.append(batch)
        for key, values in mapping.items():
            coverage[key].extend(values)
    new_grammar = {item["id"] for batch in grammar_batches for item in batch["items"]}
    items = {item["id"]: item for item in pack["items"]}
    for gid in new_grammar:
        assert set(items[gid].get("prerequisiteIDs", [])) <= items.keys(), gid
    paths = sorted(STAGING.glob("n3-similarity*readings.tsv"))
    assert paths, "No reading manuscripts"
    reading_batch = {"sentences": [], "readings": []}
    for path in paths:
        merge(reading_batch, readings(path, pack))
    # Use the normal collision check against registered content and all new
    # vocabulary/grammar examples, before merging the draft reading bundle.
    prior_sentences = list(pack["sentences"])
    merge(pack, reading_batch)
    all_sentences = {s["id"]: s for s in pack["sentences"]}
    new_readings = reading_batch["readings"]
    held_ids = {sid for r in new_readings if r["purpose"] == "assessment"
                for sid in r["sentenceIDs"]}
    practice_ids = {sid for r in new_readings if r["purpose"] == "practice"
                    for sid in r["sentenceIDs"]}
    used_ids = {sid for item in pack["items"] for sid in item.get("exampleSentenceIDs", [])}
    used_ids.update(e["sentenceID"] for e in pack["exercises"])
    used_ids.update(sid for lesson in pack["lessons"] for sid in lesson["sentenceIDs"])
    assert not held_ids.intersection(used_ids | practice_ids), "Held-out ID used in practice"
    prior_heldout_texts = {text(all_sentences[sid]) for sid in prior_heldout_ids}
    assert not prior_heldout_ids.intersection(used_ids | practice_ids), "Registered held-out ID used in practice"
    assert not prior_heldout_texts.intersection(text(all_sentences[sid]) for sid in used_ids | practice_ids), (
        "Registered held-out text leaked into a practice context")
    # Conservative additional scan: no 20-character verbatim fragment from a
    # new assessment may occur in any registered sentence or draft practice.
    # Normal short constructions can recur; full example passages cannot.
    prior_and_practice = prior_sentences + [all_sentences[sid] for sid in sorted(practice_ids)]
    training_texts = {text(s) for s in prior_and_practice}
    fragments = {t[i:i + 20] for t in training_texts for i in range(len(t) - 19)}
    for sid in sorted(held_ids):
        value = text(all_sentences[sid])
        assert value not in training_texts, (sid, "held-out row reused")
        assert not {value[i:i + 20] for i in range(len(value) - 19)}.intersection(fragments), (
            sid, "20-character held-out fragment reused")
    lookup, gaps, names = word_lookup(pack["items"]), defaultdict(list), defaultdict(list)
    for path in paths:
        for line in path.read_text().splitlines():
            row = line.split("\t")
            if row[0] != "S":
                continue
            for match in RUBY.finditer(row[4]):
                surface, ruby, lemma = match.groups()
                if lemma == "?":
                    names[surface].append(row[1] + "s" + row[2])
                elif lemma != "-" and not resolve_word(lookup, surface, ruby, lemma):
                    gaps[lemma or surface].append(row[1] + "s" + row[2])
    assert not any(form.startswith("@") for form in gaps), "Explicit ID has wrong reading"
    seen, summaries, practiced = set(), [], set()
    for r in sorted(new_readings, key=lambda value: value["id"]):
        sentence_rows = [all_sentences[sid] for sid in r["sentenceIDs"]]
        texts = [text(s) for s in sentence_rows]
        assert len(r["sentenceIDs"]) >= 6 and len(r["paragraphs"]) == 2, r["id"]
        assert len(r["questions"]) == 2, r["id"]
        assert not seen.intersection(texts), (r["id"], "draft reading row duplicated")
        seen.update(texts)
        for s in sentence_rows:
            assert not any(KANJI.search(x["text"]) and not x["reading"] for x in s["segments"]), s["id"]
        size = sum(map(len, texts))
        assert size >= 350, (r["id"], size)
        assert r["purpose"] in {"assessment", "practice"}, r["id"]
        assert all(items[gid]["kind"] == "grammar" for gid in r["grammarIDs"]), r["id"]
        if r["purpose"] == "practice":
            practiced.update(r["grammarIDs"])
        missing = sum(v["itemID"] is None for v in r["vocabulary"])
        summaries.append(dict(id=r["id"], purpose=r["purpose"], characters=size,
                              paragraphs=2, sentenceRows=len(texts), questions=len(r["questions"]),
                              annotatedOccurrences=len(r["vocabulary"]), unlinkedOccurrences=missing))
    assert new_grammar <= practiced, ("grammar without ordinary reading", sorted(new_grammar - practiced))
    counts = Counter(r["purpose"] for r in new_readings)
    assert counts["assessment"] / len(new_readings) >= 0.20, "Below 20% held-out share"
    inputs = [word_path] + [STAGING / name for name in GRAMMAR_FILES] + paths
    resource = ROOT / "Sources/LearningCore/Resources/foundation.json"
    resource_hash = hashlib.sha256(resource.read_bytes()).hexdigest()
    return dict(
        status="unregistered draft; structure and isolation checked; language review pending",
        independentlyReviewed=0,
        runtimeResourceMatches0190=resource_hash == "8d4d02628658022c14e741b061c0e6d168d7b95792b60636d272611b61c136d6",
        runtimeResourceSHA256=resource_hash,
        words=len(word_batch["items"]), wordContexts=len(word_batch["sentences"]),
        grammarFunctions=len(new_grammar), grammarContexts=sum(len(b["sentences"]) for b in grammar_batches),
        referencePatterns=len(coverage), ordinaryGrammarFunctionsCovered=len(new_grammar & practiced),
        readings=len(new_readings), practiceReadings=counts["practice"], assessmentReadings=counts["assessment"],
        heldoutFraction=counts["assessment"] / len(new_readings),
        questions=sum(len(r["questions"]) for r in new_readings),
        comparisonSentenceRows=len(prior_and_practice), heldoutRowsChecked=len(held_ids),
        registeredHeldoutRowsChecked=len(prior_heldout_ids),
        heldoutVerbatimFragmentLength=20, heldoutLeakMatches=0,
        notes=["Linked vocabulary is learnable, not evidence that the user knows it.",
               "Unlinked proper names remain in the readiness denominator; they are not new roots.",
               "Unresolved forms are candidates, not a count of selected new words.",
               "Runtime long-reading threshold is 95%; extensive reading uses 98%; each paragraph allows at most three distinct unknowns.",
               "Manuscripts, Chinese, questions and distractors are original; no independent Japanese review claimed."],
        manuscripts={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
        passageChecks=summaries, unresolvedReadingForms=len(gaps),
        gaps=dict(sorted(gaps.items())), deliberatelyUnlinkedProperNames=dict(sorted(names.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-report", action="store_true")
    args = parser.parse_args()
    result = review()
    outputs = {
        STAGING / "n3-similarity-reading-review.json": encode(result),
        STAGING / "n3-similarity-reading-gaps.json": encode(result["gaps"]),
    }
    for path, expected in outputs.items():
        if args.update_report:
            path.write_text(expected)
        else:
            assert path.read_text() == expected, f"Stale report: {path.name}; review then --update-report"
    print(encode({key: result[key] for key in ["words", "wordContexts", "grammarFunctions", "grammarContexts",
          "referencePatterns", "ordinaryGrammarFunctionsCovered", "readings", "practiceReadings",
          "assessmentReadings", "questions", "heldoutLeakMatches", "unresolvedReadingForms"]}), end="")


if __name__ == "__main__":
    main()
