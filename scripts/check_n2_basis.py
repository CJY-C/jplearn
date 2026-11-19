#!/usr/bin/env python3
"""Rebuild the N2 basis/viewpoint chapter from an immutable course checkpoint.

The language facts are source-checked authoring, not independent Japanese review.
Earlier course text, answers, rules and order must survive the one reviewed link.
"""
import argparse
from collections import Counter
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import subprocess

from build_content import ROOT, validate
from compile_grammar import RUBY, compile_manuscript as compile_grammar
from compile_readings import compile_manuscript as compile_readings
from compile_words import compile_manuscript as compile_words
from word_links import lexical_words, resolve_word, word_lookup

BASELINE = "ac36099b58ca2ddd73b4b66060c8c70b8034708e"
BASELINE_SHA256 = "6995c337638ff4e06c756b5933a314ea9d007846314d1ad422ca9fb9c3e137fd"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
FILES = ["n5-boarding-place-word.tsv", "n2-basis-and-viewpoint.tsv", "n2-basis-readings.tsv"]
REFERENCES = ROOT / "content/staging/n2-basis-additional-references.json"
REVIEW = ROOT / "content/staging/n2-basis-review.json"
WORD_REVIEW = ROOT / "content/staging/n5-boarding-place-word-review.json"
LEDGER = ROOT / "content/source-checks/n2-basis-chapter.json"
OLD_SOURCE = "n5-scene-words.tsv"
OLD_SENTENCE = "svn5956a"
NEW_WORD = "vn5b001"
COLLECTIONS = ["items", "sentences", "exercises", "lessons", "readings", "introModules", "learningRules"]
MAPPING_NOTE = "N2依据、立场与评价：按功能归组；每个目标六个原创语境，近义形式不重复扩造词根。"

# A prerequisite declaration is not proof that the function is practised.
ORDINARY_WITNESSES = {
    "gn2b001": ("rn2101sa", "日記をもとに"),
    "gn2b002": ("rn2102sc", "表記が違うことから"),
    "gn2b003": ("rn2103sa", "弟のことだから"),
    "gn2b004": ("rn2102sb", "様子からすると"),
    "gn2b005": ("rn2103sd", "弟にしたら"),
    "gn2b006": ("rn2104sa", "長さからいうと"),
    "gn2b007": ("rn2101se", "工夫というものだ"),
    "gn2b008": ("rn2104sb", "分かりやすくなるというものではない"),
    "gn2b009": ("rn2105sa", "関係にほかならない"),
    "gn2b010": ("rn2106sa", "経験はあるに越したことはありません"),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


@lru_cache(maxsize=None)
def previous(path):
    return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT)


def source_path(name):
    registered = ROOT / "content/authoring" / name
    return registered if registered.exists() else ROOT / "content/staging" / name


def source_rows(name):
    return [line.split("\t") for line in source_path(name).read_text().splitlines()
            if line and not line.startswith("#")]


def sentence_text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(text):
    return {text[i:i + 20] for i in range(len(text) - 19)}


@lru_cache(maxsize=1)
def source_batches():
    data = previous(RESOURCE)
    assert sha(data) == BASELINE_SHA256, "Basis checkpoint changed"
    pack = json.loads(data)
    additions = json.loads(REFERENCES.read_text())["references"]
    assert not {r["id"] for r in additions} & {r["id"] for r in pack["references"]}
    pack["references"] += additions
    assert not any(w["id"] == NEW_WORD for w in pack["items"])
    row = next(r for r in source_rows(FILES[0]) if r[0] == "W")
    pack["items"].append(dict(id=row[1], kind="word", text=row[2], reading=row[3], meaning=row[5]))
    word = compile_words(source_path(FILES[0]), pack)
    pack["items"] = [w for w in pack["items"] if w["id"] != NEW_WORD]
    for key, records in word.items():
        pack[key].extend(records)
    grammar, coverage = compile_grammar(source_path(FILES[1]), pack)
    for key, records in grammar.items():
        pack[key].extend(records)
    readings = compile_readings(source_path(FILES[2]), pack)
    for key, records in readings.items():
        pack[key].extend(records)
    # The runtime builder inserts earlier backfills into their stage without
    # changing the relative order of the existing lessons in any stage.
    stages = {level: i for i, level in enumerate(["N5", "N4", "N3", "N2"])}
    pack["lessons"].sort(key=lambda lesson: stages[lesson["level"]])
    old = next(s for s in pack["sentences"] if s["id"] == OLD_SENTENCE)
    slots = [s for s in old["segments"] if s["text"] == "乗り場" and s["reading"] == "のりば"]
    assert len(slots) == 1 and slots[0]["itemID"] is None
    slots[0]["itemID"] = NEW_WORD
    return pack, dict(zip(FILES, [word, grammar, readings])), coverage


