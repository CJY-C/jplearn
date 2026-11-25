#!/usr/bin/env python3
"""Reconstruct conditions/concessions from the immutable pre-chapter course.

This proves authored content and reviewed associations, not independent Japanese
review or native iOS delivery. Earlier stage words never satisfy the N2 quota.
"""
import argparse
from collections import Counter
import copy
from functools import lru_cache
import hashlib
import json
import re
import subprocess

from build_content import ROOT, validate
from compile_grammar import RUBY, compile_manuscript as grammar
from compile_readings import compile_manuscript as readings
from compile_words import compile_manuscript as words
from word_links import kana, lexical_words, resolve_word, word_lookup

BASELINE = "7bc50e1800403e6ed835c5841f03f729fee448d2"
BASELINE_SHA256 = "15725eb28eab56086803e50df37cd24d01e633c8a52972aaea8cc249586da4af"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
FILES = ["n3-conditions-foundation-words.tsv", "n2-condition-reading-words.tsv",
         "n2-conditions-and-concessions.tsv", "n2-conditions-readings.tsv"]
REFERENCES = ROOT / "content/staging/n2-conditions-additional-references.json"
REVIEW = ROOT / "content/staging/n2-conditions-review.json"
LEDGER = ROOT / "content/source-checks/n2-conditions-chapter.json"
COLLECTIONS = ["items", "sentences", "exercises", "lessons", "readings", "introModules", "learningRules"]
STAGES = {level: i for i, level in enumerate(["N5", "N4", "N3", "N2"])}
MAPPING_NOTE = "N2条件、责任与让步：按阅读功能归组；接续变体共享功能，相异义项分开检索。"
# filename, target, key, surface, ruby, old lemma, prior association, reviewed association
OLD_LINKS = [
    ("n5-expanded-context-words.tsv", "vn5766", "a", "回", "まわ", "回す", "vn5766", "vn5766"),
    ("n5-expanded-context-words.tsv", "vn5766", "b", "回", "まわ", "回す", "vn5766", "vn5766"),
    ("n3-temporal-and-change-words.tsv", "vn3f059", "b", "資金", "しきん", None, None, "vn3s005"),
    ("n3-temporal-and-change-words.tsv", "vn3f093", "b", "規模", "きぼ", None, None, "vn3s007"),
    ("n3-condition-and-perspective-words.tsv", "vn3j059", "b", "双方", "そうほう", None, None, "vn3s006"),
    ("n3-condition-and-perspective-words.tsv", "vn3j078", "b", "双方", "そうほう", None, None, "vn3s006"),
    ("n3-condition-and-perspective-words.tsv", "vn3j135", "b", "設", "もう", "設ける", None, "vn3s008"),
]
ORDINARY_WITNESSES = {
    "gn2c001": ("rn2201sb", "資料を預かったからには"),
    "gn2c002": ("rn2202sb", "毎日使うものだからこそ"),
    "gn2c003": ("rn2202sd", "異なる作業で試してこそ"),
    "gn2c004": ("rn2203sb", "使う機械が決まらないことには"),
    "gn2c005": ("rn2203sc", "確認が終わってからでないと"),
    "gn2c006": ("rn2204sb", "必要とする人がいる限り"),
    "gn2c007": ("rn2204sc", "場所の条件が変わらない限り"),
    "gn2c008": ("rn2205sb", "私が読んだ限りでは"),
    "gn2c009": ("rn2206sb", "会って聞けるものなら"),
    "gn2c010": ("rn2206sc", "公開しようものなら"),
    "gn2c011": ("rn2207sb", "入口の案内を新しくしたところで"),
    "gn2c012": ("rn2207sc", "必要だと認めるものの"),
    "gn2c013": ("rn2208sa", "忙しいながらも"),
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


@lru_cache(maxsize=None)
def previous(path):
    return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT)


def source_path(name):
    path = ROOT / "content/authoring" / name
    return path if path.exists() else ROOT / "content/staging" / name


def review_path(name):
    return ROOT / "content/staging" / (name.removesuffix(".tsv") + "-review.json")


def source_rows(name):
    return [line.split("\t") for line in source_path(name).read_text().splitlines()
            if line and not line.startswith("#")]


def expected_old_source(name):
    lines = previous("content/authoring/" + name).decode().splitlines(keepends=True)
    for source, target, key, surface, reading, lemma, before, wid in OLD_LINKS:
        if source != name:
            continue
        slots = [i for i, line in enumerate(lines) if line.startswith("\t".join(["E", target, key]) + "\t")]
        assert len(slots) == 1
        index = slots[0]
        original = f"[{surface}|{reading}" + ("|" + lemma if lemma else "") + "]"
        assert lines[index].count(original) == 1, (source, target, key, original)
        lines[index] = lines[index].replace(original, f"[{surface}|{reading}|@{wid}]")
    return "".join(lines).encode()


