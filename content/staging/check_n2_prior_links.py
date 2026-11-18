#!/usr/bin/env python3
"""Verify every old record against the exact reviewed N2 association deltas."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))


def check():
    ledger = json.loads((ROOT / "content/source-checks/n2-context-chapter.json").read_text())
    baseline = ledger["baselineCommit"]

    def previous(name):
        return subprocess.check_output(["git", "show", baseline + ":" + name], cwd=ROOT)

    resource = "Sources/LearningCore/Resources/foundation.json"
    data = previous(resource)
    assert hashlib.sha256(data).hexdigest() == ledger["baselineRuntimeSHA256"], "Baseline changed"
    before = json.loads(data)
    after = json.loads((ROOT / resource).read_text())
    # Prove current changes first, then reproduce this chapter's original proof
    # at the reviewed checkpoint. Neither audit permits arbitrary later records.
    subsequent = None
    if (ROOT / "content/source-checks/rule-learning-transfer.json").exists():
        from check_rule_transfer import check as check_rule_transfer
        subsequent = check_rule_transfer(after)
        after = json.loads(previous_at(subsequent["baselineCommit"], resource))
    for name, sha in ledger["sourceInputSHA256"].items():
        path = "content/authoring/" + name
        assert hashlib.sha256(previous(path)).hexdigest() == sha, (name, "input hash")
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == ledger["sourceOutputSHA256"][name], (name, "reviewed output hash")
    for key in before.keys() - {"references"} - set(ledger["newIDs"]):
        assert before[key] == after[key], (key, "unreviewed metadata change")
    old_refs = {r["id"] for r in before["references"]}
    assert [r for r in after["references"] if r["id"] in old_refs] == before["references"]
    extra = [r for r in after["references"] if r["id"] not in old_refs]
    expected_refs = json.loads((ROOT / "content/staging/n2-context-additional-references.json").read_text())["references"]
    assert extra == expected_refs and [r["id"] for r in extra] == ledger["newReferenceIDs"]
    sentence_changes = {r["id"]: r["changes"] for r in ledger["sentenceChanges"]}
    reading_changes = {r["id"]: r["changes"] for r in ledger["readingChanges"]}
    found_sentences, found_readings = set(), set()
    for key, added in ledger["newIDs"].items():
        old_ids = {r["id"] for r in before[key]}
        current = {r["id"]: r for r in after[key]}
        assert len(current) == len(after[key]) and old_ids <= current.keys(), (key, "missing/duplicate old record")
        assert current.keys() - old_ids == set(added), (key, "unexpected added or missing new record")
        assert [r["id"] for r in before[key]] == [r["id"] for r in after[key] if r["id"] in old_ids], (key, "old relative order")
        for original in before[key]:
            identifier = original["id"]
            normalized = copy.deepcopy(current[identifier])
            if key == "sentences" and identifier in sentence_changes:
                for edit in sentence_changes[identifier]:
                    old = original["segments"][edit["index"]]
                    actual = normalized["segments"][edit["index"]]
                    assert old["itemID"] == edit["before"] and actual["itemID"] == edit["after"], identifier
                    actual["itemID"] = edit["before"]
                found_sentences.add(identifier)
            elif key == "readings" and identifier in reading_changes:
                for edit in reading_changes[identifier]:
                    a = original if edit["field"] == "vocabulary" else original["paragraphs"][edit["paragraph"]]
                    b = normalized if edit["field"] == "vocabulary" else normalized["paragraphs"][edit["paragraph"]]
                    assert a["vocabulary"][edit["index"]]["itemID"] == edit["before"], identifier
                    assert b["vocabulary"][edit["index"]]["itemID"] == edit["after"], identifier
                    b["vocabulary"][edit["index"]]["itemID"] = edit["before"]
                found_readings.add(identifier)
            assert normalized == original, (key, identifier, "unreviewed text/ruby/Chinese/answer/other field change")
    assert found_sentences == sentence_changes.keys() and found_readings == reading_changes.keys()
    return dict(status="Every old record checked against reviewed associations; text/ruby/Chinese/answers/pitch annotations and relative order preserved",
        baselineCommit=baseline, reviewedOccurrences=ledger["reviewedOccurrences"],
        changedSentences=len(found_sentences), changedReadings=len(found_readings),
        changedSentenceAssociations=sum(len(v) for v in sentence_changes.values()),
        newIDs={k: len(v) for k, v in ledger["newIDs"].items()},
        subsequentRuleChangesVerified=subsequent is not None,
        verifiedThroughCommit=subsequent["baselineCommit"] if subsequent else None)


def previous_at(commit, name):
    return subprocess.check_output(["git", "show", commit + ":" + name], cwd=ROOT)


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False))
