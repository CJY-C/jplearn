#!/usr/bin/env python3
"""Check registered N3 associations against the reviewed pre-registration pack.

Read-only. Uses the pinned local Git baseline, validates authored input/output
hashes, and compares every previously registered record and its relative order.
Only the94 reviewed sentence item associations may change.
"""
import copy
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def check():
    review = json.loads((ROOT / "content/staging/n3-similarity-prior-link-candidates.json").read_text())
    baseline = review["registration"]["baselineCommit"]
    checkpoint = None
    later_path = ROOT / "content/source-checks/n2-context-chapter.json"
    if later_path.exists():
        # Preserve the original N3 proof at its immutable checkpoint. Verify
        # every subsequent old-record change with the N2 ledger first, so a
        # historical comparison cannot conceal an unreviewed current change.
        from check_n2_prior_links import check as check_later
        check_later()
        checkpoint = json.loads(later_path.read_text())["baselineCommit"]

    def prior_bytes(name):
        return subprocess.check_output(["git", "show", baseline + ":" + name], cwd=ROOT)

    def checkpoint_bytes(name):
        if checkpoint:
            return subprocess.check_output(["git", "show", checkpoint + ":" + name], cwd=ROOT)
        return (ROOT / name).read_bytes()

    for name, expected in review["registeredInputHashes"].items():
        assert hashlib.sha256(prior_bytes(name)).hexdigest() == expected, (name, "stale reviewed baseline")
    for field in ["registeredWordHashes", "registeredOutputHashes"]:
        for name, expected in review[field].items():
            assert hashlib.sha256(checkpoint_bytes(name)).hexdigest() == expected, (name, "stale registered input")
    expected = {}
    for decision in review["entries"]:
        assert decision["reviewStatus"].startswith("contextual sense reviewed") and decision["reason"]
        row = checkpoint_bytes(decision["file"]).decode().splitlines()[decision["line"] - 1].split("\t")
        column = 3 if row[0] in ["E", "C"] else 4 if row[0] == "S" else 2
        assert row[column] == decision["markup"].replace(decision["marker"], decision["replacementMarker"]), decision["context"]
        expected[decision["context"]] = decision
    path = "Sources/LearningCore/Resources/foundation.json"
    before = json.loads(prior_bytes(path))
    after = json.loads(checkpoint_bytes(path))
    collections = ["items", "sentences", "exercises", "lessons", "readings", "introModules"]
    for key in before.keys() - set(collections) - {"version", "references"}:
        assert before[key] == after[key], (key, "existing pack metadata changed")
    old_reference_ids = {r["id"] for r in before["references"]}
    assert [r for r in after["references"] if r["id"] in old_reference_ids] == before["references"]
    extra_references = [r for r in after["references"] if r["id"] not in old_reference_ids]
    if extra_references:
        rule_review = json.loads((ROOT / "content/source-checks/rule-learning-foundations.json").read_text())
        assert extra_references == rule_review["catalogReferenceAdditions"], "Unreviewed reference addition"
    changed, preserved = [], []
    for key in collections:
        old_ids = {row["id"] for row in before[key]}
        current = {row["id"]: row for row in after[key]}
        assert old_ids <= current.keys(), (key, "old record missing")
        assert [row["id"] for row in before[key]] == [row["id"] for row in after[key] if row["id"] in old_ids], (key, "relative order changed")
        for original in before[key]:
            sid = original["id"]
            actual = current[sid]
            if original == actual:
                if key == "sentences" and sid in expected:
                    assert expected[sid]["decision"] == "preserveExisting", sid
                    preserved.append(sid)
                continue
            assert key == "sentences" and sid in expected, (key, sid, "unreviewed old record change")
            decision = expected[sid]
            normalized = copy.deepcopy(actual)
            assert len(original["segments"]) == len(normalized["segments"]), sid
            differences = 0
            for old_segment, new_segment in zip(original["segments"], normalized["segments"]):
                if old_segment != new_segment:
                    assert old_segment.get("itemID") == decision["previousTargetID"], sid
                    assert new_segment.get("itemID") == decision["chosenTargetID"], sid
                    new_segment["itemID"] = old_segment.get("itemID")
                    differences += 1
            assert differences == 1 and normalized == original, (sid, "text/ruby/translation/other field changed")
            changed.append(sid)
    assert len(changed) == review["counts"]["newAssociations"] == 94
    assert len(preserved) == review["counts"]["preserveExisting"] == 4
    assert set(changed + preserved) == expected.keys()
    return dict(status="registered associations and all prior runtime records checked; no files edited",
        baselineCommit=baseline, verifiedThroughCommit=checkpoint,
        subsequentCurrentChangesVerified=checkpoint is not None,
        reviewedOccurrences=len(expected), newAssociations=len(changed),
        preservedCityAssociations=len(preserved), redirectedWrongSenseCandidates=review["counts"]["redirectedWrongSenseCandidates"],
        oldItemsExercisesLessonsReadingsIntroAnswersAndRelativeOrderPreserved=True,
        oldSentenceTextRubyTranslationsAndOtherFieldsPreserved=True)


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False, indent=2))
