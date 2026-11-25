#!/usr/bin/env python3
"""Check the N3 similarity chapter without changing the runtime pack.

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
SOURCE_DIR = ROOT / "content/authoring"
WORD_FILES = ["n4-similarity-sense-prerequisites.tsv", "n3-similarity-theme-words.tsv",
              "n3-similarity-prerequisite-words.tsv", "n3-similarity-reading-prerequisite-words.tsv"]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack, validate
from compile_grammar import KANJI, RUBY, compile_manuscript as grammar
from compile_readings import compile_manuscript as readings
from compile_words import compile_manuscript as words
from word_links import kana, lexical_words, resolve_word, word_lookup

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


def word_index(pack, paths):
    """Seed explicit declarations before resolving cross-manuscript references."""
    result = dict(pack, items=list(pack["items"]))
    declared = {}
    for path in paths:
        rows = [line.split("\t") for line in path.read_text().splitlines()
                if line and not line.startswith("#")]
        for row in rows:
            if row[0] != "W":
                continue
            _, wid, text, reading, _, meaning, *_ = row
            assert wid not in declared, (wid, "duplicate word declaration")
            declared[wid] = dict(id=wid, kind="word", text=text, reading=reading, meaning=meaning)
        for row in rows:
            if row[0] == "A": declared[row[1]]["acceptedReadings"] = row[2].split(",")
            if row[0] == "G": declared[row[1]]["lexemeID"] = row[2]
            if row[0] == "J": declared[row[1]]["jmdictEntryID"] = int(row[2])
    assert not {item["id"] for item in result["items"]}.intersection(declared), "Registered word ID collision"
    result["items"].extend(declared.values())
    return result


def base_pack():
    # Exclude this chapter while checking its source compilation and heldout
    # isolation. Earlier sentence annotations may refer forward to these words.
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    names = set(WORD_FILES + GRAMMAR_FILES)
    names.update(p.name for p in SOURCE_DIR.glob("n3-similarity*readings.tsv"))
    # Later N2 targets depend on this chapter. Exclude those downstream
    # batches while retaining the explicitly earlier N4/N3 backfills needed
    # by corrected old contexts. The N2 audit checks the complete composition.
    for ledger_name in ["n2-context-chapter.json", "n2-basis-chapter.json", "n2-social-chapter.json", "n2-conditions-chapter.json", "n2-emotions-chapter.json", "n2-change-chapter.json", "n2-dialogue-bridge.json"]:
        later = ROOT / "content/source-checks" / ledger_name
        if later.exists():
            names.update(name for name in json.loads(later.read_text())["manuscripts"]
                         if name.startswith("n2-"))
    replacements = {ROOT / "content/batches" / r["batch"]: {}
                    for r in manifest["entries"] if r["source"] in names}
    return make_pack(overrides=replacements)


def review():
    pack = base_pack()
    prior_heldout_ids = {sid for r in pack["readings"] if r.get("purpose") == "assessment"
                         for sid in r["sentenceIDs"]}
    word_paths = [SOURCE_DIR / name for name in WORD_FILES]
    # First establish all new words, then recompile the manuscripts against the
    # complete word index so new examples do not depend on the file order.
    index_pack = word_index(pack, word_paths)
    for path in word_paths:
        batch = words(path, index_pack)
        ids = {item["id"] for item in batch["items"]}
        index_pack["items"] = [item for item in index_pack["items"] if item["id"] not in ids] + batch["items"]
    word_batches = [words(path, index_pack) for path in word_paths]
    for index, review_name in [(0, "n4-similarity-sense-word-review.json"),
                               (1, "n3-similarity-theme-word-review.json"),
                               (2, "n3-similarity-prerequisite-word-review.json"),
                               (3, "n3-similarity-reading-word-review.json")]:
        selected_review = json.loads((STAGING / review_name).read_text())
        assert selected_review["manuscriptSHA256"] == hashlib.sha256(word_paths[index].read_bytes()).hexdigest(), (
            "Prerequisite source/sense review is stale", review_name)
        selected_entries = {entry["itemID"]: entry for entry in selected_review["entries"]}
        assert len(selected_entries) == selected_review.get("targets", selected_review["roots"]) == len(word_batches[index]["items"])
        assert len(lexical_words(word_batches[index]["items"])) == selected_review["roots"]
        for item in word_batches[index]["items"]:
            fact = selected_entries[item["id"]]
            assert (item["text"], item["reading"], item["meaning"]) == (
                fact["text"], fact["primaryReading"], fact["authoredMeaning"]), item["id"]
            assert item.get("acceptedReadings", []) == fact["acceptedAlternativeReadings"], item["id"]
            assert item["exampleSentenceIDs"] == fact["exampleSentenceIDs"], item["id"]
            if item.get("jmdictEntryID") is not None:
                assert item["jmdictEntryID"] == fact["entryID"], item["id"]
            assert item.get("lexemeID") == fact.get("lexemeID"), item["id"]
            assert item.get("readingOwnerID") == fact.get("readingOwnerID"), item["id"]
            if "acceptedReadingSources" in fact:
                accepted_readings = [item["reading"]] + item.get("acceptedReadings", [])
                sources = fact["acceptedReadingSources"]
                assert [s["acceptedReading"] for s in sources] == accepted_readings, item["id"]
                for source in sources:
                    if source.get("sourceType") == "phoneticNote":
                        assert item["id"] == "vn3l008" and source["acceptedReading"] == "じつわ"
                        assert source["orthographicReading"] == item["reading"] == "じつは"
                        assert source["documentationNote"] == "は is pronounced as わ"
                        assert any(source["documentationNote"] in s["notes"] for s in fact["selectedSenseFacts"])
                        continue
                    assert source["senseOrdinals"] and source["readingFacts"], item["id"]
                    assert all(not r["spellingRestrictions"] or item["text"] in r["spellingRestrictions"]
                               for r in source["readingFacts"]), item["id"]
                    assert all(kana(r["reading"]) == kana(source["acceptedReading"]) and
                               not r["nokanji"] and not any(
                                   flag in info for info in r["information"]
                                   for flag in ["obsolete", "out-dated", "search-only"])
                               for r in source["readingFacts"]), item["id"]
    pack = base_pack()
    for batch in word_batches:
        merge(pack, batch)
    grammar_batches, coverage = [], defaultdict(list)
    for name in GRAMMAR_FILES:
        batch, mapping = grammar(SOURCE_DIR / name, pack)
        merge(pack, batch)
        grammar_batches.append(batch)
        for key, values in mapping.items():
            coverage[key].extend(values)
    new_grammar = {item["id"] for batch in grammar_batches for item in batch["items"]}
    items = {item["id"]: item for item in pack["items"]}
    for gid in new_grammar:
        assert set(items[gid].get("prerequisiteIDs", [])) <= items.keys(), gid
    paths = sorted(SOURCE_DIR.glob("n3-similarity*readings.tsv"))
    assert paths, "No reading manuscripts"
    reading_batch = {"sentences": [], "readings": []}
    for path in paths:
        merge(reading_batch, readings(path, pack))
    # Use the normal collision check against registered content and all new
    # vocabulary/grammar examples, before merging the draft reading bundle.
    prior_sentences = list(pack["sentences"])
    merge(pack, reading_batch)
    validate(pack)
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
    grammar_gaps = defaultdict(list)
    for name in GRAMMAR_FILES:
        for line in (SOURCE_DIR / name).read_text().splitlines():
            row = line.split("\t")
            if row[0] != "C":
                continue
            for match in RUBY.finditer(row[3]):
                surface, ruby, lemma = match.groups()
                if lemma not in {"-", "?"} and not resolve_word(lookup, surface, ruby, lemma):
                    grammar_gaps[lemma or surface].append(row[1] + row[2])
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
    assert not any(form.startswith("@") for form in grammar_gaps), "Explicit grammar-example word ID has wrong reading"
    for batch in word_batches + grammar_batches + [reading_batch]:
        for sentence in batch["sentences"]:
            assert not any(KANJI.search(s["text"]) and not s["reading"] for s in sentence["segments"]), sentence["id"]
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
        assert all(v.get("properName") is True and v["text"] in r.get("properNames", [])
                   for v in r["vocabulary"] if v["itemID"] is None), r["id"]
        summaries.append(dict(id=r["id"], purpose=r["purpose"], characters=size,
                              paragraphs=2, sentenceRows=len(texts), questions=len(r["questions"]),
                              annotatedOccurrences=len(r["vocabulary"]), unlinkedOccurrences=missing))
    assert new_grammar <= practiced, ("grammar without ordinary reading", sorted(new_grammar - practiced))
    counts = Counter(r["purpose"] for r in new_readings)
    assert counts["assessment"] / len(new_readings) >= 0.20, "Below 20% held-out share"
    inputs = word_paths + [SOURCE_DIR / name for name in GRAMMAR_FILES] + paths
    resource = ROOT / "Sources/LearningCore/Resources/foundation.json"
    resource_hash = hashlib.sha256(resource.read_bytes()).hexdigest()
    return dict(
        status="registered source; structure and isolation checked; independent language review and native release pending",
        currentRuntimeVersion=pack["version"],
        independentlyReviewed=0,
        runtimeResourceMatches0190=resource_hash == "8d4d02628658022c14e741b061c0e6d168d7b95792b60636d272611b61c136d6",
        runtimeResourceSHA256=resource_hash,
        words=sum(len(lexical_words(b["items"])) for b in word_batches),
        wordTargets=sum(len(b["items"]) for b in word_batches),
        wordContexts=sum(len(b["sentences"]) for b in word_batches),
        foundationWords=len(lexical_words(word_batches[0]["items"])), foundationWordTargets=len(word_batches[0]["items"]),
        themeWords=len(lexical_words(word_batches[1]["items"])), themeWordTargets=len(word_batches[1]["items"]),
        prerequisiteWords=len(lexical_words(word_batches[2]["items"])), prerequisiteWordTargets=len(word_batches[2]["items"]),
        readingPrerequisiteWords=len(lexical_words(word_batches[3]["items"])), readingPrerequisiteWordTargets=len(word_batches[3]["items"]),
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
        unresolvedGrammarForms=len(grammar_gaps), combinedUnresolvedForms=len(set(gaps) | set(grammar_gaps)),
        grammarGaps=dict(sorted(grammar_gaps.items())),
        gaps=dict(sorted(gaps.items())), deliberatelyUnlinkedProperNames=dict(sorted(names.items())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-report", action="store_true")
    args = parser.parse_args()
    result = review()
    outputs = {
        STAGING / "n3-similarity-reading-review.json": encode(result),
        STAGING / "n3-similarity-reading-gaps.json": encode(result["gaps"]),
        STAGING / "n3-similarity-prerequisite-gaps.json": encode(result["grammarGaps"]),
    }
    for path, expected in outputs.items():
        if args.update_report:
            path.write_text(expected)
        else:
            assert path.read_text() == expected, f"Stale report: {path.name}; review then --update-report"
    print(encode({key: result[key] for key in ["words", "wordContexts", "grammarFunctions", "grammarContexts",
          "referencePatterns", "ordinaryGrammarFunctionsCovered", "readings", "practiceReadings",
          "assessmentReadings", "questions", "heldoutLeakMatches", "unresolvedReadingForms",
          "unresolvedGrammarForms", "combinedUnresolvedForms"]}), end="")


if __name__ == "__main__":
    main()
