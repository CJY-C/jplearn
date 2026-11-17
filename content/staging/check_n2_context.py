#!/usr/bin/env python3
"""Check this unregistered N2 draft without changing the bundled curriculum.

Checks source compilation, context/ID/prerequisite structure and assessment
isolation. Unresolved forms are candidates; linked word senses still need human
contextual review. Success does not register content or certify language quality.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from compile_grammar import RUBY, compile_manuscript
from word_links import resolve_word, word_lookup


def check():
    path = ROOT / "content/staging/n2-context-and-mediation.tsv"
    pack = make_pack()
    batch, coverage = compile_manuscript(path, pack)
    new = {i["id"]: i for i in batch["items"]}
    items = {i["id"]: i for i in pack["items"]}
    assert not new.keys() & items.keys(), "Registered target collision"
    for key, rows in batch.items():
        ids = [r["id"] for r in rows]
        assert len(set(ids)) == len(ids) and not set(ids) & {r["id"] for r in pack[key]}, key
    for item in new.values():
        assert item["level"] == "N2"
        assert set(item["prerequisiteIDs"]) <= items.keys() | new.keys(), item["id"]
    # A draft must not use a self-reference or an internal prerequisite cycle.
    active, visited = set(), set()

    def visit(gid):
        assert gid not in active, (gid, "prerequisite cycle")
        if gid in visited or gid not in new:
            return
        active.add(gid)
        for parent in new[gid]["prerequisiteIDs"]:
            visit(parent)
        active.remove(gid)
        visited.add(gid)

    for gid in new:
        visit(gid)
    sentences = {s["id"]: s for s in batch["sentences"]}

    def text(sentence):
        return "".join(s["text"] for s in sentence["segments"])

    values = [text(s) for s in batch["sentences"]]
    assert len(set(values)) == len(values), "Repeated draft context"
    for gid in new:
        exercises = [e for e in batch["exercises"] if e["targetID"] == gid]
        assert len({text(sentences[e["sentenceID"]]) for e in exercises}) >= 6, gid
    reference = json.loads((ROOT / "content/reference/openjlpt-grammar.json").read_text())
    expected = {r["id"] for r in reference["patterns"] if r["level"] == "N2"}
    assert coverage.keys() <= expected, "Unrecognized N2 pattern"
    heldout = {sid for r in pack["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    heldout_text = [text(s) for s in pack["sentences"] if s["id"] in heldout]
    fragments = {t[i:i + 20] for t in heldout_text for i in range(len(t) - 19)}
    for sid, sentence in sentences.items():
        value = text(sentence)
        assert value not in heldout_text
        assert not fragments.intersection(value[i:i + 20] for i in range(len(value) - 19)), sid
    gaps, lookup = defaultdict(list), word_lookup(pack["items"])
    for line in path.read_text().splitlines():
        row = line.split("\t")
        if row[0] != "C":
            continue
        for surface, reading, lemma in RUBY.findall(row[3]):
            if lemma not in {"-", "?"} and not resolve_word(lookup, surface, reading, lemma):
                gaps[lemma or surface].append(row[1] + row[2])
    resource = ROOT / "Sources/LearningCore/Resources/foundation.json"
    return dict(status="Unregistered draft; source/structure/isolation checked, contextual word-sense and independent language review pending",
        manuscript=str(path.relative_to(ROOT)), manuscriptSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),
        baselineRuntimeVersion=pack["version"], baselineRuntimeSHA256=hashlib.sha256(resource.read_bytes()).hexdigest(),
        draftGrammarFunctions=len(new), draftOriginalContexts=len(sentences), draftExercises=len(batch["exercises"]),
        draftLessons=len(batch["lessons"]), draftReferencePatterns=coverage, registeredNewN2Targets=0,
        heldoutFragmentCharacters=20, heldoutLeaks=0, unresolvedForms=len(gaps), gaps=dict(sorted(gaps.items())),
        independentLanguageReviews=0, remaining=["Review all contextual word links and teach any missing meanings/readings.",
            "Write and isolate ordinary/assessment readings, connect actual grammar use, and complete chapter vocabulary.",
            "Register only after source checks, regenerate and run curriculum/native validation.",
            "Preserve the additional2500 N2 roots,140 grammar points,140 readings,100 lessons,28 assessments and six3-reading bridges."])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-report", action="store_true")
    args = parser.parse_args()
    result = check()
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    report = ROOT / "content/staging/n2-context-and-mediation-review.json"
    if args.update_report:
        report.write_text(encoded)
    else:
        assert report.read_text() == encoded, "Review the changed draft, then --update-report"
    print(json.dumps({k: result[k] for k in ["draftGrammarFunctions", "draftOriginalContexts", "draftExercises",
        "draftLessons", "unresolvedForms", "heldoutLeaks", "registeredNewN2Targets"]}, ensure_ascii=False))
