#!/usr/bin/env python3
"""Rebuild the evidence vocabulary and prove its exact additions to the course."""
import copy
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import subprocess

from build_content import ROOT, validate
from compile_grammar import RUBY
from compile_words import compile_manuscript
from word_links import kana, lexical_words, resolve_word, word_lookup

FILES = ["n3-evidence-foundation-words.tsv", "n2-evidence-and-interpretation-words.tsv"]
LEDGER = ROOT / "content/source-checks/n2-evidence-chapter.json"
RESOURCE = "Sources/LearningCore/Resources/foundation.json"


@lru_cache(maxsize=None)
def previous(commit, path):
    return subprocess.check_output(["git", "show", commit + ":" + path], cwd=ROOT)


def baseline():
    ledger = json.loads(LEDGER.read_text())
    data = previous(ledger["baselineCommit"], RESOURCE)
    assert hashlib.sha256(data).hexdigest() == ledger["baselineRuntimeSHA256"]
    return ledger, json.loads(data)


def source_path(name):
    registered = ROOT / "content/authoring" / name
    return registered if registered.exists() else ROOT / "content/staging" / name


def source_batches():
    ledger, pack = baseline()
    # Seed only the two declared manuscripts. No generated new record can
    # supply a missing word, and the checkpoint is immutable.
    for name in FILES:
        declared = {}
        rows = [l.split("\t") for l in source_path(name).read_text().splitlines() if l and not l.startswith("#")]
        for r in rows:
            if r[0] == "W":
                declared[r[1]] = dict(id=r[1], kind="word", text=r[2], reading=r[3], meaning=r[5])
        for r in rows:
            if r[0] == "A": declared[r[1]]["acceptedReadings"] = r[2].split(",")
            if r[0] == "J": declared[r[1]]["jmdictEntryID"] = int(r[2])
        pack["items"].extend(declared.values())
    batches = {}
    for _ in range(2):
        for name in FILES:
            batch = compile_manuscript(source_path(name), pack)
            ids = {w["id"] for w in batch["items"]}
            pack["items"] = [w for w in pack["items"] if w["id"] not in ids] + batch["items"]
            batches[name] = batch
    return pack, batches


