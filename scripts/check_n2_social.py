#!/usr/bin/env python3
"""Reconstruct the social/work vocabulary batch and its seven reviewed links.

Dictionary facts and original authoring are checked separately from native iOS
delivery and independent language review; neither is implied by this proof.
"""
import argparse
from collections import Counter
import copy
from functools import lru_cache
import hashlib
import json
import subprocess

from build_content import ROOT, validate
from compile_grammar import RUBY
from compile_words import compile_manuscript
from word_links import kana, lexical_words, resolve_word, word_lookup

BASELINE = "881c17d4061f4562b7eac91342466c5e7c5a68f5"
BASELINE_SHA256 = "50bc68521902c8e60bda6ed026bcaf59136edeef7d6c17b9ae859947d0a9dcc5"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
FILES = ["n4-job-offer-foundation-word.tsv", "n3-social-foundation-words.tsv", "n2-social-and-work-words.tsv"]
LEDGER = ROOT / "content/source-checks/n2-social-chapter.json"
COLLECTIONS = ["items", "sentences", "exercises", "lessons", "readings", "introModules", "learningRules"]
STAGES = {level: i for i, level in enumerate(["N5", "N4", "N3", "N2"])}
# Only these old associations may change. Text, ruby, translation and answers stay.
OLD_LINKS = [
    ("n4-society-and-daily-life.tsv", "vn4i067", "b", "求人", "きゅうじん", "vn4jobs001"),
    ("n4-society-and-daily-life.tsv", "vn4i175", "b", "求人", "きゅうじん", "vn4jobs001"),
    ("n3-temporal-and-change-words.tsv", "vn3f052", "b", "商業", "しょうぎょう", "vn3r001"),
    ("n3-condition-and-perspective-words.tsv", "vn3j093", "b", "支援", "しえん", "vn3r003"),
    ("n3-condition-and-perspective-words.tsv", "vn3j118", "a", "支援", "しえん", "vn3r003"),
    ("n3-condition-and-perspective-words.tsv", "vn3j119", "b", "後輩", "こうはい", "vn3r002"),
    ("n3-condition-and-perspective-words.tsv", "vn3j173", "b", "保護", "ほご", "vn3r004"),
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


@lru_cache(maxsize=None)
def previous(path):
    return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT)


def source_path(name):
    registered = ROOT / "content/authoring" / name
    return registered if registered.exists() else ROOT / "content/staging" / name


def review_path(name):
    return ROOT / "content/staging" / (name.removesuffix(".tsv") + "-review.json")


def source_rows(name):
    return [line.split("\t") for line in source_path(name).read_text().splitlines()
            if line and not line.startswith("#")]


def expected_old_source(name):
    lines = previous("content/authoring/" + name).decode().splitlines(keepends=True)
    for source, target, key, surface, reading, wid in OLD_LINKS:
        if source != name:
            continue
        slots = [i for i, line in enumerate(lines) if line.startswith("\t".join(["E", target, key]) + "\t")]
        assert len(slots) == 1
        index = slots[0]
        before = f"[{surface}|{reading}]"
        assert lines[index].count(before) == 1
        lines[index] = lines[index].replace(before, f"[{surface}|{reading}|@{wid}]")
    return "".join(lines).encode()


def sentence_text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(text):
    return {text[i:i + 20] for i in range(len(text) - 19)}


@lru_cache(maxsize=1)
def source_batches():
    data = previous(RESOURCE)
    assert sha(data) == BASELINE_SHA256, "Social vocabulary checkpoint changed"
    before = json.loads(data)
    declared = {}
    for name in FILES:
        rows = source_rows(name)
        for r in rows:
            if r[0] == "W":
                assert r[1] not in declared
                declared[r[1]] = dict(id=r[1], kind="word", text=r[2], reading=r[3], meaning=r[5])
        for r in rows:
            if r[0] == "A": declared[r[1]]["acceptedReadings"] = r[2].split(",")
            if r[0] == "G": declared[r[1]]["lexemeID"] = r[2]
            if r[0] == "J": declared[r[1]]["jmdictEntryID"] = int(r[2])
    assert not declared.keys() & {w["id"] for w in before["items"]}, "New word ID collision"
    indexed = dict(before, items=before["items"] + list(declared.values()))
    batches = {}
    for _ in range(2):
        for name in FILES:
            batch = compile_manuscript(source_path(name), indexed)
            ids = {w["id"] for w in batch["items"]}
            indexed["items"] = [w for w in indexed["items"] if w["id"] not in ids] + batch["items"]
            batches[name] = batch
    pack = copy.deepcopy(before)
    for batch in batches.values():
        for key, rows in batch.items():
            assert not {r["id"] for r in rows} & {r["id"] for r in pack[key]}, (key, "New ID collision")
            pack[key].extend(copy.deepcopy(rows))
    pack["lessons"].sort(key=lambda lesson: STAGES[lesson["level"]])
    sentences = {s["id"]: s for s in pack["sentences"]}
    for _, target, key, surface, reading, wid in OLD_LINKS:
        sentence = sentences["s" + target + key]
        slots = [s for s in sentence["segments"] if s["text"] == surface and s["reading"] == reading]
        assert len(slots) == 1 and slots[0]["itemID"] is None
        slots[0]["itemID"] = wid
    return pack, batches