def sentence_text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(text):
    return {text[i:i + 20] for i in range(len(text) - 19)}


@lru_cache(maxsize=1)
def source_batches():
    data = previous(RESOURCE)
    assert sha(data) == BASELINE_SHA256, "Conditions checkpoint changed"
    before = json.loads(data)
    pack = copy.deepcopy(before)
    additions = json.loads(REFERENCES.read_text())["references"]
    assert len({r["id"] for r in additions}) == len(additions)
    assert all(re.fullmatch(r"[a-z0-9]+", r["id"]) for r in additions)
    assert not {r["id"] for r in additions} & {r["id"] for r in pack["references"]}
    pack["references"] += additions
    declared = {}
    for name in FILES[:2]:
        rows = source_rows(name)
        for r in rows:
            if r[0] == "W":
                assert r[1] not in declared
                declared[r[1]] = dict(id=r[1], kind="word", text=r[2], reading=r[3], meaning=r[5])
        for r in rows:
            if r[0] == "A": declared[r[1]]["acceptedReadings"] = r[2].split(",")
            if r[0] == "G": declared[r[1]]["lexemeID"] = r[2]
            if r[0] == "J": declared[r[1]]["jmdictEntryID"] = int(r[2])
    assert not declared.keys() & {w["id"] for w in before["items"]}
    indexed = dict(pack, items=pack["items"] + list(declared.values()))
    batches = {}
    for _ in range(2):
        for name in FILES[:2]:
            b = words(source_path(name), indexed)
            ids = {w["id"] for w in b["items"]}
            indexed["items"] = [w for w in indexed["items"] if w["id"] not in ids] + b["items"]
            batches[name] = b
    for b in batches.values():
        for key, rows in b.items(): pack[key].extend(copy.deepcopy(rows))
    batches[FILES[2]], coverage = grammar(source_path(FILES[2]), pack)
    for key, rows in batches[FILES[2]].items(): pack[key].extend(rows)
    batches[FILES[3]] = readings(source_path(FILES[3]), pack)
    for key, rows in batches[FILES[3]].items(): pack[key].extend(rows)
    pack["lessons"].sort(key=lambda l: STAGES[l["level"]])
    sentences = {s["id"]: s for s in pack["sentences"]}
    for _, target, key, surface, ruby, _, before_id, after_id in OLD_LINKS:
        slots = [s for s in sentences["s" + target + key]["segments"] if (s["text"], s["reading"]) == (surface, ruby)]
        assert len(slots) == 1 and slots[0]["itemID"] == before_id
        slots[0]["itemID"] = after_id
    return pack, batches, coverage


