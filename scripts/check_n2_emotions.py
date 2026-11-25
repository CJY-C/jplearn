#!/usr/bin/env python3
"""Reconstruct emotion/relationship vocabulary and six reviewed earlier links.

Checks content authoring, primary-dictionary selections and historical integrity.
Independent Japanese review and native iOS delivery remain separate requirements.
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
from compile_grammar import RUBY
from compile_words import compile_manuscript
from word_links import kana, lexical_words, resolve_word, word_lookup

BASELINE = "00d73fa65e5c150c69bc2baf3eab9156f8509450"
BASELINE_SHA256 = "3898e2e4f81b5f94d7e32f6a419be9d161d09c9122c8486ee8a3d042b8f1603b"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"
FILES = ["n3-emotion-foundation-words.tsv", "n2-emotions-and-relationships.tsv"]
LEDGER = ROOT / "content/source-checks/n2-emotions-chapter.json"
COLLECTIONS = ["items", "sentences", "exercises", "lessons", "readings", "introModules", "learningRules"]
STAGES = {level: i for i, level in enumerate(["N5", "N4", "N3", "N2"])}
OLD_LINKS = [
    ("n3-judgment-and-belief.tsv", "vn3b081", "b", "柵", "さく", "vn3t001"),
    ("n3-condition-and-perspective-words.tsv", "vn3j135", "b", "柵", "さく", "vn3t001"),
    ("n3-similarity-reading-prerequisite-words.tsv", "vn3n076", "a", "柵", "さく", "vn3t001"),
    ("n3-relations-and-causes-words.tsv", "vn3h015", "b", "自然", "しぜん", "vn3t002"),
    ("n3-relations-and-causes-words.tsv", "vn3h163", "b", "自然", "しぜん", "vn3t002"),
    ("n3-relationships-and-expression.tsv", "vn3d019", "a", "けんか", "けんか", "vn3t003"),
]
SENSE_PAIRS = [("vn2g076", "vn2g077", 1188690, [2], [1]),
               ("vn2g089", "vn2g090", 1483900, [1], [2])]


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
    # This source also belongs to an earlier chapter's pinned word review.
    # Preserve its bytes: its unambiguous 柵 token resolves from the new index.
    # The full runtime reconstruction below still permits only the six links.
    if name == "n3-similarity-reading-prerequisite-words.tsv":
        return previous("content/authoring/" + name)
    lines = previous("content/authoring/" + name).decode().splitlines(keepends=True)
    for source, target, key, surface, ruby, wid in OLD_LINKS:
        if source != name: continue
        slots = [i for i, line in enumerate(lines) if line.startswith("\t".join(["E", target, key]) + "\t")]
        assert len(slots) == 1
        index = slots[0]
        original = f"[{surface}|{ruby}]"
        assert lines[index].count(original) == 1
        lines[index] = lines[index].replace(original, f"[{surface}|{ruby}|@{wid}]")
    return "".join(lines).encode()


def sentence_text(sentence):
    return "".join(s["text"] for s in sentence["segments"])


def fragments(text):
    return {text[i:i + 20] for i in range(len(text) - 19)}


@lru_cache(maxsize=1)
def source_batches():
    data = previous(RESOURCE)
    assert sha(data) == BASELINE_SHA256, "Emotion vocabulary checkpoint changed"
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
    assert not declared.keys() & {w["id"] for w in before["items"]}
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
            assert not {r["id"] for r in rows} & {r["id"] for r in pack[key]}
            pack[key].extend(copy.deepcopy(rows))
    pack["lessons"].sort(key=lambda lesson: STAGES[lesson["level"]])
    sentences = {s["id"]: s for s in pack["sentences"]}
    for _, target, key, surface, ruby, wid in OLD_LINKS:
        slots = [s for s in sentences["s" + target + key]["segments"] if (s["text"], s["reading"]) == (surface, ruby)]
        assert len(slots) == 1 and slots[0]["itemID"] is None
        slots[0]["itemID"] = wid
    return pack, batches


def check_sources():
    pack, batches = source_batches()
    before = json.loads(previous(RESOURCE))
    items = {w["id"]: w for w in pack["items"]}
    oldroots = lexical_words(before["items"])
    oldentries = {w.get("jmdictEntryID") for w in oldroots}
    lookup = word_lookup(pack["items"])
    heldout_ids = {sid for r in before["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    heldout = set().union(*(fragments(sentence_text(s)) for s in before["sentences"] if s["id"] in heldout_ids))
    seen = {sentence_text(s) for s in before["sentences"]}
    roots, targets, contexts, lessons = Counter(), 0, 0, 0
    all_facts = {}
    for name, batch in batches.items():
        review = json.loads(review_path(name).read_text())
        assert sha(source_path(name).read_bytes()) == review["manuscriptSHA256"]
        assert review["independentLanguageReviews"] == 0 and review["nativeIOSCompiled"] is False
        assert review["unresolvedContextForms"] == {}
        assert review["dictionary"]["gzipSHA256"] == "96baa24218c052fef29de6d0f6fdb1aa35070ca5215f71580b62e8d03b671d36"
        assert review["communityReferenceCommit"] == "0d1d3410bec90bd4098a7c72de820543cb4f707c"
        facts = {f["itemID"]: f for f in review["entries"]}
        assert list(facts) == [w["id"] for w in batch["items"]]
        all_facts.update(facts)
        for w in batch["items"]:
            f = facts[w["id"]]
            assert (f["text"], f["primaryReading"], f["authoredMeaning"], f["entryID"]) == (w["text"], w["reading"], w["meaning"], w["jmdictEntryID"])
            assert f["exampleSentenceIDs"] == w["exampleSentenceIDs"]
            assert (f["lexemeID"], f["readingOwnerID"]) == (w.get("lexemeID"), w.get("readingOwnerID"))
            assert f["acceptedAlternativeReadings"] == w.get("acceptedReadings", [])
            accepted = [w["reading"]] + w.get("acceptedReadings", [])
            assert [r["acceptedReading"] for r in f["acceptedReadingSources"]] == accepted
            assert [s["ordinal"] for s in f["selectedSenseFacts"]] == f["senseOrdinals"]
            kana_text = not re.search("[一-龯]", w["text"])
            assert w["text"] in f["dictionarySpellings"] or kana(w["text"]) in {kana(r) for r in f["dictionaryKanaForms"]}
            for value in accepted:
                if kana_text: assert kana(value) == kana(w["text"]), (w["id"], "Different kana text is not an alternate pronunciation")
            for source in f["acceptedReadingSources"]:
                assert source["entryID"] == f["entryID"] and source["senseOrdinals"] == f["senseOrdinals"]
                assert source["readingFacts"]
                for r in source["readingFacts"]:
                    assert kana(r["reading"]) == kana(source["acceptedReading"])
                    assert kana_text or not r["spellingRestrictions"] or w["text"] in r["spellingRestrictions"]
                    assert not any(flag in info for info in r["information"] for flag in ["obsolete", "out-dated", "search-only"])
                for s in f["selectedSenseFacts"]:
                    assert not s["spellingRestrictions"] or w["text"] in s["spellingRestrictions"]
                    assert not s["readingRestrictions"] or any(r["reading"] in s["readingRestrictions"] for r in source["readingFacts"])
            assert f["entryID"] not in oldentries
            assert not any(old["text"] in f["dictionarySpellings"] + f["dictionaryKanaForms"] and
                           kana(old["reading"]) in {kana(r) for r in accepted} for old in oldroots)
            roots[w["level"]] += not w.get("lexemeID")
            targets += 1
            assert len(w["exampleSentenceIDs"]) == 2
        for s in batch["sentences"]:
            text = sentence_text(s)
            assert text not in seen, (s["id"], "Repeated context")
            assert not fragments(text) & heldout, (s["id"], "Earlier assessment leaked")
            seen.add(text)
            target = next(w for w in batch["items"] if s["id"] in w["exampleSentenceIDs"])
            assert any(part["itemID"] == target["id"] for part in s["segments"])
            assert all(STAGES[items[part["itemID"]]["level"]] <= STAGES[target["level"]] for part in s["segments"] if part["itemID"])
            contexts += 1
        for r in source_rows(name):
            if r[0] != "E": continue
            for surface, ruby, lemma in RUBY.findall(r[3]):
                assert lemma != "?"
                if lemma != "-": assert resolve_word(lookup, surface, ruby, lemma), (name, r[1:3], surface)
        lessons += len(batch["lessons"])
    assert roots == {"N3": 3, "N2": 93} and (targets, contexts, lessons) == (98, 196, 17)
    for root, sense, identity, root_senses, extra_senses in SENSE_PAIRS:
        assert items[sense]["lexemeID"] == items[sense]["readingOwnerID"] == root
        assert items[root]["meaning"] != items[sense]["meaning"]
        assert all_facts[root]["entryID"] == all_facts[sense]["entryID"] == identity
        assert all_facts[root]["senseOrdinals"] == root_senses and all_facts[sense]["senseOrdinals"] == extra_senses
    assert {w["id"] for b in batches.values() for w in b["items"] if w.get("lexemeID")} == {s for _, s, *_ in SENSE_PAIRS}
    for wid, alternatives in {"vn2g026": ["めんどくさい"], "vn2g039": ["えばる"]}.items():
        assert items[wid]["acceptedReadings"] == alternatives
    for wid in ["vn2g036", "vn2g057", "vn2g091", "vn2g095"]: assert not items[wid].get("acceptedReadings")
    assert (items["vn2g057"]["jmdictEntryID"], items["vn2g091"]["jmdictEntryID"]) == (1535320, 1568640)
    grass = next(s for s in batches[FILES[1]]["sentences"] if s["id"] == "svn2g082a")
    assert any(s["itemID"] == "vn4868" for s in grass["segments"]) and all(s["itemID"] != "vn4869" for s in grass["segments"])
    validate(pack)
    return dict(newRoots=96, n2Roots=93, n3FoundationRoots=3, additionalSenses=2, targets=98,
                contexts=196, exercises=98, lessons=17, heldoutLeaks=0, unresolvedContextForms=0,
                independentLanguageReviews=0, nativeIOSCompiled=False)


def check_prior_changes(current=None):
    ledger = json.loads(LEDGER.read_text())
    assert (ledger["baselineCommit"], ledger["baselineRuntimeSHA256"]) == (BASELINE, BASELINE_SHA256)
    expected, batches = source_batches()
    after = current if current is not None else json.loads((ROOT / RESOURCE).read_text())
    later = None
    if (ROOT / "content/source-checks/n2-change-chapter.json").exists():
        from check_n2_change import check_prior_changes as check_changes
        later = check_changes(after)
        checkpoint = later["baselineCommit"]
        after = json.loads(subprocess.check_output(["git", "show", checkpoint + ":" + RESOURCE], cwd=ROOT))

    def current_data(path):
        if later is not None:
            return subprocess.check_output(["git", "show", checkpoint + ":" + path], cwd=ROOT)
        return (ROOT / path).read_bytes()

    assert after == expected, "Emotions differs from reconstruction or unreviewed historical data changed"
    assert ledger["manuscripts"] == FILES
    for n in FILES:
        assert sha(source_path(n).read_bytes()) == ledger["newSourceSHA256"][n]
        assert sha(review_path(n).read_bytes()) == ledger["reviewSHA256"][str(review_path(n).relative_to(ROOT))]
    old_manifest = json.loads(previous("content/manuscripts.json"))
    additions = [dict(kind="word", source=n, batch=f"{95+i:03}-{n.removesuffix('.tsv')}.json") for i, n in enumerate(FILES)]
    assert ledger["manifestAdditions"] == additions
    assert json.loads(current_data("content/manuscripts.json")) == dict(old_manifest, entries=old_manifest["entries"] + additions)
    for e in additions: assert json.loads((ROOT / "content/batches" / e["batch"]).read_text()) == batches[e["source"]]
    for e in old_manifest["entries"]:
        n = e["source"]
        assert sha(previous("content/authoring/" + n)) == ledger["oldSourceInputSHA256"][n]
        assert current_data("content/authoring/" + n) == expected_old_source(n), (n, "Unreviewed earlier source change")
    for p in ["content/catalog.json", "content/syllabus.json"]: assert current_data(p) == previous(p)
    assert ledger["newIDs"] == {k: [r["id"] for b in batches.values() for r in b.get(k, [])] for k in COLLECTIONS}
    assert ledger["reviewedOldSentenceIDs"] == ["s" + target + key for _, target, key, *_ in OLD_LINKS]
    return dict(baselineCommit=BASELINE, oldSourcesChecked=len(old_manifest["entries"]),
                oldCollectionsPreservedExceptReviewedLinks=True, changedSentences=6,
                changedAssociations=6, newRoots=96, n2Roots=93,
                subsequentChangesVerified=later is not None)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sources-only", action="store_true")
    args = p.parse_args()
    result = dict(source=check_sources())
    if not args.sources_only: result["compatibility"] = check_prior_changes()
    print(json.dumps(result, ensure_ascii=False))