def check_sources():
    pack, batches = source_batches()
    before = json.loads(previous(RESOURCE))
    old_roots = lexical_words(before["items"])
    old_entries = {w.get("jmdictEntryID") for w in old_roots}
    items = {w["id"]: w for w in pack["items"]}
    lookup = word_lookup(pack["items"])
    heldout_ids = {sid for r in before["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    heldout = set().union(*(fragments(sentence_text(s)) for s in before["sentences"] if s["id"] in heldout_ids))
    seen = {sentence_text(s) for s in before["sentences"]}
    roots, targets, context_count = Counter(), 0, 0
    for name, batch in batches.items():
        review = json.loads(review_path(name).read_text())
        assert sha(source_path(name).read_bytes()) == review["manuscriptSHA256"], (name, "Unreviewed manuscript")
        assert review["independentLanguageReviews"] == 0 and review["nativeIOSCompiled"] is False
        assert review["unresolvedContextForms"] == {}
        assert review["dictionary"]["gzipSHA256"] == "96baa24218c052fef29de6d0f6fdb1aa35070ca5215f71580b62e8d03b671d36"
        assert review["communityReferenceCommit"] == "0d1d3410bec90bd4098a7c72de820543cb4f707c"
        facts = {f["itemID"]: f for f in review["entries"]}
        assert list(facts) == [w["id"] for w in batch["items"]]
        for w in batch["items"]:
            f = facts[w["id"]]
            assert (f["text"], f["primaryReading"], f["authoredMeaning"], f["entryID"]) == (w["text"], w["reading"], w["meaning"], w["jmdictEntryID"])
            assert f["exampleSentenceIDs"] == w["exampleSentenceIDs"] and w["text"] in f["dictionarySpellings"]
            assert (f["lexemeID"], f["readingOwnerID"]) == (w.get("lexemeID"), w.get("readingOwnerID"))
            assert f["entryID"] not in old_entries
            assert not any(old["text"] in f["dictionarySpellings"] and kana(old["reading"]) in
                           {kana(r) for r in [w["reading"]] + w.get("acceptedReadings", [])} for old in old_roots), (w["id"], "Existing root duplicated")
            accepted = [w["reading"]] + w.get("acceptedReadings", [])
            assert f["acceptedAlternativeReadings"] == w.get("acceptedReadings", [])
            assert [r["acceptedReading"] for r in f["acceptedReadingSources"]] == accepted
            assert [s["ordinal"] for s in f["selectedSenseFacts"]] == f["senseOrdinals"]
            for reading in f["acceptedReadingSources"]:
                cross = (w["id"], reading["acceptedReading"]) == ("vn2e012", "しょたい")
                senses = reading["selectedSenseFacts"] if cross else f["selectedSenseFacts"]
                assert reading["entryID"] == (2869002 if cross else f["entryID"])
                assert reading["senseOrdinals"] == ([1] if cross else f["senseOrdinals"])
                if cross:
                    assert f["entryID"] == 1374170 and w["text"] == "世帯"
                    assert w["text"] in reading["dictionarySpellings"] and reading["compatibility"]
                assert reading["readingFacts"]
                for r in reading["readingFacts"]:
                    assert kana(r["reading"]) == kana(reading["acceptedReading"])
                    assert not r["spellingRestrictions"] or w["text"] in r["spellingRestrictions"]
                    assert not any(flag in info for info in r["information"] for flag in ["obsolete", "out-dated", "search-only"])
                for sense in senses:
                    assert not sense["spellingRestrictions"] or w["text"] in sense["spellingRestrictions"]
                    assert not sense["readingRestrictions"] or any(r["reading"] in sense["readingRestrictions"] for r in reading["readingFacts"])
            roots[w["level"]] += not w.get("lexemeID")
            targets += 1
        for sentence in batch["sentences"]:
            text = sentence_text(sentence)
            assert text not in seen, (sentence["id"], "Repeated context")
            seen.add(text)
            assert not fragments(text) & heldout, (sentence["id"], "Assessment leaked")
            target = next(w for w in batch["items"] if sentence["id"] in w["exampleSentenceIDs"])
            assert any(s["itemID"] == target["id"] for s in sentence["segments"])
            assert all(STAGES[items[s["itemID"]]["level"]] <= STAGES[target["level"]] for s in sentence["segments"] if s["itemID"])
            context_count += 1
        for r in source_rows(name):
            if r[0] != "E": continue
            for surface, ruby, lemma in RUBY.findall(r[3]):
                assert lemma != "?", (r[1:3], "Unreviewed skipped form")
                if lemma != "-": assert resolve_word(lookup, surface, ruby, lemma), (r[1:3], lemma or surface)
    assert roots == {"N4": 1, "N3": 12, "N2": 111} and targets == 125 and context_count == 250
    sense = items["vn2e112"]
    assert sense["lexemeID"] == sense["readingOwnerID"] == "vn2e106"
    assert sense["meaning"] != items["vn2e106"]["meaning"]
    assert {w["id"] for b in batches.values() for w in b["items"] if w.get("lexemeID")} == {"vn2e112"}
    for wid, expected in {"vn2e011": ["わたくしりつ"], "vn2e012": ["しょたい"], "vn2e014": ["せろん", "せいろん"],
                          "vn2e026": ["かいじょう"], "vn2e027": ["せこう"], "vn2e078": ["ちんきん"], "vn3r009": ["しょうがっきん"]}.items():
        assert items[wid]["acceptedReadings"] == expected
    validate(pack)
    return dict(newRoots=124, n2Roots=111, n3Roots=12, n4Roots=1, additionalSenses=1,
                targets=125, contexts=250, exercises=125, lessons=18, heldoutLeaks=0,
                unresolvedContextForms=0, independentLanguageReviews=0, nativeIOSCompiled=False)


def check_prior_changes(current=None):
    ledger = json.loads(LEDGER.read_text())
    assert (ledger["baselineCommit"], ledger["baselineRuntimeSHA256"]) == (BASELINE, BASELINE_SHA256)
    expected, batches = source_batches()
    after = current if current is not None else json.loads((ROOT / RESOURCE).read_text())
    later = None
    if (ROOT / "content/source-checks/n2-conditions-chapter.json").exists():
        from check_n2_conditions import check_prior_changes as check_conditions
        later = check_conditions(after)
        checkpoint = later["baselineCommit"]
        after = json.loads(subprocess.check_output(["git", "show", checkpoint + ":" + RESOURCE], cwd=ROOT))

    def current_data(path):
        if later is not None:
            return subprocess.check_output(["git", "show", checkpoint + ":" + path], cwd=ROOT)
        return (ROOT / path).read_bytes()

    assert after == expected, "Social batch differs from source reconstruction or unreviewed historical data changed"
    assert ledger["manuscripts"] == FILES
    for name in FILES:
        assert sha(source_path(name).read_bytes()) == ledger["newSourceSHA256"][name]
        assert sha(review_path(name).read_bytes()) == ledger["reviewSHA256"][str(review_path(name).relative_to(ROOT))]
    old_manifest = json.loads(previous("content/manuscripts.json"))
    manifest = json.loads(current_data("content/manuscripts.json"))
    additions = [dict(kind="word", source=n, batch=f"{88+i:03}-{n.removesuffix('.tsv')}.json") for i, n in enumerate(FILES)]
    assert ledger["manifestAdditions"] == additions
    assert manifest == dict(old_manifest, entries=old_manifest["entries"] + additions)
    for entry in additions:
        assert json.loads((ROOT / "content/batches" / entry["batch"]).read_text()) == batches[entry["source"]]
    for entry in old_manifest["entries"]:
        name = entry["source"]
        assert sha(previous("content/authoring/" + name)) == ledger["oldSourceInputSHA256"][name]
        assert current_data("content/authoring/" + name) == expected_old_source(name), (name, "Unreviewed prior source change")
    for path in ["content/catalog.json", "content/syllabus.json"]:
        assert current_data(path) == previous(path), (path, "Metadata or quotas changed")
    assert ledger["newIDs"] == {k: [r["id"] for b in batches.values() for r in b.get(k, [])] for k in COLLECTIONS}
    assert ledger["reviewedOldSentenceIDs"] == ["s" + target + key for _, target, key, *_ in OLD_LINKS]
    return dict(baselineCommit=BASELINE, oldSourcesChecked=len(old_manifest["entries"]),
                oldCollectionsPreservedExceptReviewedLinks=True, changedSentences=7,
                changedAssociations=7, newRoots=124, n2Roots=111,
                subsequentConditionsChangesVerified=later is not None)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources-only", action="store_true")
    args = parser.parse_args()
    result = dict(source=check_sources())
    if not args.sources_only:
        result["compatibility"] = check_prior_changes()
    print(json.dumps(result, ensure_ascii=False))