def check_sources():
    pack, batches, coverage = source_batches()
    word, grammar, readings = [batches[name] for name in FILES]
    assert [w["id"] for w in word["items"]] == [NEW_WORD]
    assert word["items"][0]["level"] == "N5" and word["items"][0]["jmdictEntryID"] == 1600520
    assert len(word["sentences"]) == 2 and len(word["exercises"]) == len(word["lessons"]) == 1
    assert [w["id"] for w in grammar["items"]] == list(ORDINARY_WITNESSES)
    assert all(w["kind"] == "grammar" and w["level"] == "N2" for w in grammar["items"])
    assert len(grammar["sentences"]) == len(grammar["exercises"]) == 60
    assert len(grammar["lessons"]) == 10 and len(coverage) == 11
    assert all(len(w["exampleSentenceIDs"]) == 6 for w in grammar["items"])
    assert [r["id"] for r in readings["readings"]] == [f"rn210{i}" for i in range(1, 9)]
    assert Counter(r["purpose"] for r in readings["readings"]) == {"practice": 6, "assessment": 2}
    assert len(readings["sentences"]) == 48
    lookup = word_lookup(pack["items"])
    byid = {w["id"]: w for w in pack["items"]}
    order = {level: i for i, level in enumerate(["N5", "N4", "N3", "N2"])}
    for name in FILES:
        for row in source_rows(name):
            if row[0] not in ["E", "C", "S"]:
                continue
            markup = row[4] if row[0] == "S" else row[3]
            for text, reading, lemma in RUBY.findall(markup):
                assert lemma != "?", (name, row[1:3], "No unlearnable proper-name shortcut")
                if lemma == "-":
                    continue
                linked = resolve_word(lookup, text, reading, lemma)
                assert linked, (name, row[1:3], text, "Unresolved content word")
                if row[0] == "E":
                    assert order[linked["level"]] <= order[byid[row[1]]["level"]]
    for key in ["items", "sentences", "exercises", "lessons", "readings"]:
        identifiers = [r["id"] for name in FILES for r in batches[name].get(key, [])]
        assert len(identifiers) == len(set(identifiers)), (key, "Duplicate new ID")
    review = json.loads(REVIEW.read_text())
    for name, expected in review["sourceSHA256"].items():
        assert sha(source_path(name).read_bytes()) == expected, (name, "Unreviewed source")
    assert [g["itemID"] for g in review["grammarFunctions"]] == list(ORDINARY_WITNESSES)
    assert review["independentLanguageReviews"] == 0 and review["nativeIOSCompiled"] is False
    word_review = json.loads(WORD_REVIEW.read_text())
    assert sha(source_path(FILES[0]).read_bytes()) == word_review["manuscriptSHA256"]
    fact = word_review["entries"][0]
    target = word["items"][0]
    assert (fact["itemID"], fact["entryID"], fact["primaryReading"], fact["senseOrdinals"]) == (NEW_WORD, 1600520, "のりば", [1])
    assert fact["text"] == target["text"] and fact["authoredMeaning"] == target["meaning"]
    assert fact["acceptedAlternativeReadings"] == [] and fact["exampleSentenceIDs"] == target["exampleSentenceIDs"]
    assert all(not x["spellingRestrictions"] and not x["readingRestrictions"] for x in fact["selectedSenseFacts"])
    assert fact["acceptedReadingSources"][0]["readingFacts"][0]["reading"] == "のりば"
    old_words = [w for w in lexical_words(pack["items"]) if w["id"] != NEW_WORD]
    assert all(w.get("jmdictEntryID") != 1600520 and w["text"] not in fact["dictionarySpellings"] for w in old_words)
    new_sentences = [s for name in FILES for s in batches[name].get("sentences", [])]
    new_sids = {s["id"] for s in new_sentences}
    old_sentences = [s for s in pack["sentences"] if s["id"] not in new_sids]
    old_texts = {sentence_text(s) for s in old_sentences}
    texts = [sentence_text(s) for s in new_sentences]
    assert len(texts) == len(set(texts)) and not set(texts) & old_texts, "Repeated new context"
    previous_heldout = {sid for r in pack["readings"] if r["id"] not in {r["id"] for r in readings["readings"]}
                        and r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    old_fragments = set().union(*(fragments(sentence_text(s)) for s in old_sentences if s["id"] in previous_heldout))
    assert all(not fragments(t) & old_fragments for t in texts), "Prior assessment leaked into new material"
    sentence_index = {s["id"]: s for s in pack["sentences"]}
    lengths, japanese_lengths = [], []
    for reading in readings["readings"]:
        assert len(reading["paragraphs"]) == 2 and len(reading["questions"]) == 2
        assert len(reading["sentenceIDs"]) == 6 and all(w["itemID"] for w in reading["vocabulary"])
        whole = "".join(sentence_text(sentence_index[sid]) for sid in reading["sentenceIDs"])
        lengths.append(len(whole))
        japanese_lengths.append(sum("ぁ" <= ch <= "ゖ" or "ァ" <= ch <= "ヺ" or "一" <= ch <= "龯" for ch in whole))
        assert japanese_lengths[-1] >= 350, (reading["id"], "Reading is too short")
        assert all(p["vocabulary"] for p in reading["paragraphs"])
        if reading["purpose"] == "assessment":
            own = set(reading["sentenceIDs"])
            heldout = set().union(*(fragments(sentence_text(sentence_index[sid])) for sid in own))
            assert all(not fragments(sentence_text(s)) & heldout for s in pack["sentences"] if s["id"] not in own), (reading["id"], "Assessment exposed elsewhere")
    for gid, (sid, anchor) in ORDINARY_WITNESSES.items():
        assert anchor in sentence_text(sentence_index[sid]), (gid, "Missing ordinary-practice surface")
        reading = next(r for r in readings["readings"] if sid in r["sentenceIDs"])
        assert reading["purpose"] == "practice" and gid in reading["grammarIDs"]
    validate(pack)
    return dict(newRoots=1, n5FoundationRoots=1, n2Roots=0, grammarFunctions=10,
                grammarContexts=60, referencePatterns=11, readings=8, ordinaryReadings=6,
                assessments=2, readingQuestions=16, lessons=11,
                readingLengths=lengths, japaneseCharacterCounts=japanese_lengths,
                wordContextGaps=[], independentLanguageReviews=0, nativeIOSCompiled=False)


def check_prior_changes(current=None):
    ledger = json.loads(LEDGER.read_text())
    assert ledger["baselineCommit"] == BASELINE and ledger["baselineRuntimeSHA256"] == BASELINE_SHA256
    pack, batches, coverage = source_batches()
    after = current if current is not None else json.loads((ROOT / RESOURCE).read_text())
    assert after == pack, "Basis chapter differs from independent source reconstruction"
    for name, expected in ledger["newSourceSHA256"].items():
        assert sha(source_path(name).read_bytes()) == expected, (name, "New source changed")
    for path, expected in ledger["reviewSHA256"].items():
        assert sha((ROOT / path).read_bytes()) == expected, (path, "Source review changed")
    old_manifest = json.loads(previous("content/manuscripts.json"))
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    assert manifest == dict(old_manifest, entries=old_manifest["entries"] + ledger["manifestAdditions"])
    assert len(ledger["manifestAdditions"]) == 3
    for entry in ledger["manifestAdditions"]:
        assert json.loads((ROOT / "content/batches" / entry["batch"]).read_text()) == batches[entry["source"]]
    for entry in old_manifest["entries"]:
        source = entry["source"]
        original = previous("content/authoring/" + source)
        assert sha(original) == ledger["oldSourceInputSHA256"][source]
        expected = original
        if source == OLD_SOURCE:
            text = original.decode()
            assert text.count("[乗り場|のりば]") == 1
            expected = text.replace("[乗り場|のりば]", "[乗り場|のりば|@vn5b001]").encode()
        assert (ROOT / "content/authoring" / source).read_bytes() == expected, (source, "Unreviewed old-source edit")
    catalog = json.loads(previous("content/catalog.json"))
    catalog["references"] += json.loads(REFERENCES.read_text())["references"]
    assert json.loads((ROOT / "content/catalog.json").read_text()) == catalog
    syllabus = json.loads(previous("content/syllabus.json"))
    for pattern, ids in coverage.items():
        key = "N2:" + pattern
        assert key not in syllabus["grammarCoverage"]
        syllabus["grammarCoverage"][key] = dict(itemIDs=ids, note=MAPPING_NOTE)
    assert json.loads((ROOT / "content/syllabus.json").read_text()) == syllabus, "Unreviewed syllabus or quota change"
    expected_ids = {key: [r["id"] for name in FILES for r in batches[name].get(key, [])] for key in COLLECTIONS}
    assert ledger["newIDs"] == expected_ids
    assert ledger["reviewedOldSentenceIDs"] == [OLD_SENTENCE]
    return dict(baselineCommit=BASELINE, oldSourcesChecked=len(old_manifest["entries"]),
                oldCollectionsPreservedExceptReviewedLink=True, changedSentences=1,
                changedAssociations=1, newRoots=1, grammarFunctions=10, newReadings=8)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources-only", action="store_true")
    args = parser.parse_args()
    result = dict(source=check_sources())
    if not args.sources_only:
        result["compatibility"] = check_prior_changes()
    print(json.dumps(result, ensure_ascii=False))
