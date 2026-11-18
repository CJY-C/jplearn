#!/usr/bin/env python3
"""Check the morphology-rule addition against its immutable course checkpoint."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def check(current=None):
    ledger = json.loads((ROOT / "content/source-checks/rule-learning-transfer.json").read_text())
    resource = "Sources/LearningCore/Resources/foundation.json"
    baseline_data = subprocess.check_output(
        ["git", "show", ledger["baselineCommit"] + ":" + resource], cwd=ROOT)
    assert hashlib.sha256(baseline_data).hexdigest() == ledger["baselineRuntimeSHA256"], "Rule baseline changed"
    before = json.loads(baseline_data)
    after = current if current is not None else json.loads((ROOT / resource).read_text())
    source = (ROOT / ledger["ruleSource"]).read_bytes()
    assert hashlib.sha256(source).hexdigest() == ledger["sourceSHA256"], "Unreviewed rule source"
    rules = json.loads(source)["learningRules"]
    added = [r for r in rules if r["id"] in ledger["newRuleIDs"]]
    assert [r["id"] for r in added] == ledger["newRuleIDs"]
    assert all(not r["regularItemIDs"] for r in added), "Morphology cannot prove lemma knowledge"
    assert sum(len(r["practiceSets"]) for r in added) == ledger["newPracticeSets"]
    assert sum(len(s["questions"]) for r in added for s in r["practiceSets"]) == ledger["newQuestions"]
    assert before.keys() == after.keys(), "Unreviewed course metadata"
    for key in before.keys() - {"references", "learningRules"}:
        assert before[key] == after[key], (key, "Rule addition changed existing course data")
    assert after["references"] == before["references"] + ledger["newReferences"], "Unreviewed references"
    assert rules == before["learningRules"] + added, "Old rule changed"
    assert after["learningRules"] == rules, "Runtime rule/source mismatch"
    return dict(baselineCommit=ledger["baselineCommit"], oldCollectionsPreserved=True,
                oldRulesPreserved=len(before["learningRules"]), newRules=len(added),
                newQuestions=ledger["newQuestions"], newLexicalRoots=0, newGrammarFunctions=0)


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False))