def check_sources():
    ledger, before = baseline()
    pack, batches = source_batches()
    lookup, items = word_lookup(pack["items"]), {w["id"]: w for w in pack["items"]}
    old_roots = lexical_words(before["items"])
    old_entries = {w["jmdictEntryID"] for w in old_roots if w.get("jmdictEntryID")}
    old_sentences = ["".join(s["text"] for s in sentence["segments"]) for sentence in before["sentences"]]
    heldout = {sid for r in before["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    fragments = {value[i:i + 20] for sentence, value in zip(before["sentences"], old_sentences)
                 if sentence["id"] in heldout for i in range(len(value) - 19)}
    seen, entries, totals = set(old_sentences), set(), {"N3": 0, "N2": 0}
    order = {level: i for i, level in enumerate(["N5", "N4", "N3", "N2"])}
    for name, batch in batches.items():
        path = source_path(name)
        review = json.loads((ROOT / "content/staging" / (path.stem + "-review.json")).read_text())
        assert hashlib.sha256(path.read_bytes()).hexdigest() == review["manuscriptSHA256"]
        facts = {f["itemID"]: f for f in review["entries"]}
        assert len(batch["items"]) == len(facts) == review["targets"] == review["roots"]
        assert len(batch["sentences"]) == review["contexts"]
        assert len(batch["lessons"]) == review["lessons"]
        for w in batch["items"]:
            f = facts[w["id"]]
            assert not w.get("lexemeID") and w["jmdictEntryID"] not in old_entries | entries
            entries.add(w["jmdictEntryID"])
            assert (w["text"], w["reading"], w["meaning"], w["jmdictEntryID"]) == (
                f["text"], f["primaryReading"], f["authoredMeaning"], f["entryID"])
            assert w.get("acceptedReadings", []) == f["acceptedAlternativeReadings"]
            assert w["exampleSentenceIDs"] == f["exampleSentenceIDs"]
            assert not any(old["text"] in f["dictionarySpellings"] and
                           kana(old["reading"]) in {kana(x) for x in [w["reading"]] + w.get("acceptedReadings", [])}
                           for old in old_roots), (w["id"], "existing dictionary spelling")
            assert [s["acceptedReading"] for s in f["acceptedReadingSources"]] == [w["reading"]] + w.get("acceptedReadings", [])
            for source in f["acceptedReadingSources"]:
                assert source["entryID"] == f["entryID"] and source["senseOrdinals"] == f["senseOrdinals"]
                assert source["readingFacts"]
                for r in source["readingFacts"]:
                    assert kana(r["reading"]) == kana(source["acceptedReading"])
                    assert not r["spellingRestrictions"] or w["text"] in r["spellingRestrictions"]
                    assert not any(flag in info for info in r["information"] for flag in ["obsolete", "out-dated", "search-only"])
                for sense in f["selectedSenseFacts"]:
                    assert not sense["spellingRestrictions"] or w["text"] in sense["spellingRestrictions"]
                    assert not sense["readingRestrictions"] or any(r["reading"] in sense["readingRestrictions"] for r in source["readingFacts"])
            totals[w["level"]] += 1
        for sentence in batch["sentences"]:
            value = "".join(s["text"] for s in sentence["segments"])
            assert value not in seen, (sentence["id"], "reused context")
            seen.add(value)
            assert not fragments.intersection(value[i:i + 20] for i in range(len(value) - 19)), sentence["id"]
            target = next(w for w in batch["items"] if sentence["id"] in w["exampleSentenceIDs"])
            assert any(s["itemID"] == target["id"] for s in sentence["segments"])
            assert all(order[items[s["itemID"]]["level"]] <= order[target["level"]]
                       for s in sentence["segments"] if s["itemID"]), target["id"]
        for line in path.read_text().splitlines():
            r = line.split("\t")
            if r[0] != "E": continue
            for surface, ruby, lemma in RUBY.findall(r[3]):
                if lemma not in {"-", "?"}:
                    assert resolve_word(lookup, surface, ruby, lemma), (r[1:3], lemma or surface)
        registered = ROOT / "content/batches" / ledger["batches"][name]
        assert json.loads(registered.read_text()) == batch, "Generated/source mismatch"
    assert totals == {"N3": 5, "N2": 96}
    complete = copy.deepcopy(before)
    for batch in batches.values():
        for key, rows in batch.items():
            assert not {r["id"] for r in complete[key]} & {r["id"] for r in rows}
            complete[key].extend(copy.deepcopy(rows))
    sentences = {s["id"]: s for s in complete["sentences"]}
    for edit in ledger["sentenceChanges"]:
        for change in edit["changes"]:
            segment = sentences[edit["id"]]["segments"][change["index"]]
            assert segment["itemID"] == change["before"]
            segment["itemID"] = change["after"]
    validate(complete)
    return dict(wordRoots=101, n2Roots=96, earlierRoots=5, contexts=202, exercises=101,
                lessons=14, heldoutLeaks=0, unresolvedContextForms=0, completeRebuiltPackValidated=True,
                independentLanguageReviews=0)


def check_prior_changes(current=None):
    ledger, before = baseline()
    after = current if current is not None else json.loads((ROOT / RESOURCE).read_text())
    later = None
    if (ROOT / "content/source-checks/n2-basis-chapter.json").exists():
        from check_n2_basis import check_prior_changes as check_basis
        later = check_basis(after)
        after = json.loads(previous(later["baselineCommit"], RESOURCE))
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    if later is not None:
        manifest = json.loads(previous(later["baselineCommit"], "content/manuscripts.json"))
    old_manifest = json.loads(previous(ledger["baselineCommit"], "content/manuscripts.json"))
    assert manifest["entries"] == old_manifest["entries"] + ledger["manifestAdditions"]
    assert {k: v for k, v in manifest.items() if k != "entries"} == {k: v for k, v in old_manifest.items() if k != "entries"}
    for name, expected in ledger["oldSourceInputSHA256"].items():
        path = "content/authoring/" + name
        assert hashlib.sha256(previous(ledger["baselineCommit"], path)).hexdigest() == expected
        output = ledger["oldSourceOutputSHA256"].get(name, expected)
        data = previous(later["baselineCommit"], path) if later is not None else (ROOT / path).read_bytes()
        assert hashlib.sha256(data).hexdigest() == output, (name, "unreviewed source change")
    for name, sha in ledger["newSourceSHA256"].items():
        assert hashlib.sha256(source_path(name).read_bytes()).hexdigest() == sha
    assert before.keys() == after.keys()
    expected_new = {key: {} for key in ledger["newIDs"]}
    for name in ledger["batches"].values():
        batch = json.loads((ROOT / "content/batches" / name).read_text())
        for key, rows in batch.items():
            expected_new[key].update({r["id"]: r for r in rows})
    for key in before.keys() - set(ledger["newIDs"]):
        assert before[key] == after[key], (key, "unreviewed metadata or rule change")
    edits = {r["id"]: r["changes"] for r in ledger["sentenceChanges"]}
    found = set()
    for key, added in ledger["newIDs"].items():
        ids = {r["id"] for r in before[key]}
        actual = {r["id"]: r for r in after[key]}
        assert len(actual) == len(after[key]) and ids <= actual.keys()
        assert actual.keys() - ids == set(added), (key, "unreviewed new record")
        assert [r["id"] for r in after[key] if r["id"] not in ids] == added
        assert expected_new[key].keys() == set(added)
        assert all(actual[identifier] == expected_new[key][identifier] for identifier in added), (key, "new record/source mismatch")
        assert [r["id"] for r in before[key]] == [r["id"] for r in after[key] if r["id"] in ids]
        for old in before[key]:
            normalized = copy.deepcopy(actual[old["id"]])
            if key == "sentences" and old["id"] in edits:
                for edit in edits[old["id"]]:
                    original, changed = old["segments"][edit["index"]], normalized["segments"][edit["index"]]
                    assert original["itemID"] == edit["before"] and changed["itemID"] == edit["after"]
                    changed["itemID"] = edit["before"]
                found.add(old["id"])
            assert normalized == old, (key, old["id"], "unreviewed old field change")
    assert found == edits.keys()
    return dict(baselineCommit=ledger["baselineCommit"], oldSourcesChecked=len(ledger["oldSourceInputSHA256"]),
                oldCollectionsPreservedExceptReviewedLinks=True, changedSentences=len(found),
                changedAssociations=sum(len(e) for e in edits.values()), newRoots=101,
                subsequentBasisChangesVerified=later is not None)


if __name__ == "__main__":
    print(json.dumps(dict(source=check_sources(), compatibility=check_prior_changes()), ensure_ascii=False))
