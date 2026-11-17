#!/usr/bin/env python3
"""Preflight the reviewed old-sentence links while the N3 chapter is staged.

Never edits authoring, batches or the runtime pack. Recompiles all registered
manuscripts using temporary reviewed annotations and the complete future word
index; checks that all old records and sentence text/ruby/answers are preserved.
"""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from compile_course import COMPILERS, entries
from compile_words import compile_manuscript as words
from check_n3_similarity import word_index


def check():
    review = json.loads((ROOT / "content/staging/n3-similarity-prior-link-candidates.json").read_text())
    for field in ["wordManuscriptHashes", "registeredInputHashes"]:
        for name, expected in review[field].items():
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, (name, "stale reviewed input")
    paths = [ROOT / name for name in review["wordManuscriptHashes"]]
    index = word_index(make_pack(), paths)
    for path in paths:
        batch = words(path, index)
        ids = {item["id"] for item in batch["items"]}
        index["items"] = [item for item in index["items"] if item["id"] not in ids] + batch["items"]
    targets = {item["id"]: item for item in index["items"]}
    patched = {name: (ROOT / name).read_text().splitlines() for name in review["registeredInputHashes"]}
    expected = {}
    for decision in review["entries"]:
        assert decision["reviewStatus"].startswith("contextual sense reviewed")
        assert decision["chosenTargetID"] in targets and decision["reason"]
        name, number = decision["file"], decision["line"] - 1
        row = patched[name][number].split("\t")
        column = 3 if row[0] in ["E", "C"] else 4 if row[0] == "S" else 2
        assert row[column] == decision["markup"], (name, number, "sentence changed after review")
        assert row[column].count(decision["marker"]) == 1
        row[column] = row[column].replace(decision["marker"], decision["replacementMarker"])
        patched[name][number] = "\t".join(row)
        expected[decision["context"]] = decision
    changed, preserved, checked = [], [], 0
    with tempfile.TemporaryDirectory(prefix="jplearn-reviewed-links-") as directory:
        temp = Path(directory)
        for record in entries():
            original_path = ROOT / "content/authoring" / record["source"]
            relative = str(original_path.relative_to(ROOT))
            path = original_path
            if relative in patched:
                path = temp / record["source"]
                path.write_text("\n".join(patched[relative]) + "\n")
            result = COMPILERS[record["kind"]](path, index)
            batch = result[0] if record["kind"] == "grammar" else result
            prior = json.loads((ROOT / "content/batches" / record["batch"]).read_text())
            assert prior.keys() == batch.keys(), record["batch"]
            for key in prior:
                if key != "sentences":
                    assert prior[key] == batch[key], (record["batch"], key, "old record or order changed")
                    continue
                assert [s["id"] for s in prior[key]] == [s["id"] for s in batch[key]]
                for before, after in zip(prior[key], batch[key]):
                    sid = before["id"]
                    if before == after:
                        if sid in expected:
                            assert expected[sid]["decision"] == "preserveExisting"
                            preserved.append(sid)
                        continue
                    assert sid in expected, (sid, "unreviewed annotation change")
                    decision = expected[sid]
                    assert decision["decision"] != "preserveExisting", sid
                    normalized = copy.deepcopy(after)
                    assert len(before["segments"]) == len(normalized["segments"]), sid
                    differences = 0
                    for old_segment, new_segment in zip(before["segments"], normalized["segments"]):
                        if old_segment != new_segment:
                            assert old_segment.get("itemID") == decision["previousTargetID"], sid
                            assert new_segment.get("itemID") == decision["chosenTargetID"], sid
                            new_segment["itemID"] = old_segment.get("itemID")
                            differences += 1
                    assert differences == 1 and normalized == before, (sid, "text, ruby or other field changed")
                    changed.append(sid)
            checked += 1
    assert len(changed) == review["counts"]["newAssociations"] == 94
    assert len(preserved) == review["counts"]["preserveExisting"] == 4
    assert set(changed + preserved) == expected.keys()
    return dict(status="preflight passed; no registered file or runtime pack edited",
        registeredManuscripts=checked, reviewedOccurrences=len(expected), newAssociations=len(changed),
        preservedCityAssociations=len(preserved), redirectedWrongSenseCandidates=review["counts"]["redirectedWrongSenseCandidates"],
        oldItemsExercisesLessonsReadingsAnswersAndRelativeOrderPreserved=True,
        oldSentenceTextRubyTranslationsAndOtherFieldsPreserved=True)


if __name__ == "__main__":
    print(json.dumps(check(), ensure_ascii=False, indent=2))