def check_sources():
    pack, batches, coverage = source_batches()
    before = json.loads(previous(RESOURCE))
    byid = {w["id"]: w for w in pack["items"]}
    lookup = word_lookup(pack["items"])
    oldroots = lexical_words(before["items"])
    oldentries = {w.get("jmdictEntryID") for w in oldroots}
    roots, targets, contexts = Counter(), 0, 0
    for name in FILES[:2]:
        b = batches[name]
        report = json.loads(review_path(name).read_text())
        assert sha(source_path(name).read_bytes()) == report["manuscriptSHA256"]
        assert report["independentLanguageReviews"] == 0 and report["nativeIOSCompiled"] is False
        assert report["unresolvedContextForms"] == {}
        assert report["dictionary"]["gzipSHA256"] == "96baa24218c052fef29de6d0f6fdb1aa35070ca5215f71580b62e8d03b671d36"
        assert report["communityReferenceCommit"] == "0d1d3410bec90bd4098a7c72de820543cb4f707c"
        facts = {f["itemID"]: f for f in report["entries"]}
        assert list(facts) == [w["id"] for w in b["items"]]
        for w in b["items"]:
            f = facts[w["id"]]
            assert (f["text"], f["primaryReading"], f["authoredMeaning"], f["entryID"]) == (w["text"], w["reading"], w["meaning"], w["jmdictEntryID"])
            assert f["exampleSentenceIDs"] == w["exampleSentenceIDs"] and w["text"] in f["dictionarySpellings"]
            assert (f["lexemeID"], f["readingOwnerID"]) == (w.get("lexemeID"), w.get("readingOwnerID"))
            assert f["acceptedAlternativeReadings"] == w.get("acceptedReadings", []) == []
            assert [s["ordinal"] for s in f["selectedSenseFacts"]] == f["senseOrdinals"]
            assert len(f["acceptedReadingSources"]) == 1
            r = f["acceptedReadingSources"][0]
            assert r["acceptedReading"] == w["reading"] and r["entryID"] == f["entryID"]
            assert r["senseOrdinals"] == f["senseOrdinals"] and r["readingFacts"]
            for rf in r["readingFacts"]:
                assert kana(rf["reading"]) == kana(w["reading"])
                assert not rf["spellingRestrictions"] or w["text"] in rf["spellingRestrictions"]
                assert not any(flag in info for info in rf["information"] for flag in ["obsolete", "out-dated", "search-only"])
            for sense in f["selectedSenseFacts"]:
                assert not sense["spellingRestrictions"] or w["text"] in sense["spellingRestrictions"]
                assert not sense["readingRestrictions"] or any(rf["reading"] in sense["readingRestrictions"] for rf in r["readingFacts"])
            if w.get("lexemeID"):
                assert w["id"] == "vn3s004" and w["lexemeID"] == w["readingOwnerID"] == "vn5766"
                assert f["senseOrdinals"] == [3] and f["entryID"] == 1199350
            else:
                assert f["entryID"] not in oldentries, (w["id"], "Repeated dictionary root")
                assert not any(old["text"] in f["dictionarySpellings"] and kana(old["reading"]) == kana(w["reading"]) for old in oldroots)
                roots[w["level"]] += 1
            targets += 1
        assert all(len(w["exampleSentenceIDs"]) == 2 for w in b["items"])
        contexts += len(b["sentences"])
    assert roots == {"N3": 7, "N2": 8} and targets == 16 and contexts == 32
    assert byid["vn3s008"]["jmdictEntryID"] == 1386000
    assert next(f for f in json.loads(review_path(FILES[0]).read_text())["entries"] if f["itemID"] == "vn3s008")["senseOrdinals"] == [1, 2]
    assert byid["vn2f002"]["jmdictEntryID"] == 2825953
    for name in FILES:
        for r in source_rows(name):
            if r[0] not in ["E", "C", "S"]: continue
            for surface, ruby, lemma in RUBY.findall(r[4] if r[0] == "S" else r[3]):
                assert lemma != "?", (name, r[1:3], "Hidden unreviewed word")
                if lemma == "-": continue
                linked = resolve_word(lookup, surface, ruby, lemma)
                assert linked, (name, r[1:3], surface, "Unresolved context word")
                if r[0] == "E": assert STAGES[linked["level"]] <= STAGES[byid[r[1]]["level"]]
    g, rb = [batches[n] for n in FILES[2:]]
    assert [w["id"] for w in g["items"]] == list(ORDINARY_WITNESSES)
    assert len(g["sentences"]) == len(g["exercises"]) == 78 and len(g["lessons"]) == 13 and len(coverage) == 12
    assert all(w["level"] == "N2" and len(w["exampleSentenceIDs"]) == 6 for w in g["items"])
    assert [r["id"] for r in rb["readings"]] == [f"rn22{i:02}" for i in range(1, 11)]
    assert Counter(r["purpose"] for r in rb["readings"]) == {"practice": 8, "assessment": 2}
    review = json.loads(REVIEW.read_text())
    assert review["sourceSHA256"] == {n: sha(source_path(n).read_bytes()) for n in FILES[2:]}
    assert review["independentLanguageReviews"] == 0 and review["nativeIOSCompiled"] is False
    assert [f["itemID"] for f in review["grammarFunctions"]] == list(ORDINARY_WITNESSES)
    for f in review["grammarFunctions"]:
        refs = [dict(c, status="reference") for c in f["primaryLocators"]]
        assert all(c in byid[f["itemID"]]["citations"] for c in refs)
        assert f["contexts"] == 6
    new = [s for b in batches.values() for s in b.get("sentences", [])]
    new_ids = {s["id"] for s in new}
    old = [s for s in before["sentences"]]
    texts = [sentence_text(s) for s in new]
    assert len(texts) == len(set(texts)) and not set(texts) & {sentence_text(s) for s in old}
    heldout_ids = {sid for r in before["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    old_fragments = set().union(*(fragments(sentence_text(s)) for s in old if s["id"] in heldout_ids))
    assert all(not fragments(t) & old_fragments for t in texts), "Earlier assessment reused"
    index = {s["id"]: s for s in pack["sentences"]}
    lengths, japanese = [], []
    for r in rb["readings"]:
        assert len(r["paragraphs"]) == 2 and len(r["questions"]) == 2 and len(r["sentenceIDs"]) == 6
        assert all(w["itemID"] for w in r["vocabulary"]) and all(p["vocabulary"] for p in r["paragraphs"])
        text = "".join(sentence_text(index[sid]) for sid in r["sentenceIDs"])
        lengths.append(len(text))
        japanese.append(sum("ぁ" <= ch <= "ゖ" or "ァ" <= ch <= "ヺ" or "一" <= ch <= "龯" for ch in text))
        assert japanese[-1] >= 350
        if r["purpose"] == "assessment":
            own = set(r["sentenceIDs"])
            heldout = set().union(*(fragments(sentence_text(index[sid])) for sid in own))
            leaks = [s["id"] for s in pack["sentences"] if s["id"] not in own and fragments(sentence_text(s)) & heldout]
            assert not leaks, (r["id"], "Assessment exposed elsewhere", leaks)
    for gid, (sid, anchor) in ORDINARY_WITNESSES.items():
        assert anchor in sentence_text(index[sid]), (gid, "Missing actual ordinary use")
        r = next(r for r in rb["readings"] if sid in r["sentenceIDs"])
        assert r["purpose"] == "practice" and gid in r["grammarIDs"]
    for key in COLLECTIONS:
        ids = [r["id"] for b in batches.values() for r in b.get(key, [])]
        assert len(ids) == len(set(ids)) and not set(ids) & {r["id"] for r in before.get(key, [])}
    validate(pack)
    return dict(newRoots=15, n3FoundationRoots=7, n2Roots=8, additionalSenses=1, wordTargets=16,
                wordContexts=32, grammarFunctions=13, grammarContexts=78, referencePatterns=12,
                readings=10, ordinaryReadings=8, assessments=2, readingQuestions=20, lessons=20,
                readingLengths=lengths, japaneseCharacterCounts=japanese, heldoutLeaks=0,
                independentLanguageReviews=0, nativeIOSCompiled=False)


def check_prior_changes(current=None):
    ledger = json.loads(LEDGER.read_text())
    assert (ledger["baselineCommit"], ledger["baselineRuntimeSHA256"]) == (BASELINE, BASELINE_SHA256)
    expected, batches, coverage = source_batches()
    after = current if current is not None else json.loads((ROOT / RESOURCE).read_text())
    later = None
    if (ROOT / "content/source-checks/n2-emotions-chapter.json").exists():
        from check_n2_emotions import check_prior_changes as check_emotions
        later = check_emotions(after)
        checkpoint = later["baselineCommit"]
        after = json.loads(subprocess.check_output(["git", "show", checkpoint + ":" + RESOURCE], cwd=ROOT))

    def current_data(path):
        if later is not None:
            return subprocess.check_output(["git", "show", checkpoint + ":" + path], cwd=ROOT)
        return (ROOT / path).read_bytes()

    assert after == expected, "Conditions differs from reconstruction or unreviewed historical data changed"
    assert ledger["manuscripts"] == FILES
    for n in FILES: assert sha(source_path(n).read_bytes()) == ledger["newSourceSHA256"][n]
    for path, digest in ledger["reviewSHA256"].items(): assert sha((ROOT / path).read_bytes()) == digest
    old_manifest = json.loads(previous("content/manuscripts.json"))
    additions = [dict(kind=kind, source=n, batch=f"{91+i:03}-{n.removesuffix('.tsv')}.json")
                 for i, (n, kind) in enumerate(zip(FILES, ["word", "word", "grammar", "reading"]))]
    assert ledger["manifestAdditions"] == additions
    assert json.loads(current_data("content/manuscripts.json")) == dict(old_manifest, entries=old_manifest["entries"] + additions)
    for e in additions:
        assert json.loads((ROOT / "content/batches" / e["batch"]).read_text()) == batches[e["source"]]
    for e in old_manifest["entries"]:
        n = e["source"]
        assert sha(previous("content/authoring/" + n)) == ledger["oldSourceInputSHA256"][n]
        assert current_data("content/authoring/" + n) == expected_old_source(n), (n, "Unreviewed earlier manuscript change")
    catalog = json.loads(previous("content/catalog.json"))
    catalog["references"] += json.loads(REFERENCES.read_text())["references"]
    assert json.loads(current_data("content/catalog.json")) == catalog
    syllabus = json.loads(previous("content/syllabus.json"))
    for pattern, ids in coverage.items():
        key = "N2:" + pattern
        assert key not in syllabus["grammarCoverage"]
        syllabus["grammarCoverage"][key] = dict(itemIDs=ids, note=MAPPING_NOTE)
    assert json.loads(current_data("content/syllabus.json")) == syllabus
    assert ledger["newIDs"] == {k: [r["id"] for b in batches.values() for r in b.get(k, [])] for k in COLLECTIONS}
    assert ledger["reviewedOldSentenceIDs"] == ["s" + target + key for _, target, key, *_ in OLD_LINKS]
    return dict(baselineCommit=BASELINE, oldSourcesChecked=len(old_manifest["entries"]),
                oldCollectionsPreservedExceptReviewedLinks=True, changedSentences=5,
                changedAssociations=5, preservedPhysicalAssociations=2, newRoots=15,
                grammarFunctions=13, newReadings=10,
                subsequentEmotionsChangesVerified=later is not None)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sources-only", action="store_true")
    args = p.parse_args()
    result = dict(source=check_sources())
    if not args.sources_only: result["compatibility"] = check_prior_changes()
    print(json.dumps(result, ensure_ascii=False))
